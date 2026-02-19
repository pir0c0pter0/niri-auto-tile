#!/usr/bin/env python3
"""Auto-tile for niri: redistributes column widths evenly (max N visible).

Listens to niri's JSON event stream and automatically resizes all tiling
columns to equal widths whenever a window is opened or closed.

Fixes applied from multi-perspective security/quality review:
- JSON event parsing instead of fragile substring matching
- Per-workspace state tracking (not global)
- Thread-safe lock on shared state
- Structured logging with levels
- Rate limiting / circuit breaker for event floods
- Reconnection loop if event stream dies
- SIGTERM handler for graceful shutdown
- Input validation on IPC responses
- Column count cap for safety
"""

import argparse
import json
import logging
import signal
import subprocess
import threading
import time

# ─── Configuration (overridable via CLI args) ───
MAX_VISIBLE = 4
MAX_COLUMNS = 20
DEBOUNCE_SECONDS = 0.3
NIRI_TIMEOUT = 5
RECONNECT_DELAY = 2.0
MAX_EVENTS_PER_SECOND = 20

# ─── Logging ───
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s auto-tile: %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("auto-tile")

# ─── State ───
_prev_col_counts: dict[int, int] = {}  # workspace_id -> column count
_known_window_ids: set[int] = set()    # track known windows to detect new ones
_debounce_timer: threading.Timer | None = None
_lock = threading.Lock()
_event_count = 0
_event_window_start = 0.0


# ─── Validation ───
def _valid_id(value) -> int | None:
    """Validate that value is a non-negative integer."""
    try:
        val = int(value)
        return val if val >= 0 else None
    except (TypeError, ValueError):
        return None


# ─── Niri IPC ───
def niri_cmd(*args) -> str:
    """Run a niri msg command and return stdout."""
    try:
        result = subprocess.run(
            ["niri", "msg", *args],
            capture_output=True, text=True, timeout=NIRI_TIMEOUT,
        )
        if result.returncode != 0:
            log.warning("niri msg %s rc=%d: %s", args, result.returncode, result.stderr.strip())
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        log.warning("niri msg %s timed out", args)
        return ""
    except FileNotFoundError:
        log.error("niri binary not found")
        return ""
    except OSError as exc:
        log.error("niri msg %s error: %s", args, exc)
        return ""


def niri_action(*args) -> None:
    """Run a niri msg action."""
    try:
        result = subprocess.run(
            ["niri", "msg", "action", *args],
            capture_output=True, timeout=NIRI_TIMEOUT,
        )
        if result.returncode != 0:
            log.debug("niri action %s rc=%d", args, result.returncode)
    except subprocess.TimeoutExpired:
        log.warning("niri action %s timed out", args)
    except OSError as exc:
        log.error("niri action %s error: %s", args, exc)


# ─── Queries ───
def get_focused_workspace() -> tuple[int | None, int | None]:
    """Get (workspace_id, focused_window_id)."""
    raw = niri_cmd("-j", "focused-window")
    if not raw:
        return None, None
    try:
        data = json.loads(raw)
        return _valid_id(data.get("workspace_id")), _valid_id(data.get("id"))
    except json.JSONDecodeError:
        log.warning("failed to parse focused-window JSON")
        return None, None


def _get_windows() -> list[dict]:
    """Fetch all windows from niri IPC (single shared call)."""
    raw = niri_cmd("-j", "windows")
    if not raw:
        return []
    try:
        windows = json.loads(raw)
        if not isinstance(windows, list):
            log.warning("unexpected windows JSON type: %s", type(windows).__name__)
            return []
        return [w for w in windows if isinstance(w, dict)]
    except json.JSONDecodeError:
        log.warning("failed to parse windows JSON")
        return []


def count_columns(workspace_id: int) -> int:
    """Count unique tiling columns in the given workspace."""
    cols: set[int] = set()
    for w in _get_windows():
        if w.get("workspace_id") != workspace_id:
            continue
        if w.get("is_floating", False):
            continue
        layout = w.get("layout")
        if not isinstance(layout, dict):
            continue
        pos = layout.get("pos_in_scrolling_layout")
        if isinstance(pos, (list, tuple)) and len(pos) > 0:
            col_idx = _valid_id(pos[0])
            if col_idx is not None:
                cols.add(col_idx)
    return len(cols)


def get_all_window_ids() -> set[int]:
    """Get set of all current window IDs."""
    return {w["id"] for w in _get_windows() if "id" in w}


# ─── Core Logic ───
def redistribute() -> None:
    """Redistribute all columns evenly, only if column count changed."""
    ws_id, focused_id = get_focused_workspace()
    if ws_id is None:
        return

    col_count = count_columns(ws_id)
    if col_count == 0:
        return

    # Safety cap
    if col_count > MAX_COLUMNS:
        log.warning("col_count=%d exceeds max=%d, capping", col_count, MAX_COLUMNS)
        col_count = MAX_COLUMNS

    # Thread-safe check: skip if column count unchanged for this workspace
    with _lock:
        if col_count == _prev_col_counts.get(ws_id):
            return
        _prev_col_counts[ws_id] = col_count

    # Re-verify workspace hasn't changed before applying actions
    current_ws, _ = get_focused_workspace()
    if current_ws != ws_id:
        log.debug("workspace changed %d -> %s during redistribute, skipping", ws_id, current_ws)
        with _lock:
            _prev_col_counts.pop(ws_id, None)
        return

    visible = min(col_count, MAX_VISIBLE)
    base_pct = 100 // visible
    remainder = 100 - (base_pct * visible)
    log.info("ws=%d: %d cols -> %d%% each (+%d%% last)", ws_id, col_count, base_pct, remainder)

    # Walk columns and set widths
    niri_action("focus-column-first")
    for i in range(col_count):
        pct = f"{base_pct + remainder}%" if i == col_count - 1 and remainder > 0 else f"{base_pct}%"
        niri_action("set-column-width", pct)
        if i < col_count - 1:
            niri_action("focus-column-right")

    # Force viewport recalculation
    niri_action("focus-column-first")
    niri_action("center-visible-columns")

    # Restore original focus
    if focused_id is not None:
        niri_action("focus-window", "--id", str(focused_id))
        niri_action("center-visible-columns")


def debounced_redistribute() -> None:
    """Debounce + rate limit before redistributing."""
    global _debounce_timer, _event_count, _event_window_start

    now = time.monotonic()

    with _lock:
        # Rate limiter: sliding window
        if now - _event_window_start > 1.0:
            _event_window_start = now
            _event_count = 0
        _event_count += 1
        if _event_count > MAX_EVENTS_PER_SECOND:
            log.debug("rate limit exceeded, dropping event")
            return

        # Cancel previous timer, start new one
        if _debounce_timer is not None:
            _debounce_timer.cancel()
        _debounce_timer = threading.Timer(DEBOUNCE_SECONDS, redistribute)
        _debounce_timer.start()


# ─── Event Processing ───
def should_redistribute(event: dict) -> bool:
    """Determine if an event warrants redistribution.

    Only triggers on actual window open/close, NOT title changes.
    """
    global _known_window_ids

    if "WindowClosed" in event:
        win_id = event["WindowClosed"].get("id")
        if win_id is not None:
            with _lock:
                _known_window_ids.discard(win_id)
        return True

    if "WindowOpenedOrChanged" in event:
        window = event["WindowOpenedOrChanged"].get("window", {})
        win_id = window.get("id")
        if win_id is not None:
            with _lock:
                if win_id not in _known_window_ids:
                    _known_window_ids.add(win_id)
                    return True
            return False
        return False

    if "WindowsChanged" in event:
        # Batch event (startup) — sync known IDs
        windows = event["WindowsChanged"].get("windows") or []
        if not isinstance(windows, list):
            return False
        new_ids = {w["id"] for w in windows if isinstance(w, dict) and "id" in w}
        with _lock:
            if new_ids != _known_window_ids:
                _known_window_ids = new_ids
                return True
        return False

    return False


def run_event_loop() -> None:
    """Connect to niri event stream and process events."""
    global _known_window_ids, _debounce_timer, _event_count, _event_window_start

    # Cancel any pending timer from previous cycle and reset rate limiter
    with _lock:
        if _debounce_timer is not None:
            _debounce_timer.cancel()
            _debounce_timer = None
        _event_count = 0
        _event_window_start = 0.0
        # Initialize known windows under lock
        _known_window_ids = get_all_window_ids()
    log.info("tracking %d existing windows", len(_known_window_ids))

    # Initialize per-workspace column counts
    ws_id, _ = get_focused_workspace()
    if ws_id is not None:
        with _lock:
            _prev_col_counts[ws_id] = count_columns(ws_id)
        log.info("ws=%d initial cols=%d", ws_id, _prev_col_counts.get(ws_id, 0))

    proc = subprocess.Popen(
        ["niri", "msg", "-j", "event-stream"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )

    try:
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            if not isinstance(event, dict):
                continue

            if should_redistribute(event):
                debounced_redistribute()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


# ─── CLI ───
def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Auto-tile daemon for niri — redistributes column widths evenly.",
    )
    parser.add_argument(
        "--max-visible", type=int, default=None,
        help=f"max columns visible on screen (default: {MAX_VISIBLE})",
    )
    parser.add_argument(
        "--debounce", type=float, default=None,
        help=f"debounce delay in seconds (default: {DEBOUNCE_SECONDS})",
    )
    parser.add_argument(
        "--max-events", type=int, default=None,
        help=f"max events per second (default: {MAX_EVENTS_PER_SECOND})",
    )
    parser.add_argument(
        "--debug", action="store_true",
        help="enable debug logging",
    )
    return parser.parse_args()


# ─── Main ───
def main() -> None:
    """Main entry point with reconnection loop."""
    global MAX_VISIBLE, DEBOUNCE_SECONDS, MAX_EVENTS_PER_SECOND

    args = parse_args()

    # Apply CLI overrides
    if args.max_visible is not None:
        MAX_VISIBLE = max(1, args.max_visible)
    if args.debounce is not None:
        DEBOUNCE_SECONDS = max(0.05, args.debounce)
    if args.max_events is not None:
        MAX_EVENTS_PER_SECOND = max(1, args.max_events)
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # Handle SIGTERM for graceful shutdown
    def _shutdown(signum, frame):
        # Timer.cancel() is thread-safe; avoid _lock here to prevent deadlock
        t = _debounce_timer
        if t is not None:
            t.cancel()
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, _shutdown)

    log.info("starting (max_visible=%d, debounce=%gms)", MAX_VISIBLE, DEBOUNCE_SECONDS * 1000)

    while True:
        try:
            run_event_loop()
            log.warning("event stream ended, reconnecting in %gs", RECONNECT_DELAY)
        except KeyboardInterrupt:
            log.info("shutting down")
            break
        except Exception as exc:
            log.error("event loop crashed: %s, reconnecting in %gs", exc, RECONNECT_DELAY)
        time.sleep(RECONNECT_DELAY)


if __name__ == "__main__":
    main()

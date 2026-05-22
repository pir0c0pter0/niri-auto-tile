#!/usr/bin/env python3
"""Auto-tile for niri: redistributes column widths evenly (max N visible).

Listens to niri's JSON event stream and automatically resizes all tiling
columns to equal widths whenever a window is opened or closed.

Supports per-workspace max-visible settings via --workspace-config.
"""

import argparse
import json
import logging
import os
import re
import select
import signal
import subprocess
import threading
import time

# ─── Configuration (overridable via CLI args) ───
MAX_VISIBLE = 4
MAX_COLUMNS = 20
DEBOUNCE_SECONDS = 0.3
OPEN_DEBOUNCE_SECONDS = 0.1
CLOSE_DEBOUNCE_SECONDS = 0.05
MAX_DEBOUNCE_SECONDS = 0.75
ANCHOR_SETTLE_SECONDS = 0.03
OPEN_RETRY_DELAY_SECONDS = 0.15
OPEN_RETRY_ATTEMPTS = 3
NIRI_TIMEOUT = 5
NIRI_QUERY_TIMEOUT = 1.0
FOCUS_QUERY_TIMEOUT = 0.35
RECONNECT_DELAY = 2.0
MAX_EVENTS_PER_SECOND = 20
PER_WORKSPACE = False
WORKSPACE_MAX_VISIBLE: dict[int, int] = {}
KEEP_MAX_WIDTH = False
CONFIG_FILE: str = ""
NIRI_CONFIG_FILE = os.path.expanduser("~/.config/niri/config.kdl")

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
_windows_by_id: dict[int, dict] = {}   # event-stream mirror, keyed by window ID
_debounce_timer: threading.Timer | None = None
_debounce_started_at: float | None = None
_lock = threading.Lock()
_event_count = 0
_event_window_start = 0.0
_pending_event: dict | None = None  # open/close/full context for debounced resize
_config_reload_requested = threading.Event()


# ─── Validation ───
def _valid_id(value) -> int | None:
    """Validate that value is a non-negative integer."""
    try:
        val = int(value)
        return val if val >= 0 else None
    except (TypeError, ValueError):
        return None


def _int_at_least(value, minimum: int, fallback: int) -> int:
    """Convert value to int, enforcing a lower bound."""
    try:
        return max(minimum, int(value))
    except (TypeError, ValueError):
        return fallback


def _milliseconds_to_seconds(value, fallback: float) -> float:
    """Convert a millisecond config value to seconds."""
    try:
        return max(0.05, float(value) / 1000.0)
    except (TypeError, ValueError):
        return fallback


def get_max_visible(ws_id: int) -> int:
    """Get max visible columns for a workspace."""
    if PER_WORKSPACE and ws_id in WORKSPACE_MAX_VISIBLE:
        return WORKSPACE_MAX_VISIBLE[ws_id]
    return MAX_VISIBLE


def _default_column_width_proportion() -> str:
    """Return the niri default-column-width proportion for current auto-tile config."""
    max_visible = max(1, int(MAX_VISIBLE))
    return f"{1 / max_visible:.5f}".rstrip("0").rstrip(".")


# ─── Niri IPC ───
def niri_cmd(*args, timeout: float | None = None) -> str:
    """Run a niri msg command and return stdout."""
    cmd_timeout = NIRI_TIMEOUT if timeout is None else timeout
    try:
        result = subprocess.run(
            ["niri", "msg", *args],
            capture_output=True, text=True, timeout=cmd_timeout,
        )
        if result.returncode != 0:
            log.warning("niri msg %s rc=%d: %s", args, result.returncode, result.stderr.strip())
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        log.warning("niri msg %s timed out after %gs", args, cmd_timeout)
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


def _strip_kdl_line_comment(line: str) -> str:
    """Strip // comments for simple brace-depth scanning."""
    return line.split("//", 1)[0]


def _find_top_level_layout(lines: list[str]) -> tuple[int, int] | None:
    """Return (start, end) indexes for the top-level niri layout block."""
    depth = 0
    layout_start: int | None = None

    for idx, line in enumerate(lines):
        code = _strip_kdl_line_comment(line)
        stripped = code.strip()
        if layout_start is None and depth == 0 and re.match(r"^layout\s*\{", stripped):
            layout_start = idx

        depth += code.count("{") - code.count("}")

        if layout_start is not None and depth == 0:
            return layout_start, idx

    return None


def sync_niri_default_column_width() -> None:
    """Keep niri's new-window width aligned with the auto-tile maxVisible value."""
    path = NIRI_CONFIG_FILE
    if not os.path.isfile(path):
        log.warning("niri config not found: %s", path)
        return

    proportion = _default_column_width_proportion()
    target_line = f"default-column-width {{ proportion {proportion}; }}"

    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError as exc:
        log.warning("failed to read niri config %s: %s", path, exc)
        return

    layout_span = _find_top_level_layout(lines)
    if layout_span is None:
        log.warning("failed to find top-level layout block in %s", path)
        return

    start, end = layout_span
    target_idx: int | None = None
    indent = "    "
    for idx in range(start + 1, end):
        stripped = lines[idx].strip()
        if stripped.startswith("//"):
            continue
        if re.match(r"^\s*default-column-width\s*\{", lines[idx]):
            target_idx = idx
            indent = re.match(r"^(\s*)", lines[idx]).group(1)
            break

    new_line = f"{indent}{target_line}\n"
    if target_idx is None:
        lines.insert(end, new_line)
    elif lines[target_idx] == new_line:
        return
    else:
        lines[target_idx] = new_line

    try:
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except OSError as exc:
        log.warning("failed to update niri config %s: %s", path, exc)
        return

    log.info("niri default-column-width synced to proportion %s", proportion)
    niri_action("load-config-file")


# ─── Queries ───
def get_focused_workspace(timeout: float | None = FOCUS_QUERY_TIMEOUT) -> tuple[int | None, int | None]:
    """Get (workspace_id, focused_window_id)."""
    raw = niri_cmd("-j", "focused-window", timeout=timeout)
    if not raw:
        cached_ws, cached_win = _get_cached_focus()
        if cached_ws is not None or cached_win is not None:
            return cached_ws, cached_win
        return _get_active_workspace_id(timeout=timeout), None
    try:
        data = json.loads(raw)
        if not isinstance(data, dict):
            cached_ws, cached_win = _get_cached_focus()
            if cached_ws is not None or cached_win is not None:
                return cached_ws, cached_win
            return _get_active_workspace_id(timeout=timeout), None
        ws_id = _valid_id(data.get("workspace_id"))
        win_id = _valid_id(data.get("id"))
        if ws_id is None:
            ws_id = _get_active_workspace_id(timeout=timeout)
        return ws_id, win_id
    except json.JSONDecodeError:
        log.warning("failed to parse focused-window JSON")
        cached_ws, cached_win = _get_cached_focus()
        if cached_ws is not None or cached_win is not None:
            return cached_ws, cached_win
        return _get_active_workspace_id(timeout=timeout), None


def _get_active_workspace_id(timeout: float | None = None) -> int | None:
    """Get the active workspace ID from niri workspaces list (fallback)."""
    raw = niri_cmd("-j", "workspaces", timeout=timeout)
    if not raw:
        return None
    try:
        workspaces = json.loads(raw)
        if not isinstance(workspaces, list):
            return None
        for ws in workspaces:
            if isinstance(ws, dict) and ws.get("is_active") and ws.get("is_focused"):
                return _valid_id(ws.get("id"))
        # Fallback: just active
        for ws in workspaces:
            if isinstance(ws, dict) and ws.get("is_focused"):
                return _valid_id(ws.get("id"))
        return None
    except json.JSONDecodeError:
        return None


def _get_windows(timeout: float | None = None) -> list[dict]:
    """Fetch all windows from niri IPC (single shared call)."""
    raw = niri_cmd("-j", "windows", timeout=timeout)
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


def _tracked_windows_snapshot() -> list[dict]:
    """Return a shallow snapshot of event-stream window state."""
    with _lock:
        return [dict(w) for w in _windows_by_id.values()]


def _windows_snapshot_or_query(timeout: float | None = NIRI_QUERY_TIMEOUT) -> list[dict]:
    """Prefer event-stream state, falling back to a bounded IPC windows query."""
    windows = _tracked_windows_snapshot()
    if windows:
        return windows
    return _get_windows(timeout=timeout)


def _get_cached_focus() -> tuple[int | None, int | None]:
    """Get focused workspace/window from the event-stream mirror."""
    with _lock:
        for w in _windows_by_id.values():
            if w.get("is_focused"):
                return _valid_id(w.get("workspace_id")), _valid_id(w.get("id"))
    return None, None


def count_columns(workspace_id: int, windows: list[dict] | None = None) -> int:
    """Count unique tiling columns in the given workspace."""
    cols: set[int] = set()
    if windows is None:
        windows = _get_windows()
    for w in windows:
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
def get_active_workspaces(windows: list[dict] | None = None) -> set[int]:
    """Get set of workspace IDs that have tiled windows."""
    ws_ids: set[int] = set()
    if windows is None:
        windows = _get_windows()
    for w in windows:
        if w.get("is_floating", False):
            continue
        ws = _valid_id(w.get("workspace_id"))
        if ws is not None:
            ws_ids.add(ws)
    return ws_ids


def _build_column_map(windows: list[dict], ws_id: int) -> dict[int, list[int]]:
    """Build a map of col_idx -> [window_ids] for tiled windows on a workspace.

    Returns sorted by column index.
    """
    col_map: dict[int, list[int]] = {}
    for w in windows:
        if w.get("workspace_id") != ws_id or w.get("is_floating", False):
            continue
        win_id = _valid_id(w.get("id"))
        if win_id is None:
            continue
        layout = w.get("layout")
        if not isinstance(layout, dict):
            continue
        pos = layout.get("pos_in_scrolling_layout")
        if isinstance(pos, (list, tuple)) and len(pos) > 0:
            col_idx = _valid_id(pos[0])
            if col_idx is not None:
                if col_idx not in col_map:
                    col_map[col_idx] = []
                col_map[col_idx].append(win_id)
    return col_map


def _calc_widths(col_count: int, max_vis: int) -> tuple[int, int]:
    """Calculate base percentage and remainder for even distribution."""
    visible = min(col_count, max_vis)
    base_pct = 100 // visible
    remainder = 100 - (base_pct * visible)
    return base_pct, remainder


def _set_column_width_by_id(win_id: int, pct: str) -> None:
    """Focus a window by ID and set its column width (no walking)."""
    niri_action("focus-window", "--id", str(win_id))
    niri_action("set-column-width", pct)


def _anchor_and_center(col_map: dict[int, list[int]], max_vis: int) -> bool:
    """Anchor leftmost column then re-center to flush any stale scroll offset.

    Always runs, even when col_count > max_vis (overflow case). Otherwise
    niri keeps the scroll position from the previous layout (e.g. coming
    from max=2 → max=4 with 6 cols leaves col6's scroll offset), and the
    focused column ends up mid-viewport with a partial column on either
    side instead of a clean 4-column fit.

    Uses focus-window --id (not focus-column-first) for a real scroll
    reset, plus a small settle delay so the prior set-column-width batch
    has time to apply before we re-anchor.
    """
    sorted_cols = sorted(col_map.keys())
    if not sorted_cols:
        log.info("anchor_and_center: SKIP, empty col_map")
        return False
    first_win = col_map[sorted_cols[0]][0]
    log.info("anchor_and_center: %d cols, settle=%gms, focus win=%d (col=%d), center",
             len(sorted_cols), ANCHOR_SETTLE_SECONDS * 1000, first_win, sorted_cols[0])
    if ANCHOR_SETTLE_SECONDS > 0:
        time.sleep(ANCHOR_SETTLE_SECONDS)
    niri_action("focus-window", "--id", str(first_win))
    niri_action("center-visible-columns")
    return True


def _redistribute_incremental_open(
    ws_id: int, new_window_id: int, windows: list[dict] | None = None,
) -> bool:
    """Handle window open: set only the new column's width.

    Avoids scrolling to the beginning — focuses the new window directly by ID.
    """
    if windows is None:
        windows = _windows_snapshot_or_query()
    col_map = _build_column_map(windows, ws_id)
    col_count = len(col_map)
    new_window_seen = False
    new_window_floating = False
    for window in windows:
        if _valid_id(window.get("id")) != new_window_id:
            continue
        new_window_seen = True
        new_window_floating = bool(window.get("is_floating", False))
        break

    new_col_idx = None
    for col_idx, win_ids in col_map.items():
        if new_window_id in win_ids:
            new_col_idx = col_idx
            break

    if new_col_idx is None:
        if new_window_seen and new_window_floating:
            log.debug("ws=%d: open window %d is floating, no tiling resize", ws_id, new_window_id)
            return True
        log.debug("ws=%d: new window %d not in column map", ws_id, new_window_id)
        return False

    if col_count == 0:
        return False

    if col_count > MAX_COLUMNS:
        col_count = MAX_COLUMNS

    max_vis = get_max_visible(ws_id)
    sorted_cols = sorted(col_map.keys())

    # Cache check
    cache_key = (col_count, max_vis)
    with _lock:
        if _prev_col_counts.get(ws_id) == cache_key:
            return True
        _prev_col_counts[ws_id] = cache_key

    # At or below threshold: full redistribute (all columns need sizing)
    if col_count <= max_vis:
        log.info("ws=%d: %d cols <= max=%d, full redistribute (open)", ws_id, col_count, max_vis)
        _redistribute_full(ws_id, col_map, col_count, max_vis, anchor_visible=False)
        _anchor_and_center(col_map, max_vis)
        # Restore focus to new window (viewport stays since all cols visible)
        niri_action("focus-window", "--id", str(new_window_id))
        return True

    # Above threshold: only set the new column's width (incremental)
    base_pct, remainder = _calc_widths(col_count, max_vis)

    i = sorted_cols.index(new_col_idx)
    pct = f"{base_pct + remainder}%" if i == len(sorted_cols) - 1 and remainder > 0 else f"{base_pct}%"
    log.info("ws=%d: open window %d at col %d, setting %s (incremental)", ws_id, new_window_id, i, pct)

    _set_column_width_by_id(new_window_id, pct)
    niri_action("center-visible-columns")
    return True


def _redistribute_incremental_close(
    ws_id: int, original_focused: int | None, windows: list[dict] | None = None,
) -> None:
    """Handle window close: use post-close layout and center if needed."""
    if windows is None:
        windows = _windows_snapshot_or_query()
    col_count = count_columns(ws_id, windows)
    max_vis = get_max_visible(ws_id)
    with _lock:
        _prev_col_counts[ws_id] = (col_count, max_vis)

    if col_count >= max_vis:
        # Find the focused window's column, then focus max_vis columns back
        # to bring the leftmost needed column into view
        col_map = _build_column_map(windows, ws_id)
        sorted_cols = sorted(col_map.keys())

        # Find focused window's column index
        focused_col_pos = len(sorted_cols) - 1  # default to last
        if original_focused is not None:
            for col_idx, win_ids in col_map.items():
                if original_focused in win_ids:
                    focused_col_pos = sorted_cols.index(col_idx)
                    break

        # The leftmost column that should be visible
        leftmost_pos = max(0, focused_col_pos - max_vis + 1)
        leftmost_col_idx = sorted_cols[leftmost_pos]
        leftmost_win_id = col_map[leftmost_col_idx][0]

        # Focus the leftmost column to bring it into view
        niri_action("focus-window", "--id", str(leftmost_win_id))
        niri_action("center-visible-columns")
        # Restore original focus
        if original_focused is not None:
            niri_action("focus-window", "--id", str(original_focused))
        log.info("ws=%d: close event, %d cols >= max=%d — pulled columns to fill viewport", ws_id, col_count, max_vis)
    else:
        # Fewer than max_visible: WindowClosed already delivered post-close
        # state, so anchor immediately without compositor-settle sleeps.
        col_map = _build_column_map(windows, ws_id)
        actual_count = len(col_map)
        if actual_count > 0:
            with _lock:
                _prev_col_counts[ws_id] = (actual_count, max_vis)
            # Columns were sized by daemon, resize remaining (or hold width).
            _redistribute_full(ws_id, col_map, actual_count, max_vis, anchor_visible=False)
            _anchor_and_center(col_map, max_vis)
            if original_focused is not None:
                niri_action("focus-window", "--id", str(original_focused))
        close_mode = "held width and centered" if KEEP_MAX_WIDTH else "resized and centered"
        log.info("ws=%d: close event, %d cols < max=%d — %s",
                 ws_id, col_count, max_vis, close_mode)


def _redistribute_full(ws_id: int, col_map: dict[int, list[int]] | None = None,
                       col_count: int | None = None, max_vis: int | None = None,
                       anchor_visible: bool = True,
                       windows: list[dict] | None = None) -> None:
    """Full redistribute using direct window ID focus (no focus-column-first walk).

    Used as fallback and for close events. Much less disruptive than the old
    approach because it uses focus-window --id instead of walking columns.

    When col_map/col_count/max_vis are passed, cache was already checked by caller.
    """
    caller_checked_cache = col_map is not None

    if col_map is None:
        if windows is None:
            windows = _windows_snapshot_or_query()
        col_map = _build_column_map(windows, ws_id)

    if col_count is None:
        col_count = len(col_map)
    if col_count == 0:
        return

    if col_count > MAX_COLUMNS:
        col_count = MAX_COLUMNS

    if max_vis is None:
        max_vis = get_max_visible(ws_id)

    # Cache check only when called directly (not from incremental callers)
    if not caller_checked_cache:
        cache_key = (col_count, max_vis)
        with _lock:
            if _prev_col_counts.get(ws_id) == cache_key:
                return
            _prev_col_counts[ws_id] = cache_key

    if KEEP_MAX_WIDTH and col_count < max_vis:
        # Lock columns at 100/max_vis %, leaving empty space — caller centers.
        width_base = max_vis
        hold_width = True
    else:
        width_base = min(col_count, max_vis)
        hold_width = False
    base_pct = 100 // width_base
    # When holding width below max, "missing" slots absorb the remainder so
    # existing columns stay at exactly base_pct — don't grow the last one.
    remainder = 0 if hold_width else 100 - (base_pct * width_base)
    sorted_cols = sorted(col_map.keys())

    log.info("ws=%d: %d cols, max=%d -> %d%% each (base=%d, hold=%s) [direct ID]",
             ws_id, col_count, max_vis, base_pct, width_base, hold_width)

    # Set each column width by focusing a window in it directly (no walking)
    for i, col_idx in enumerate(sorted_cols):
        win_id = col_map[col_idx][0]
        pct = f"{base_pct + remainder}%" if i == len(sorted_cols) - 1 and remainder > 0 else f"{base_pct}%"
        log.info("  → col=%d win=%d set %s", col_idx, win_id, pct)
        _set_column_width_by_id(win_id, pct)

    if anchor_visible and not _anchor_and_center(col_map, max_vis):
        niri_action("center-visible-columns")


def _redistribute_workspace(ws_id: int, focused_id: int | None,
                            event_type: str | None = None,
                            event_window_id: int | None = None,
                            windows: list[dict] | None = None) -> bool:
    """Redistribute columns on a single workspace (dispatch to incremental or full)."""
    if event_type == "open" and event_window_id is not None:
        return _redistribute_incremental_open(ws_id, event_window_id, windows)
    elif event_type == "close":
        _redistribute_incremental_close(ws_id, focused_id, windows)
    else:
        _redistribute_full(ws_id, windows=windows)
    return True


def _schedule_open_retry(event: dict | None, reason: str) -> bool:
    """Retry an open once niri has published settled window layout state."""
    global _pending_event, _debounce_timer, _debounce_started_at

    if not event or event.get("type") != "open":
        return False
    try:
        attempt = int(event.get("attempt", 0))
    except (TypeError, ValueError):
        attempt = 0
    if attempt >= OPEN_RETRY_ATTEMPTS:
        log.debug("open retry exhausted for window=%s: %s", event.get("window_id"), reason)
        return False

    retry_event = dict(event)
    retry_event["attempt"] = attempt + 1
    with _lock:
        if _pending_event is not None:
            log.debug("open retry skipped; newer pending event exists (%s)", reason)
            return True
        _pending_event = retry_event
        if _debounce_timer is not None:
            _debounce_timer.cancel()
        _debounce_started_at = time.monotonic()
        _debounce_timer = threading.Timer(OPEN_RETRY_DELAY_SECONDS, redistribute)
        _debounce_timer.start()
    log.debug(
        "open retry %d/%d for window=%s in %gms: %s",
        attempt + 1, OPEN_RETRY_ATTEMPTS, event.get("window_id"),
        OPEN_RETRY_DELAY_SECONDS * 1000, reason,
    )
    return True


def redistribute() -> None:
    """Redistribute workspaces, using incremental mode when possible."""
    global _pending_event, _debounce_timer, _debounce_started_at

    # Consume pending event context
    with _lock:
        event = _pending_event
        _pending_event = None
        _debounce_timer = None
        _debounce_started_at = None

    event_type = event.get("type") if event else None
    event_window_id = event.get("window_id") if event else None

    windows = _windows_snapshot_or_query()
    original_ws, original_focused = get_focused_workspace()

    if event_type == "open" and event_window_id is not None:
        # Incremental: only handle the workspace of the new window
        target_ws = _valid_id(event.get("workspace_id")) if event else None
        if target_ws is None and isinstance(event.get("window") if event else None, dict):
            target_ws = _valid_id(event["window"].get("workspace_id"))
        if target_ws is None:
            for w in windows:
                if _valid_id(w.get("id")) == event_window_id:
                    target_ws = _valid_id(w.get("workspace_id"))
                    break
        if target_ws is not None:
            handled = _redistribute_workspace(
                target_ws, original_focused, "open", event_window_id, windows,
            )
            if not handled:
                if _schedule_open_retry(event, "new window not present in tiled column map"):
                    return
                log.debug("falling back to full redistribute after open miss")
                for active_ws in get_active_workspaces(windows):
                    _redistribute_workspace(active_ws, original_focused, windows=windows)
        else:
            if _schedule_open_retry(event, "new window workspace unknown"):
                return
            for active_ws in get_active_workspaces(windows):
                _redistribute_workspace(active_ws, original_focused, windows=windows)
    elif event_type == "close":
        # Incremental close: redistribute with direct ID focus, no focus change
        for active_ws in get_active_workspaces(windows):
            _redistribute_workspace(active_ws, original_focused, "close", event_window_id, windows)
        # Close handler restores focus itself — skip global restore
        return
    else:
        # Full redistribute (startup, batch events)
        for active_ws in get_active_workspaces(windows):
            _redistribute_workspace(active_ws, original_focused, windows=windows)

    # Restore focus to the original window (open + full only)
    restore_focused = original_focused
    if restore_focused is None and event_type == "open":
        restore_focused = event_window_id
    if restore_focused is not None:
        niri_action("focus-window", "--id", str(restore_focused))
        niri_action("center-visible-columns")
    elif original_ws is not None:
        for w in windows:
            if w.get("workspace_id") == original_ws and not w.get("is_floating", False):
                win_id = _valid_id(w.get("id"))
                if win_id is not None:
                    niri_action("focus-window", "--id", str(win_id))
                    niri_action("center-visible-columns")
                    break


def debounced_redistribute() -> None:
    """Debounce + coalescing rate limit before redistributing."""
    global _debounce_timer, _debounce_started_at, _event_count, _event_window_start

    now = time.monotonic()

    with _lock:
        # Rate limiter: sliding window
        if now - _event_window_start > 1.0:
            _event_window_start = now
            _event_count = 0
        _event_count += 1
        rate_limited = _event_count > MAX_EVENTS_PER_SECOND

        # Cancel previous timer, start new one
        if _debounce_timer is not None:
            _debounce_timer.cancel()
        if _debounce_started_at is None:
            _debounce_started_at = now

        event_type = _pending_event.get("type") if _pending_event else None
        if event_type == "close":
            debounce_seconds = CLOSE_DEBOUNCE_SECONDS
        elif event_type == "open":
            debounce_seconds = min(DEBOUNCE_SECONDS, OPEN_DEBOUNCE_SECONDS)
        else:
            debounce_seconds = DEBOUNCE_SECONDS

        deadline = min(now + debounce_seconds, _debounce_started_at + MAX_DEBOUNCE_SECONDS)
        delay = max(0.0, deadline - now)
        if rate_limited:
            log.debug(
                "rate limit exceeded (%d/s), coalescing pending %s event",
                MAX_EVENTS_PER_SECOND, event_type or "full",
            )
        log.debug("debounce event_type=%s interval=%gms",
                  event_type or "full", delay * 1000)
        _debounce_timer = threading.Timer(delay, redistribute)
        _debounce_timer.start()


# ─── Event Processing ───
def _queue_pending_event_locked(
    event_type: str,
    window_id: int | None = None,
    window: dict | None = None,
    workspace_id: int | None = None,
    reason: str | None = None,
) -> None:
    """Queue event context, widening to full redistribute for mixed bursts."""
    global _pending_event

    event: dict = {"type": event_type}
    if window_id is not None:
        event["window_id"] = window_id
    if window is not None:
        event["window"] = dict(window)
        if workspace_id is None:
            workspace_id = _valid_id(window.get("workspace_id"))
    if workspace_id is not None:
        event["workspace_id"] = workspace_id
    if reason:
        event["reason"] = reason

    if _pending_event is None:
        _pending_event = event
        return

    pending_type = _pending_event.get("type")
    pending_window_id = _pending_event.get("window_id")
    if pending_type == event_type and pending_window_id == window_id:
        _pending_event.update(event)
        return

    if pending_type == "full":
        return

    _pending_event = {
        "type": "full",
        "reason": reason or f"merged pending {pending_type} with {event_type}",
    }


def _track_focus_change_locked(focused_id: int | None) -> None:
    """Apply WindowFocusChanged to the event-stream mirror."""
    for win_id, window in list(_windows_by_id.items()):
        is_focused = focused_id is not None and win_id == focused_id
        if window.get("is_focused") == is_focused:
            continue
        updated = dict(window)
        updated["is_focused"] = is_focused
        _windows_by_id[win_id] = updated


def should_redistribute(event: dict) -> bool:
    """Determine if an event warrants redistribution.

    Only triggers on actual window open/close, NOT title changes.
    Stores event context in _pending_event for incremental redistribution.
    """
    global _known_window_ids, _windows_by_id, _pending_event

    if "WindowClosed" in event:
        closed = event["WindowClosed"]
        if isinstance(closed, dict):
            win_id = _valid_id(closed.get("id"))
            if win_id is not None:
                with _lock:
                    _known_window_ids.discard(win_id)
                    _windows_by_id.pop(win_id, None)
                    _queue_pending_event_locked("close", win_id)
                return True
        return False

    if "WindowOpenedOrChanged" in event:
        payload = event["WindowOpenedOrChanged"]
        if not isinstance(payload, dict):
            return False
        window = payload.get("window") or {}
        if not isinstance(window, dict):
            return False
        win_id = _valid_id(window.get("id"))
        if win_id is not None:
            with _lock:
                _windows_by_id[win_id] = dict(window)
                if win_id not in _known_window_ids:
                    _known_window_ids.add(win_id)
                    _queue_pending_event_locked("open", win_id, window=window)
                    if window.get("is_focused"):
                        _track_focus_change_locked(win_id)
                    return True
                if window.get("is_focused"):
                    _track_focus_change_locked(win_id)
            return False
        return False

    if "WindowsChanged" in event:
        # Complete replacement list: sync cache and classify simple deltas.
        changed = event["WindowsChanged"]
        if not isinstance(changed, dict):
            return False
        windows = changed.get("windows") or []
        if not isinstance(windows, list):
            return False
        new_by_id: dict[int, dict] = {}
        for w in windows:
            if not isinstance(w, dict):
                continue
            win_id = _valid_id(w.get("id"))
            if win_id is not None:
                new_by_id[win_id] = dict(w)
        new_ids = set(new_by_id.keys())
        with _lock:
            old_ids = set(_known_window_ids)
            if new_ids != old_ids:
                added = new_ids - old_ids
                removed = old_ids - new_ids
                _known_window_ids = new_ids
                _windows_by_id = new_by_id
                if len(added) == 1 and not removed:
                    win_id = next(iter(added))
                    _queue_pending_event_locked("open", win_id, window=new_by_id.get(win_id))
                elif len(removed) == 1 and not added:
                    _queue_pending_event_locked("close", next(iter(removed)))
                else:
                    _queue_pending_event_locked(
                        "full",
                        reason=f"WindowsChanged added={len(added)} removed={len(removed)}",
                    )
                return True
            _windows_by_id = new_by_id
        return False

    if "WindowLayoutsChanged" in event:
        changed = event["WindowLayoutsChanged"]
        if not isinstance(changed, dict):
            return False
        changes = changed.get("changes") or []
        if not isinstance(changes, list):
            return False
        with _lock:
            for change in changes:
                if not isinstance(change, (list, tuple)) or len(change) != 2:
                    continue
                win_id = _valid_id(change[0])
                layout = change[1]
                if win_id is None or not isinstance(layout, dict) or win_id not in _windows_by_id:
                    continue
                updated = dict(_windows_by_id[win_id])
                updated["layout"] = layout
                _windows_by_id[win_id] = updated
        return False

    if "WindowFocusChanged" in event:
        changed = event["WindowFocusChanged"]
        if not isinstance(changed, dict):
            return False
        with _lock:
            _track_focus_change_locked(_valid_id(changed.get("id")))
        return False

    return False


def process_pending_config_reload() -> None:
    """Apply SIGUSR1-requested config reloads outside the signal handler."""
    if not _config_reload_requested.is_set():
        return
    _config_reload_requested.clear()
    reload_config()


def run_event_loop() -> None:
    """Connect to niri event stream and process events."""
    global _known_window_ids, _windows_by_id, _debounce_timer, _debounce_started_at
    global _event_count, _event_window_start

    # Cancel any pending timer from previous cycle and reset rate limiter
    initial_windows = _get_windows(timeout=NIRI_QUERY_TIMEOUT)
    initial_by_id: dict[int, dict] = {}
    for window in initial_windows:
        win_id = _valid_id(window.get("id"))
        if win_id is not None:
            initial_by_id[win_id] = dict(window)

    with _lock:
        if _debounce_timer is not None:
            _debounce_timer.cancel()
            _debounce_timer = None
        _debounce_started_at = None
        _event_count = 0
        _event_window_start = 0.0
        _known_window_ids = set(initial_by_id.keys())
        _windows_by_id = initial_by_id
    log.info("tracking %d existing windows", len(_known_window_ids))

    # Force immediate redistribution on startup
    with _lock:
        _prev_col_counts.clear()
    redistribute()

    proc = subprocess.Popen(
        ["niri", "msg", "-j", "event-stream"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )

    try:
        stdout = proc.stdout
        if stdout is None:
            return

        while True:
            process_pending_config_reload()

            ready, _, _ = select.select([stdout], [], [], 0.25)
            if not ready:
                if proc.poll() is not None:
                    break
                continue

            line = stdout.readline()
            if line == "":
                break
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
        if proc.poll() is None:
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
        "--keep-max-width", action="store_true",
        help="keep each column at 100/max-visible%% even when fewer columns are open",
    )
    parser.add_argument(
        "--per-workspace", action="store_true",
        help="use per-workspace max-visible settings",
    )
    parser.add_argument(
        "--workspace-config", type=str, default=None,
        help='JSON map of workspace_id -> maxVisible, e.g. \'{"3":2,"1":4}\'',
    )
    parser.add_argument(
        "--config-file", type=str, default=None,
        help="path to runtime config file for hot-reload via SIGUSR1",
    )
    parser.add_argument(
        "--niri-config-file", type=str, default=None,
        help=f"path to niri config for default-column-width sync (default: {NIRI_CONFIG_FILE})",
    )
    parser.add_argument(
        "--debug", action="store_true",
        help="enable debug logging",
    )
    return parser.parse_args()


# ─── Hot Reload ───
def reload_config() -> None:
    """Reload configuration from CONFIG_FILE and trigger redistribution."""
    global MAX_VISIBLE, PER_WORKSPACE, WORKSPACE_MAX_VISIBLE
    global KEEP_MAX_WIDTH, DEBOUNCE_SECONDS, MAX_EVENTS_PER_SECOND, _debounce_timer
    global _debounce_started_at, _pending_event, _event_count, _event_window_start

    if not CONFIG_FILE or not os.path.isfile(CONFIG_FILE):
        log.warning("no config file to reload")
        return

    try:
        with open(CONFIG_FILE) as f:
            cfg = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        log.warning("failed to read config file: %s", exc)
        return

    if not isinstance(cfg, dict):
        return

    old_layout_config = (
        MAX_VISIBLE, PER_WORKSPACE, dict(WORKSPACE_MAX_VISIBLE),
        KEEP_MAX_WIDTH,
    )

    if "maxVisible" in cfg:
        MAX_VISIBLE = _int_at_least(cfg["maxVisible"], 1, MAX_VISIBLE)
    if "keepMaxWidth" in cfg:
        KEEP_MAX_WIDTH = bool(cfg["keepMaxWidth"])
    if "perWorkspace" in cfg:
        PER_WORKSPACE = bool(cfg["perWorkspace"])
    if "workspaceMaxVisible" in cfg:
        raw = cfg["workspaceMaxVisible"]
        if isinstance(raw, dict):
            WORKSPACE_MAX_VISIBLE = {
                int(k): max(1, int(v))
                for k, v in raw.items()
                if str(k).isdigit() and str(v).isdigit()
            }
    if "debounceMs" in cfg:
        DEBOUNCE_SECONDS = _milliseconds_to_seconds(cfg["debounceMs"], DEBOUNCE_SECONDS)
    if "maxEventsPerSecond" in cfg:
        MAX_EVENTS_PER_SECOND = _int_at_least(
            cfg["maxEventsPerSecond"], 1, MAX_EVENTS_PER_SECOND,
        )

    layout_config = (
        MAX_VISIBLE, PER_WORKSPACE, dict(WORKSPACE_MAX_VISIBLE),
        KEEP_MAX_WIDTH,
    )
    layout_changed = layout_config != old_layout_config

    log.info(
        "config reloaded (max_visible=%d, debounce=%gms, max_events=%d, "
        "keep_max_width=%s, layout_changed=%s)",
        MAX_VISIBLE,
        DEBOUNCE_SECONDS * 1000,
        MAX_EVENTS_PER_SECOND,
        KEEP_MAX_WIDTH,
        layout_changed,
    )
    sync_niri_default_column_width()

    # Timing-only changes should not touch window layout or focus.
    with _lock:
        _event_count = 0
        _event_window_start = 0.0
        if not layout_changed:
            return
        if _debounce_timer is not None:
            _debounce_timer.cancel()
            _debounce_timer = None
        _debounce_started_at = None
        _pending_event = None
        _prev_col_counts.clear()

    _, original_focused = get_focused_workspace()
    windows = _get_windows()
    active_workspaces: set[int] = set()
    for window in windows:
        if window.get("is_floating", False):
            continue
        ws_id = _valid_id(window.get("workspace_id"))
        if ws_id is not None:
            active_workspaces.add(ws_id)

    had_overflow = False
    for active_ws in active_workspaces:
        col_map = _build_column_map(windows, active_ws)
        col_count = len(col_map)
        if col_count == 0:
            continue
        max_vis = get_max_visible(active_ws)
        if col_count > max_vis:
            had_overflow = True
        _redistribute_full(
            active_ws, col_map, col_count, max_vis,
            anchor_visible=False,
        )
        _anchor_and_center(col_map, max_vis)
    if original_focused is not None:
        niri_action("focus-window", "--id", str(original_focused))
        if had_overflow:
            niri_action("center-visible-columns")


# ─── Main ───
def main() -> None:
    """Main entry point with reconnection loop."""
    global MAX_VISIBLE, DEBOUNCE_SECONDS, MAX_EVENTS_PER_SECOND
    global PER_WORKSPACE, WORKSPACE_MAX_VISIBLE
    global KEEP_MAX_WIDTH, CONFIG_FILE, NIRI_CONFIG_FILE

    args = parse_args()

    # Apply CLI overrides
    if args.max_visible is not None:
        MAX_VISIBLE = max(1, args.max_visible)
    if args.debounce is not None:
        DEBOUNCE_SECONDS = max(0.05, args.debounce)
    if args.max_events is not None:
        MAX_EVENTS_PER_SECOND = max(1, args.max_events)
    if args.keep_max_width:
        KEEP_MAX_WIDTH = True
    if args.per_workspace:
        PER_WORKSPACE = True
    if args.workspace_config:
        try:
            raw = json.loads(args.workspace_config)
            if isinstance(raw, dict):
                WORKSPACE_MAX_VISIBLE = {
                    int(k): max(1, int(v))
                    for k, v in raw.items()
                    if str(k).isdigit() and str(v).isdigit()
                }
        except (json.JSONDecodeError, ValueError) as exc:
            log.warning("invalid --workspace-config: %s", exc)
    if args.config_file:
        CONFIG_FILE = args.config_file
    if args.niri_config_file:
        NIRI_CONFIG_FILE = os.path.expanduser(args.niri_config_file)
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

    # Handle SIGUSR1 for hot config reload (no restart needed).
    # The actual reload happens in the event loop, outside signal context.
    def _reload(signum, frame):
        _config_reload_requested.set()
    signal.signal(signal.SIGUSR1, _reload)

    sync_niri_default_column_width()

    mode = "per-workspace" if PER_WORKSPACE else "global"
    ws_cfg = f", ws_config={WORKSPACE_MAX_VISIBLE}" if WORKSPACE_MAX_VISIBLE else ""
    flag_str = ", keep_max_width" if KEEP_MAX_WIDTH else ""
    log.info("starting (max_visible=%d, mode=%s, debounce=%gms%s%s)",
             MAX_VISIBLE, mode, DEBOUNCE_SECONDS * 1000, ws_cfg, flag_str)

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

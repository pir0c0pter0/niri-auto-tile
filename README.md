# niri-auto-tile

**Auto-tiling daemon for [niri](https://github.com/YaLTeR/niri) compositor** — automatically redistributes column widths evenly when windows are opened or closed.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![niri](https://img.shields.io/badge/niri-v25.11+-green.svg)](https://github.com/YaLTeR/niri)
[![Python](https://img.shields.io/badge/Python-3.10+-yellow.svg)](https://python.org)
[![Noctalia Plugin](https://img.shields.io/badge/Noctalia-Plugin-purple.svg)](https://github.com/noctalia-dev/noctalia-plugins)

---

## The Problem

Niri is a scrollable-tiling Wayland compositor where windows are arranged in columns on an infinite horizontal strip. When you open or close windows, existing columns don't automatically resize to fill the viewport — you're left with empty space or columns scrolled off-screen.

## The Solution

`niri-auto-tile` listens to niri's JSON event stream and automatically resizes all tiling columns to equal widths whenever a window is opened or closed. If you have 4 columns and close one, the remaining 3 instantly expand to fill the screen.

### Features

- **Automatic redistribution** — columns resize instantly on window open/close
- **Multi-workspace support** — redistributes all active workspaces, restoring original focus afterwards
- **Configurable max visible columns** — caps how many columns fit on screen (default: 4)
- **Per-workspace settings** — each workspace can have its own column count
- **Keep max width mode** — locks every column at `100/max-visible %` even when fewer columns are open, re-centering the layout instead of expanding
- **Synced new-window width** — keeps niri's `layout.default-column-width` aligned with the global `maxVisible` value, so new windows open at the right size before post-open redistribution runs
- **Open-event retry path** — retries newly opened windows until niri publishes their workspace and column layout
- **Event-stream layout cache** — tracks `WindowsChanged`, `WindowLayoutsChanged`, and focus changes to reduce slow IPC queries during busy window creation
- **Smart event filtering** — only reacts to actual window open/close, ignores title changes (e.g., browser tab switches)
- **Theme-aware UI** — all colors follow the active Noctalia theme (no hardcoded colors)
- **Thread-safe debouncing** — coalesces rapid events to prevent flickering
- **Rate limiting** — circuit breaker for event floods (20 events/second cap)
- **Auto-reconnection** — recovers if the niri event stream drops
- **Graceful shutdown** — handles SIGTERM cleanly
- **JSON IPC** — uses niri's structured JSON protocol, not fragile text parsing
- **Live runtime settings** — Noctalia changes are applied with `SIGUSR1` and niri IPC, without restarting the daemon
- **Input validation** — validates all IPC responses and data types
- **i18n** — English and Portuguese translations

---

## Installation

### Standalone (any niri setup)

1. **Copy the script:**

   ```bash
   cp auto-tile.py ~/.config/niri/auto-tile.py
   chmod 700 ~/.config/niri/auto-tile.py
   ```

2. **Add to niri autostart** (`~/.config/niri/config.kdl`):

   ```kdl
   spawn-at-startup "python3" "/home/YOUR_USER/.config/niri/auto-tile.py"
   ```

3. **Start it for the current session:**

   ```bash
   python3 ~/.config/niri/auto-tile.py
   ```

   The `spawn-at-startup` entry takes effect the next time niri starts. If you need niri to pick up that autostart edit immediately without a full compositor restart, use niri's native config reload once:

   ```bash
   niri msg action load-config-file
   ```

### Noctalia Shell Plugin

If you use [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell), this project includes a native plugin with a bar indicator, floating panel, and settings UI:

1. **Clone into the plugins directory:**

   ```bash
   git clone https://github.com/pir0c0pter0/niri-auto-tile.git \
     ~/.config/noctalia/plugins/niri-auto-tile
   ```

2. **Enable** in Noctalia Settings > Plugins > niri-auto-tile

3. **Add the bar widget** — drag "Auto-Tile" to your bar in Noctalia Settings > Bar

### Systemd User Service (optional)

For process supervision with automatic restart:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/niri-auto-tile.service << 'EOF'
[Unit]
Description=niri auto-tile daemon
After=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 %h/.config/niri/auto-tile.py
Restart=on-failure
RestartSec=2
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user enable --now niri-auto-tile.service
```

---

## Noctalia Plugin UI

### Bar Widget

- Column indicators showing the current max visible count
- Status dot (theme primary = running, theme secondary = starting)
- Left-click opens the floating panel
- Right-click context menu: enable/disable, settings

### Floating Panel

- Enable/disable toggle in the header
- Visual column layout selector (1-4 columns grid)
- Status bar with current state and workspace info

### Settings

- **Enable Auto-Tile** — master on/off switch
- **Per workspace** — each workspace has its own column count
- **Keep max width** — lock columns at `100/max-visible %` even with fewer cols, re-center the layout
- **Max visible columns** — slider from 1 to 8
- **Debounce delay** — 100-1000ms event coalescence
- **Rate limit** — 5-50 events per second
- **Daemon status** — running/error/stopped indicator
- **About** — credits and version info

Settings that affect layout or event handling are applied live. The plugin writes `runtime-config.json` with Quickshell's `FileView`, sends `SIGUSR1` to the running daemon, and the daemon updates its in-memory config. It does not restart niri or restart the daemon for normal settings changes.

When the global **Max visible columns** value changes, the daemon also updates niri's top-level `layout { default-column-width ... }` to `1/maxVisible` and calls `niri msg action load-config-file`. This makes future windows open at the same width auto-tile will enforce. Per-workspace overrides still apply during redistribution, but niri only has one global default for newly created columns.

---

## Configuration

### CLI Arguments

```bash
python3 auto-tile.py \
  --max-visible 4 \
  --debounce 0.3 \
  --max-events 20 \
  --keep-max-width \
  --per-workspace \
  --workspace-config '{"3":2,"1":4}' \
  --config-file ~/.config/niri/auto-tile-runtime.json \
  --niri-config-file ~/.config/niri/config.kdl \
  --debug
```

### Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_VISIBLE` | `4` | Maximum columns visible on screen at once |
| `MAX_COLUMNS` | `20` | Safety cap for total column count |
| `DEBOUNCE_SECONDS` | `0.3` | Delay before redistribution (coalesces rapid events) |
| `OPEN_DEBOUNCE_SECONDS` | `0.1` | Shorter debounce used for window-open events |
| `CLOSE_DEBOUNCE_SECONDS` | `0.05` | Shorter debounce used for window-close events |
| `MAX_DEBOUNCE_SECONDS` | `0.75` | Maximum time a burst can keep delaying redistribution |
| `OPEN_RETRY_DELAY_SECONDS` | `0.15` | Delay between retries while a new window layout is not ready |
| `OPEN_RETRY_ATTEMPTS` | `3` | Maximum post-open layout retries |
| `NIRI_TIMEOUT` | `5` | Timeout for niri IPC calls (seconds) |
| `NIRI_CONFIG_FILE` | `~/.config/niri/config.kdl` | niri config file updated for `default-column-width` sync |
| `RECONNECT_DELAY` | `2.0` | Delay before reconnecting after event stream drops |
| `MAX_EVENTS_PER_SECOND` | `20` | Rate limiter threshold |
| `PER_WORKSPACE` | `False` | Per-workspace column count settings |
| `KEEP_MAX_WIDTH` | `False` | Hold each column at `100/MAX_VISIBLE %` below max, re-centering |
| `CONFIG_FILE` | `""` | Optional runtime JSON file used for hot reload via `SIGUSR1` |

### Synced niri layout

The daemon automatically keeps the top-level niri layout default in sync with the global `MAX_VISIBLE` value:

```kdl
// ~/.config/niri/config.kdl
layout {
    default-column-width { proportion 0.25; }  // 1/4 for MAX_VISIBLE=4
    preset-column-widths {
        proportion 0.25
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }
}
```

For example, changing the Noctalia setting from 4 to 2 visible columns changes the default to `proportion 0.5` and reloads niri's config. This affects newly opened windows immediately. Existing windows are still resized through `niri msg action set-column-width`.

---

## How It Works

```
niri event-stream (JSON)
         |
         v
   Event Filter          — window open/close plus layout and focus cache updates
         |
         v
   Rate Limiter          — max 20 events/second sliding window
         |
         v
   Debounce Timer        — 300ms coalescence
         |
         v
   Layout Cache          — event-stream snapshot, bounded IPC fallback
         |
         v
   Save Original Focus   — remember current workspace and focused window
         |
         v
   Redistribute          — set-column-width for affected columns via niri IPC
         |
         v
   Restore Focus         — return to original workspace and window
```

### Runtime Configuration

The Noctalia plugin keeps the Python daemon alive across normal setting changes:

1. `Settings.qml` and `Panel.qml` persist the new values through Noctalia
2. `Main.qml` coalesces rapid changes, writes `runtime-config.json`, and sends `SIGUSR1`
3. `auto-tile.py` reloads that file from the event loop, outside signal-handler context
4. Layout-affecting changes clear the column cache and redistribute via niri actions
5. Global `maxVisible` changes update niri's `default-column-width` and call `load-config-file`
6. Timing-only changes (`debounceMs`, `maxEventsPerSecond`) update memory only and do not touch window layout

Process restarts are limited to enable/disable, plugin teardown, and failure recovery. niri config reloads are used only for the new-window default width; column resizing itself remains native `niri msg action` IPC.

### Multi-Workspace Redistribution

When a window event triggers redistribution:

1. The daemon saves the currently focused workspace and window
2. Iterates through all active workspaces with tiled windows
3. Builds a column map from `niri msg -j windows`
4. Uses `niri msg action focus-window --id ...` and `set-column-width` on one representative window per column
5. After all workspaces are processed, restores focus to the original window
6. If no window was focused (e.g., panel was open), falls back to focusing any window on the original workspace via `niri msg -j workspaces`

### Event Filtering

The script maintains a set of known window IDs and an event-stream mirror of current windows. When events arrive:
- `WindowOpenedOrChanged` with a new ID triggers the open path
- `WindowsChanged` is used as a fallback when niri reports the window list before the open event
- `WindowLayoutsChanged` updates cached layout positions without forcing a resize by itself
- `WindowFocusChanged` keeps focus restoration fast without an extra IPC query
- repeated title changes for known IDs are skipped

This prevents the flickering that would occur with apps like Firefox that fire `WindowOpenedOrChanged` on every tab switch or page load.

If a newly opened window has not received a workspace or column position yet, the daemon schedules a bounded retry. That prevents the common race where a window opens at niri's default size and only resizes after the next focus event.

### Width Calculation

Columns are sized to fill exactly 100% of the viewport:

| Columns | Width per column |
|---------|-----------------|
| 1 | 100% |
| 2 | 50% |
| 3 | 33% + 33% + 34% |
| 4 | 25% |
| 5+ | 25% each (scrolled) |

The last column absorbs any rounding remainder to ensure widths sum to exactly 100%.

---

## Logging

The script logs to stdout with structured messages:

```
18:07:44 INFO auto-tile: starting (max_visible=4, mode=global, debounce=300ms)
18:07:44 INFO auto-tile: tracking 4 existing windows
18:08:01 INFO auto-tile: ws=3: 4 cols, max=4 -> 25% each (+0% last)
```

When using systemd, view logs with:

```bash
journalctl --user -u niri-auto-tile -f
```

---

## Compatibility

- **niri** v25.11+ (requires JSON event-stream support)
- **Python** 3.10+ (uses `X | Y` union syntax)
- **noctalia-shell** 4.4+ (for the plugin — optional)

No external Python dependencies required — uses only the standard library.

---

## Security

This script has been through two rounds of multi-perspective security review (5 specialized agents each round). Key security properties:

- **No shell injection** — all subprocess calls use list form, never `shell=True`
- **No network access** — communicates only via local niri IPC
- **No credentials or secrets** — reads only window metadata
- **Input validation** — all IPC responses are type-checked and validated
- **Thread safety** — all shared state protected by `threading.Lock`
- **Rate limiting** — prevents event flood DoS
- **Graceful shutdown** — SIGTERM handler without deadlock risk

---

## Troubleshooting

### Windows don't redistribute

1. Check if the script is running: `pgrep -f auto-tile.py`
2. Check logs: `journalctl --user -u niri-auto-tile -f` or `/tmp/auto-tile.log`
3. Verify niri IPC works: `niri msg -j windows`

### Flickering when switching browser tabs

This should not happen — the script filters title-change events. If it does:
1. Increase `DEBOUNCE_SECONDS` to `0.5`
2. Check logs for unexpected `WindowOpenedOrChanged` events with new IDs

### Script crashes on startup

Ensure niri is running and `niri msg -j event-stream` produces output. The script will auto-reconnect if the stream drops.

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test with at least 2-4 windows across multiple workspaces
4. Submit a pull request

---

## License

[MIT](LICENSE) — same as niri.

---

## Credits

Developed by Pir0c0pter0 using [Claude Code](https://claude.ai/claude-code).

## Acknowledgements

- [niri](https://github.com/YaLTeR/niri) by YaLTeR — the scrollable-tiling Wayland compositor
- [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell) — the desktop shell framework

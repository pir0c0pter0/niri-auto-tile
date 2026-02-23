# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Auto-tile is a monorepo with two independent auto-tiling implementations for Linux desktops. Both distribute windows in equal-width columns automatically when windows open or close.

| Directory | Platform | Tech |
|-----------|----------|------|
| `niri-auto-tile/` | niri compositor | Python daemon + Noctalia Shell QML plugin |
| `kde-auto-tile/` | KDE Plasma 6 | KWin Script (JavaScript) |

## Running

**niri (standalone daemon):**
```bash
python3 niri-auto-tile/auto-tile.py --max-visible 4 --debounce 0.3 --debug
```

**niri (Noctalia plugin):** Install `niri-auto-tile/` to `~/.config/noctalia/plugins/niri-auto-tile/`, enable in Noctalia Settings.

**KDE Plasma 6:**
```bash
kpackagetool6 --type=KWin/Script -i kde-auto-tile/
kwriteconfig6 --file kwinrc --group Plugins --key kwin-auto-tileEnabled true
qdbus6 org.kde.KWin /KWin reconfigure
```

There is no build step, test suite, or linter configured. The Python script uses only the standard library. The KWin script uses only built-in KWin JS APIs.

## Architecture

### niri-auto-tile — Two-layer design

1. **Python daemon** (`niri-auto-tile/auto-tile.py`) — core logic. Connects to `niri msg -j event-stream`, filters events, debounces, and calls `niri msg action` to resize columns.

2. **QML plugin layer** (Noctalia Shell) — GUI controls. `Main.qml` spawns/stops the Python daemon, passing settings as CLI args. QML files depend on Noctalia/Quickshell APIs.

**Event flow:** `niri event-stream → Event Filter (new window IDs only) → Rate Limiter → Debounce Timer → Redistribute All Workspaces → Restore Focus`

**QML entry points** (defined in `niri-auto-tile/manifest.json`):

| File | Role |
|------|------|
| `Main.qml` | Daemon lifecycle, IPC, settings bridge, i18n |
| `BarWidget.qml` | Bar indicator with column count and status dot |
| `Panel.qml` | Floating panel with visual column selector |
| `Settings.qml` | Full settings page |

**Niri IPC:** All communication uses `subprocess.run(["niri", "msg", ...])` in list form (never `shell=True`).

**Thread safety:** Shared state protected by `threading.Lock`. Debounce timer fires on a separate thread.

### kde-auto-tile — KWin Script

Single file (`kde-auto-tile/contents/code/main.js`) with 10 sections:

1. **Configuration** — `readConfig()` from KCfg
2. **State** — window tracking, layout cache, rate limiter
3. **Window Filtering** — `isTileable()` rejects dialogs, docks, tooltips, minimized, fullscreen, excluded classes
4. **Window Grouping** — groups by `(desktop.id, output.name)`, handles `onAllDesktops`
5. **Redistribution** — `width = (screen - gaps) / maxVisible`, stable insertion order sort
6. **Debounce** — recursive `callDBus` polling with timestamp superseding
7. **Event Handlers** — signals: `windowAdded/Removed`, `minimizedChanged`, `fullScreenChanged`, `desktopsChanged`, `outputChanged`
8. **Keyboard Shortcuts** — `Meta+Ctrl+1-4` (columns), `Meta+Ctrl+T` (re-tile)
9. **Context Menu** — `registerUserActionsMenu` for per-window exclude/include
10. **Initialization** — connect signals, track existing windows, initial redistribute

**Config UI:** `kde-auto-tile/contents/config/main.xml` (KCfg schema) + `kde-auto-tile/contents/ui/config.ui` (Qt Designer). Widgets named `kcfg_*` auto-bind to config entries.

**Key difference from niri:** KWin has no scrollable viewport, so overflow windows (beyond maxVisible) are moved off-screen to the right.

## i18n (niri only)

Self-contained translation system in `niri-auto-tile/Main.qml`. EN and PT strings inline, resolved via `translate(key)`. Live switching via `reloadLanguage()` + `translationVersion` signal.

## Requirements

**niri:** niri v25.11+, Python 3.10+, Noctalia Shell 4.4+ (optional)
**KDE:** KDE Plasma 6 (KWin 6.x)

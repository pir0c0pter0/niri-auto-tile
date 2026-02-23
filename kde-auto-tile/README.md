# KWin Auto Tile

A KWin Script for **KDE Plasma 6** that automatically arranges windows in equal-width columns. When you open or close a window, all visible windows are instantly redistributed into a clean column layout.

> Ported from [niri-auto-tile](https://github.com/pir0c0pter0/auto-tile), originally built for the niri Wayland compositor.

---

## How It Works

```
┌──────────┬──────────┬──────────┬──────────┐
│          │          │          │          │
│  Window  │  Window  │  Window  │  Window  │
│    1     │    2     │    3     │    4     │
│          │          │          │          │
└──────────┴──────────┴──────────┴──────────┘
           maxVisible = 4 (default)
```

- Opens a window → columns redistribute automatically
- Closes a window → remaining windows fill the gap
- Each **monitor** and **virtual desktop** tiles independently
- Column width is always calculated as `screen_width / maxVisible`, keeping layout consistent
- Windows beyond `maxVisible` are moved off-screen (accessible via Alt+Tab or task switcher)
- Right-click any title bar to exclude a window from tiling

## Features

- **Automatic redistribution** on window open, close, minimize, fullscreen, and desktop/monitor changes
- **Configurable column count** (1-8) with keyboard shortcuts for quick switching
- **Per-monitor + per-desktop** independent tiling
- **Configurable gaps** between windows (0-32px)
- **Window class filtering** to permanently exclude apps (e.g. `plasmashell, krunner`)
- **Per-window exclusion** via right-click context menu ("Exclude from Auto-Tile")
- **Debounce + rate limiting** to prevent flickering during rapid events
- **Zero dependencies** — pure KWin JavaScript, no external processes

## Requirements

- **KDE Plasma 6** (KWin 6.x)
- **kpackagetool6** (included with Plasma 6)

## Installation

### From file manager (GUI)

1. Download or clone this repository
2. Open **System Settings** > **Window Management** > **KWin Scripts**
3. Click **Install from File...** and select the folder (or zip it as `.kwinscript` first)
4. Enable **Auto Tile** in the list

### From terminal

```bash
# Clone
git clone https://github.com/pir0c0pter0/kwin-auto-tile.git
cd kwin-auto-tile

# Install
kpackagetool6 --type=KWin/Script -i .

# Enable
kwriteconfig6 --file kwinrc --group Plugins --key kwin-auto-tileEnabled true

# Reload KWin to activate
qdbus6 org.kde.KWin /KWin reconfigure
```

### Updating

```bash
kpackagetool6 --type=KWin/Script -u .
qdbus6 org.kde.KWin /KWin reconfigure
```

### Uninstalling

```bash
kpackagetool6 --type=KWin/Script -r kwin-auto-tile
qdbus6 org.kde.KWin /KWin reconfigure
```

## Configuration

Open **System Settings** > **Window Management** > **KWin Scripts** > click **Configure** next to Auto Tile.

| Setting | Default | Description |
|---------|---------|-------------|
| **Enable auto-tiling** | `true` | Master on/off toggle |
| **Maximum visible columns** | `4` | How many columns fit on screen (1-8) |
| **Gap between windows** | `8 px` | Pixel gap between columns and screen edges (0-32) |
| **Debounce delay** | `300 ms` | Wait time before redistributing after events (50-1000) |
| **Max events per second** | `20` | Rate limit to prevent excessive recalculations (5-50) |
| **Exclude minimized** | `true` | Whether minimized windows are excluded from the layout |
| **Excluded window classes** | *(empty)* | Comma-separated list of window classes to never tile |

> **Note:** Changing settings requires reloading KWin: toggle the script off/on in System Settings, or run `qdbus6 org.kde.KWin /KWin reconfigure`.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Meta+Ctrl+1` | Set 1 column |
| `Meta+Ctrl+2` | Set 2 columns |
| `Meta+Ctrl+3` | Set 3 columns |
| `Meta+Ctrl+4` | Set 4 columns |
| `Meta+Ctrl+T` | Force re-tile all windows |

Shortcuts can be customized in **System Settings** > **Shortcuts** > search for "Auto Tile".

## Context Menu

Right-click any window's title bar to see the **Exclude from Auto-Tile** / **Include in Auto-Tile** option. Excluded windows are ignored by the tiling algorithm until re-included or closed.

## Architecture

```
Event (window open/close/move/minimize/...)
  │
  ▼
Rate Limiter (sliding window, max N events/sec)
  │
  ▼
Debounce (waits for burst to settle)
  │
  ▼
Group windows by (virtual desktop + monitor)
  │
  ▼
Sort by insertion order (stable layout)
  │
  ▼
Calculate geometry: width = (screen - gaps) / maxVisible
  │
  ▼
Apply frameGeometry to each window
```

### Key design decisions

- **Column width is always `screen / maxVisible`**, even with fewer windows. This keeps columns the same width as you add windows, matching the behavior of the niri compositor's scrollable tiling.
- **Insertion order is preserved** so windows don't jump around when other windows open/close.
- **Debounce uses recursive `callDBus` polling** since KWin's JavaScript environment doesn't expose `setTimeout`. A timestamp-based approach ensures only the latest burst triggers redistribution.
- **Layout cache** prevents redundant geometry writes. The cache key includes window IDs, count, maxVisible, and gap size.

### Signals monitored

| Signal | Triggers |
|--------|----------|
| `workspace.windowAdded` | New window → register + redistribute |
| `workspace.windowRemoved` | Closed window → cleanup + redistribute |
| `workspace.currentDesktopChanged` | Desktop switch → redistribute |
| `workspace.screensChanged` / `outputsChanged` | Monitor hotplug → invalidate cache + redistribute |
| `window.minimizedChanged` | Minimize/restore → redistribute |
| `window.fullScreenChanged` | Fullscreen toggle → redistribute |
| `window.desktopsChanged` | Window moved to another desktop → redistribute |
| `window.outputChanged` | Window moved to another monitor → redistribute |

## Project Structure

```
kwin-auto-tile/
├── metadata.json              # KWin Script metadata (Plasma 6)
├── contents/
│   ├── code/
│   │   └── main.js            # Core auto-tiling logic
│   ├── config/
│   │   └── main.xml           # Configuration schema (KCfg)
│   └── ui/
│       └── config.ui          # Settings UI (Qt Designer)
├── LICENSE
└── README.md
```

## Troubleshooting

### Script not loading after install

```bash
# Verify it's installed
kpackagetool6 --type=KWin/Script -l | grep auto-tile

# Check it's enabled in kwinrc
kreadconfig6 --file kwinrc --group Plugins --key kwin-auto-tileEnabled

# Force reload
qdbus6 org.kde.KWin /KWin reconfigure
```

### Windows not tiling

1. Check if the window is a **dialog, splash, or utility** — these are excluded by design
2. Check if the window class is in the **excluded list** in settings
3. Check if the window was manually excluded via right-click menu
4. Try `Meta+Ctrl+T` to force re-tile
5. Check KWin debug log: `journalctl --user -u plasma-kwin_wayland -f` (Wayland) or `~/.local/share/sddm/xorg-session.log` (X11)

### Conflicts with KDE native tiling

If you use KDE's built-in tiling zones, they may fight with this script. Disable native tiling in **System Settings** > **Window Management** > **Window Tiling** or exclude overlapping shortcuts.

### Shortcuts not working

Verify no conflicts in **System Settings** > **Shortcuts**. Search for "Auto Tile" to see all registered shortcuts and rebind if needed.

## Known Limitations

1. **No scrollable viewport** — unlike niri, KDE has a static screen. Windows beyond `maxVisible` are pushed off-screen rather than scrolled to.
2. **Config changes require KWin reload** — changing settings in System Settings requires toggling the script or running `qdbus6 org.kde.KWin /KWin reconfigure`.
3. **Shared maxVisible across desktops** — all virtual desktops use the same column count. Use keyboard shortcuts (`Meta+Ctrl+1-4`) for quick per-desktop adjustment.
4. **Debounce is approximate** — KWin JS lacks `setTimeout`, so debounce uses recursive D-Bus polling (~1-5ms granularity). Effective but not millisecond-precise.

## Related Projects

- [niri-auto-tile](https://github.com/pir0c0pter0/auto-tile) — The original auto-tiling daemon for the niri compositor (+ Noctalia Shell plugin)
- [niri](https://github.com/YaLTeR/niri) — Scrollable-tiling Wayland compositor
- [Bismuth](https://github.com/Bismuth-Forge/bismuth) — Full tiling window manager for KDE (archived)
- [Polonium](https://github.com/zeroxoneafour/polonium) — Tiling manager for KDE Plasma 6
- [Krohnkite](https://github.com/esjeon/krohnkite) — Dynamic tiling for KDE (Plasma 5)

## License

[MIT](LICENSE)

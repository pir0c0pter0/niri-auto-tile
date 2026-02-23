# Auto Tile

Automatic window tiling for Linux desktops. Open a window, and all visible windows instantly redistribute into equal-width columns.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Platforms

This repository contains two independent implementations of the same idea, one for each compositor/desktop environment:

| | niri | KDE Plasma 6 |
|---|---|---|
| **Directory** | [`niri-auto-tile/`](niri-auto-tile/) | [`kde-auto-tile/`](kde-auto-tile/) |
| **Type** | Python daemon + Noctalia Shell plugin | KWin Script (pure JavaScript) |
| **Compositor** | [niri](https://github.com/YaLTeR/niri) (scrollable-tiling Wayland) | KWin 6.x (Wayland / X11) |
| **Dependencies** | Python 3.10+, niri v25.11+ | KDE Plasma 6 (built-in) |
| **Configuration** | CLI args / Noctalia Settings UI | System Settings > KWin Scripts |
| **GUI** | Bar widget, floating panel, settings page | Settings dialog (config.ui) |

### How it looks

```
┌──────────┬──────────┬──────────┬──────────┐
│          │          │          │          │
│  Window  │  Window  │  Window  │  Window  │
│    1     │    2     │    3     │    4     │
│          │          │          │          │
└──────────┴──────────┴──────────┴──────────┘
              maxVisible = 4
```

Open a 5th window → it takes the next column slot (or goes off-screen/scrolled depending on the compositor). Close a window → the remaining ones fill the gap instantly.

---

## Quick Start

### niri

```bash
# Standalone
cp niri-auto-tile/auto-tile.py ~/.config/niri/auto-tile.py
python3 ~/.config/niri/auto-tile.py --max-visible 4

# Or as Noctalia Shell plugin
git clone https://github.com/pir0c0pter0/auto-tile.git \
  ~/.config/noctalia/plugins/niri-auto-tile
```

See [`niri-auto-tile/`](niri-auto-tile/) for full docs, Noctalia plugin UI screenshots, systemd service setup, and per-workspace configuration.

### KDE Plasma 6

```bash
# Install
cd kde-auto-tile
kpackagetool6 --type=KWin/Script -i .
kwriteconfig6 --file kwinrc --group Plugins --key kwin-auto-tileEnabled true
qdbus6 org.kde.KWin /KWin reconfigure
```

Or install via **System Settings** > **Window Management** > **KWin Scripts** > **Install from File**.

See [`kde-auto-tile/`](kde-auto-tile/) for full docs, keyboard shortcuts, context menu, and troubleshooting.

---

## Shared Features

Both implementations share the same core behavior:

- **Automatic redistribution** on window open/close/minimize/fullscreen
- **Column width = screen / maxVisible** — consistent column sizes even with fewer windows
- **Configurable column count** (1-8) with keyboard shortcuts
- **Per-monitor tiling** — each output is independent
- **Debounce + rate limiting** — no flickering during rapid events
- **Zero external dependencies** — each uses only its platform's native APIs
- **Window exclusion** — filter by class or exclude individual windows

### Key Differences

| Behavior | niri | KDE |
|----------|------|-----|
| Overflow windows | Scrolled off-screen (native viewport) | Moved off-screen to the right |
| Virtual desktops | Per-workspace with workspace-config JSON | Per-desktop (automatic) |
| Debounce | Real 300ms timer thread | Recursive callDBus polling (~1-5ms steps) |
| Event source | JSON event-stream (external process) | Direct KWin signals (in-process) |
| Thread model | Multi-threaded with Lock | Single-threaded (event loop) |
| GUI | Noctalia bar widget + panel + settings | System Settings config dialog |

---

## Repository Structure

```
auto-tile/
├── niri-auto-tile/           # niri compositor version
│   ├── auto-tile.py          #   Python daemon (core logic)
│   ├── Main.qml              #   Noctalia plugin entry point
│   ├── BarWidget.qml          #   Bar indicator widget
│   ├── Panel.qml             #   Floating panel
│   ├── Settings.qml          #   Settings page
│   ├── manifest.json         #   Noctalia plugin manifest
│   ├── settings.json         #   Default settings
│   ├── i18n/                 #   Translation reference files
│   └── PUBLISHING.md         #   Publishing guide
├── kde-auto-tile/            # KDE Plasma 6 version
│   ├── metadata.json         #   KWin Script metadata
│   └── contents/
│       ├── code/main.js      #   Core auto-tiling logic
│       ├── config/main.xml   #   Configuration schema (KCfg)
│       └── ui/config.ui      #   Settings UI (Qt Designer)
├── LICENSE                   # MIT
├── CLAUDE.md                 # Development guide
└── README.md                 # This file
```

---

## License

[MIT](LICENSE)

---

## Credits

Developed by Pir0c0pter0 using [Claude Code](https://claude.ai/claude-code).

### Acknowledgements

- [niri](https://github.com/YaLTeR/niri) by YaLTeR — scrollable-tiling Wayland compositor
- [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell) — desktop shell framework
- [KDE KWin](https://invent.kde.org/plasma/kwin) — KDE window manager with scripting API

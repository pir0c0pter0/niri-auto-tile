# Repository guide

This is a Noctalia Shell 5 plugin for niri. It uses plugin API 4 and has no
standalone mode or build step.

Version 2 is the only maintained line. Do not restore the discontinued
Noctalia 4 Python/QML architecture or add compatibility for its settings and
IPC unless explicitly requested.

## Runtime

- `niri-auto-tile/service.luau` owns the niri event stream, debounce, redistribution, and
  shared `division` state.
- `niri-auto-tile/widget.luau` displays the selected division and toggles the panel.
- `niri-auto-tile/panel.luau` selects and persists a division from 1 through 4.
- `niri-auto-tile/plugin.toml` declares the three entries and the external `niri` dependency.
- `niri-auto-tile/translations/` contains only strings used by the widget and panel.
- `catalog.toml` exposes the plugin through Noctalia Git sources.

Entries run in isolated VMs. Share plain values through `noctalia.state` and
persist only under `noctalia.pluginDataDir()`.

## Checks

```bash
lua test_service.lua
noctalia plugins lint niri-auto-tile
```

Keep `niri-auto-tile/service.luau` compatible with standard Lua syntax so its pure logic can
be loaded by the small test without a Noctalia runtime.

## Distribution

During the v2 testing period, publish changes only to the repository's Git
source. Do not submit the plugin to a Noctalia registry or open a registry pull
request until explicitly requested.

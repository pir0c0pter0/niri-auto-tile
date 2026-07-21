# Repository guide

This is a Noctalia Shell 5 plugin for niri. It uses plugin API 4 and has no
standalone mode or build step.

Version 2 is the only maintained line. Do not restore the discontinued
Noctalia 4 Python/QML architecture or add compatibility for its settings and
IPC unless explicitly requested.

## Runtime

- `service.luau` owns the niri event stream, debounce, redistribution, and
  shared `division` state.
- `widget.luau` displays the selected division and toggles the panel.
- `panel.luau` selects and persists a division from 1 through 4.
- `plugin.toml` declares the three entries and the external `niri` dependency.
- `translations/` contains only strings used by the widget and panel.

Entries run in isolated VMs. Share plain values through `noctalia.state` and
persist only under `noctalia.pluginDataDir()`.

## Checks

```bash
lua test_service.lua
noctalia plugins lint .
```

Keep `service.luau` compatible with standard Lua syntax so its pure logic can
be loaded by the small test without a Noctalia runtime.

## Distribution

During the v2 testing period, publish changes only to
`pir0c0pter0/niri-auto-tile`. Do not submit the plugin to a Noctalia registry
or open a registry pull request until explicitly requested.

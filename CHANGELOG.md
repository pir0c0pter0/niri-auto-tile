# Changelog

## 2.0.4 - 2026-07-23

### Fixed

- Redistribute only the affected workspace when it is active on its output.

## 2.0.3 - 2026-07-21

### Fixed

- Pull the full visible column group into the viewport after windows open or close.

## 2.0.2 - 2026-07-21

### Fixed

- Verify the layout after every window open or close so the remaining columns fill the viewport.

## 2.0.1 - 2026-07-21

### Fixed

- Keep every visible column group filling the viewport, including three-column layouts.
- Redistribute after columns move between workspaces, stacks, or floating state.

## 2.0.0 - 2026-07-21

Noctalia 5-only testing release. Not yet submitted to the official Noctalia
plugin registry.

### Breaking

- Discontinue the Noctalia 4/Python/QML line.
- Drop compatibility with the old plugin ID, settings, IPC, and standalone CLI.
- Do not migrate v1 configuration; version 2 starts with a global division of 4.

### Changed

- Migrate the plugin to Noctalia 5 plugin API 4 and the Luau runtime.
- Replace the Python/QML daemon architecture with service, widget, and panel entries.
- Keep only global 1–4 column selection, automatic redistribution, focus restoration, and persistence.

### Removed

- Remove standalone mode, legacy IPC/settings, per-workspace configuration, niri config editing, and runtime tuning controls.

## Legacy Noctalia 4 line — discontinued

## 1.11.0 - 2026-05-22

### Added

- Sync niri's top-level `layout.default-column-width` with auto-tile's global `maxVisible` value, then reload niri config with `niri msg action load-config-file`.
- Add `--niri-config-file` to override the niri config path used for default-column-width sync.
- Track `WindowsChanged`, `WindowLayoutsChanged`, and `WindowFocusChanged` from the event stream so open/close handling can use cached compositor state before falling back to IPC.
- Retry the open path when niri has announced a new window but has not published its settled workspace/column layout yet.

### Changed

- Coalesce event floods instead of dropping the pending resize outright after the rate limit is hit.
- Use shorter open/close debounce timings while keeping a bounded maximum debounce window for bursts.
- Re-anchor visible columns more quickly after layout corrections.

### Fixed

- New windows can now open at the current auto-tile width, avoiding the visible delay where niri's old default width remained until another focus event occurred.
- Window-list updates that arrive before `WindowOpenedOrChanged` are classified as open/close events instead of being treated as generic full redistributes.

# Changelog

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

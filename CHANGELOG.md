# Changelog

## Unreleased

### Added

- Keep a separate division per workspace and show each monitor's active workspace value in its bar widget; changing focus only updates the indicator.
- Persist workspace divisions across Noctalia restarts, with named-workspace restoration across compositor sessions and safe migration of the legacy default.
- Add Reapply and session-only Pause/Resume controls, with keyboard-accessible buttons.
- Identify the target workspace in the panel; expose independent save, layout, and event-stream warnings.
- Add isolated asynchronous runtime, UI, and shell failure tests without extra dependencies.

### Fixed

- Preserve the latest manual layout request while other workspace events or layout operations are in progress, without redirecting it to another workspace.
- Reject inconsistent focus snapshots with one bounded retry, and invalidate queries predating a pause even after a quick resume.
- Consistently skip redistribution while a floating window is focused, and ignore events that affect only floating windows.
- Retry failed event-stream launches with a bounded backoff and prevent old queries from overwriting the stream's topology cache.
- Preserve command failures and stderr while still attempting final focus restoration; report timeouts and truncated query responses.
- Keep layout errors visible after pausing or an inapplicable request without hiding the current request's result.
- Validate divisions consistently and preserve temporary preferences and save warnings across panel reopening; reselecting the current number retries saving.
- Preserve preferences when workspaces gain or change names, without automatically overwriting unreadable or malformed preference files.
- Avoid redundant UI updates when event-stream error state is already clear.

### Changed

- Update all ten translations and the panel screenshot for the new controls.
- Keep the second layout verification pass: available geometry does not prove that viewport framing is already correct.

## 2.0.8 - 2026-11-09

### Documentation

- Clarify focused-workspace behavior, global division defaults, redistribution triggers, and niri subprocess usage.
- Document Git-source updates, local-copy precedence, and Noctalia configuration file locations.
- Update contributor and distribution guides to reflect current versioning and GitHub release policy.
- No runtime changes from 2.0.7.

## 2.0.7 - 2026-11-09

### Fixed

- Apply the selected column width even when the workspace has no more columns than the selected division, including 25% widths for four columns.
- Redistribute only the focused workspace, leaving other monitors untouched and allowing layout selection while the panel owns keyboard focus.

## 2.0.6 - 2026-07-28

### Fixed

- Keep the active tiled window as centered as possible after redistribution.
- Avoid jumping to the first visible columns while niri's focus state settles after a window closes.

## 2.0.5 - 2026-07-23

### Fixed

- Keep existing column widths and only recenter when the selected layout already accommodates every column.

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

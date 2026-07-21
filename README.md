# niri-auto-tile

Noctalia 5 plugin that keeps niri's tiled columns evenly sized when windows
open or close.

> [!IMPORTANT]
> Version 2 is a Noctalia 5-only rewrite currently under testing. The previous
> Python/QML line for Noctalia 4 is discontinued and its settings are not
> compatible or migrated.

## Features

- Redistributes tiled columns after real window open/close events.
- Ignores floating windows and counts stacked windows as one column.
- Preserves focus while anchoring and centering visible columns.
- Provides a bar widget and a compact 1–4 column selector.
- Persists the selected division across Noctalia restarts.

The selected division is a visibility limit. With fewer columns, they fill the
screen. With more columns, each keeps `100 / division` percent width.

## Requirements

- Noctalia Shell 5.0 or newer
- niri

`niri` is listed as an external plugin dependency. Noctalia may display
“Requires: niri”; this is informational, not an installation error.

## Install from this repository

Until testing is complete, the plugin is available only from this repository
and is not published in the official Noctalia plugin registry.

Clone it inside a parent directory that Noctalia can use as a local source:

```bash
mkdir -p ~/Projects/noctalia-plugins-dev
git clone https://github.com/pir0c0pter0/niri-auto-tile \
  ~/Projects/noctalia-plugins-dev/niri-auto-tile
noctalia msg plugins source add niri-auto-tile-dev path \
  ~/Projects/noctalia-plugins-dev
noctalia msg plugins enable pir0c0pter0/niri-auto-tile
```

Add the widget to a bar in Noctalia's `settings.toml`:

```toml
[widget.niri-auto-tile]
type = "pir0c0pter0/niri-auto-tile:widget"

[bar.default]
center = ["date", "clock", "niri-auto-tile"]
```

Keep the other widgets already present in your bar list, then apply it:

```bash
noctalia config validate
noctalia msg config-reload
```

## Entries

- Widget: `pir0c0pter0/niri-auto-tile:widget`
- Panel: `pir0c0pter0/niri-auto-tile:panel`
- Service: `pir0c0pter0/niri-auto-tile:service`

Open the panel externally with:

```bash
noctalia msg panel-toggle pir0c0pter0/niri-auto-tile:panel
```

## Development

```bash
lua test_service.lua
noctalia plugins lint .
```

The runtime is entirely Luau. There is no standalone daemon, legacy IPC,
settings page, or automatic niri config editing.

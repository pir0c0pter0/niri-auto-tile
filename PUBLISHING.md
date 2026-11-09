# Distribution status

Version 2 is the maintained Noctalia 5-only line and remains under testing.
The current version is recorded in [plugin.toml](niri-auto-tile/plugin.toml)
and [catalog.toml](catalog.toml); see the [changelog](CHANGELOG.md) for changes.

For now:

- publish code only to `https://github.com/pir0c0pter0/niri-auto-tile`;
- install through the repository's Noctalia `git` source;
- publish a [GitHub Release](https://github.com/pir0c0pter0/niri-auto-tile/releases) only when explicitly requested; existing releases do not imply a Noctalia registry submission;
- do not copy the plugin into `noctalia-dev/official-plugins`;
- do not open a registry pull request or catalog submission.

Follow [AGENTS.md](AGENTS.md) before each push: create a separate release commit
with synchronized versions and a dated changelog entry, then an annotated tag.
Documentation-only pushes also require a patch release. Keep the README version
badge and distribution text synchronized with the manifests.

The discontinued Noctalia 4 Python/QML implementation remains available only
in Git history. It is not maintained, packaged, or supported by version 2.

Before any future registry submission, complete live testing of window
open/close handling, focus restoration, floating/stacked windows, all four
division choices, persistence, widget placement, panel behavior, and plugin
shutdown.

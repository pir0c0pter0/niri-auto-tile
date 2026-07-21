# Repository instructions

## Versioning and commits

Use [Semantic Versioning](https://semver.org/) from the current `2.0.1`
baseline and Conventional Commit messages for every new commit.

Commit types:

- `fix:` for a user-visible bug fix (next patch version).
- `feat:` for a backward-compatible feature (next minor version).
- `feat!:` or `fix!:` for a breaking change (next major version).
- `docs:`, `test:`, `refactor:`, `perf:`, `build:`, `ci:`, and `chore:` for
  changes that do not select a release bump by themselves.

Keep each commit focused and use the imperative mood, for example:

```text
fix: preserve focus after redistributing columns
feat: add a two-column quick action
docs: clarify Git source installation
```

Before pushing any non-release commit, prepare the corresponding release in a
separate release commit:

1. choose the highest SemVer impact since the previous release, using a patch
   bump when no commit type selects a larger bump;
2. update the same version in `niri-auto-tile/plugin.toml` and `catalog.toml`;
3. add a dated section to `CHANGELOG.md`;
4. commit as `chore(release): vX.Y.Z`; and
5. create the matching annotated `vX.Y.Z` tag.

During the version 2 testing period, push the release commit and tag only. Do
not create a GitHub Release or submit to the Noctalia registry unless the user
explicitly requests it.

Before committing code, run:

```bash
lua test_service.lua
noctalia plugins lint niri-auto-tile
```

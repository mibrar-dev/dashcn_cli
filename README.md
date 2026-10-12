# dashcn_cli

`dashcn_cli` is a command-line installer for dashcn-style Flutter component registries. It initializes a Flutter app with the shared foundation + theme layers, resolves components and their dependency closure from a registry, copies the required files, adds missing pub packages, and keeps install state in a project-local `dashcn.lock` (lockfileVersion 2).

## Features

- Layer-aware installs: `foundation/`, `theme/` and `primitives/` are pulled in as a dependency closure, never addressed as components.
- Transitive component closure with a single-owner symbol preflight.
- Hash-driven `update`: overwrite unchanged files, report local edits, install files the registry added, and never touch user-owned `<name>_theme.dart` files.
- Registry theme presets: `theme list` / `theme apply` generate a values-only `<installRoot>/theme/app_theme.dart`.
- Remote registry by default (GitHub raw at the CLI version's ref), with `--registry <path|url>` and an offline cache.
- Diagnostics for the manifest, closure, layout, lock drift and pub dependencies.
- JSON output and documented exit codes for scripts and CI.

## Installation

Activate the CLI globally:

```bash
dart pub global activate dashcn_cli
```

Make sure the Dart pub cache bin directory is on your `PATH`. Then verify the executable:

```bash
dashcn version
```

Installed components carry no per-file `// @dart=` language pins, so the app
they land in must declare `environment: sdk: ^3.12.0` or newer — the newest
language feature the registry uses shipped in Dart 3.12.0. See
[doc/user/complete-guide.md](doc/user/complete-guide.md) for the full
requirements list.

## Quick Start

Run commands from the root of an existing Flutter project:

```bash
dashcn init --yes
dashcn add button
```

`init` copies the always-on foundation + theme core, writes `.dashcn/config.json` and `dashcn.lock`, and generates the app theme from a preset (`neutral` by default). It asks "package or own the code?"; `--mode package|copy` answers non-interactively.

Prefer the published package over copied sources? Skip the copies entirely:

```bash
dashcn init --mode package --yes
dashcn add button --package
```

`add --package` runs `flutter pub add dashcn` (or `--path <dir>`), writes no
sources, and records `mode: package` in `dashcn.lock`. Turn a package
dependency back into owned sources later with `dashcn eject button`.

Point the CLI at a local registry checkout while developing a registry:

```bash
dashcn --registry ../dashcn-kit/dashcn/lib/src init --yes
```

## Common Workflows

List and inspect available registry content:

```bash
dashcn list
dashcn list --blocks
dashcn list --category "Forms & Inputs"
dashcn search button
dashcn info button
dashcn info login-01
```

Preview, install, update and remove components or blocks:

```bash
dashcn dry-run button
dashcn add button card alert
dashcn add login-01
dashcn update --check
dashcn update button
dashcn remove alert
dashcn remove login-01
```

Themes:

```bash
dashcn theme list
dashcn theme apply tangerine
dashcn theme apply tangerine --refresh
```

Bring a web theme (shadcn/tweakcn CSS, Tailwind v3 config or preset JSON) —
no registry needed. Import stores it as `<installRoot>/theme/<id>.json` and
prints the mapped/defaulted/ignored report; `--apply` also renders
`app_theme.dart`. Export renders the current theme back to the web:

```bash
dashcn theme import theme.css --name tweak
dashcn theme import theme.css --name tweak --apply
dashcn theme export --format css|tailwind|dtcg|json|dart [--out <file>]
```

The interop layer (`lib/src/theme_interop/`) is vendored from the kit's
`dashcn/lib/src/theme/interop/` — never edit it by hand; run
`tool/sync_interop.sh` (or `tool/sync_interop.sh --check` in CI) instead.

Diagnose project state:

```bash
dashcn doctor
dashcn validate
dashcn audit
```

## Blocks

A **block** is a ready-made, installable screen (`login-01`, `dashboard-01`,
`sidebar-07`, ...) assembled from components. Blocks are a fourth registry
layer under `blocks/`, and `add <id>` resolves a component and a block alike:

```bash
dashcn add login-01        # the block + every component it needs
dashcn add --all --blocks  # all components and all blocks
```

- a block installs to `lib/ui/dashcn/blocks/<id>/`, together with the
  transitive components, primitives, theme and foundation units it imports;
- `dashcn.lock` records installed blocks (a `blocks[]` array with their file
  hashes and closure), so `update`, `remove`, `sync`, `audit` and `doctor`
  all see them;
- a block owns **no** user-owned file: `update` may always refresh a block
  file whose bytes still match the lock, exactly as for a component;
- removing a block deletes only its own files; the components it assembled
  stay installed. Removing a component a block still needs is refused unless
  `--force`;
- `list --blocks`, `search` and `info <block>` report the block's `category`
  and `viewport`; block docs (`blocks/<id>/README.md`) are never copied into
  an app.

## Install Layout

Every install keeps the registry's directory depth so the relative imports inside the copied files stay valid:

```
lib/ui/dashcn/
  foundation/…               # shared primitives
  theme/…                    # theme tokens + the generated app_theme.dart
  primitives/…               # UI primitives
  components/<name>/        # one directory per installed component
  blocks/<id>/              # one directory per installed block
```…        # one directory per installed component
```

`<name>_theme.dart` files are **user-owned**: `add`, `update` and `remove` never overwrite or delete them unless `remove --purge-user-themes` is given.

## Registry and Install State

`dashcn` resolves a registry manifest (`manifests/registry.json`, schemaVersion 2) from the remote registry by default, or from `--registry <path|url>`. Remote reads are cached under `.dashcn/cache/registry` for offline re-installs (`--offline`).

Project state lives in two files:

- `.dashcn/config.json` — the install path, the selected theme id and the registry source.
- `dashcn.lock` — lockfileVersion 2: the registry reference, the install root, the theme selection, the layer units/files, each component's files, user-owned files and public symbols, and each installed block's files and closure.

## JSON and Exit Codes

Automation-friendly commands support `--json`:

```bash
dashcn doctor --json
dashcn validate --json
dashcn info button --json
```

The process exit code is also returned in `meta.exitCode` for JSON-capable commands. See [doc/reference/exit-codes.md](doc/reference/exit-codes.md) for the full exit-code table.

## Example

The [example](example/dashcn_cli_example.dart) script demonstrates the small public Dart API exported by the package for inspecting bundled theme preset metadata:

```bash
dart run example/dashcn_cli_example.dart
```

Most users should run the CLI executables instead of importing the package.

## Documentation

- User guide: [doc/index.md](doc/index.md)
- Getting started: [doc/user/getting-started.md](doc/user/getting-started.md)
- Complete guide: [doc/user/complete-guide.md](doc/user/complete-guide.md)
- Developer / local registry development: [doc/developer/local-registry-development.md](doc/developer/local-registry-development.md)
- Testing guide: [doc/testing-guide.md](doc/testing-guide.md)
- Command reference: [doc/reference/commands/index.md](doc/reference/commands/index.md)
- Exit codes: [doc/reference/exit-codes.md](doc/reference/exit-codes.md)

## Publishing Checks

Before publishing, run:

```bash
dart format --set-exit-if-changed .
dart analyze
dart test
dart pub publish --dry-run
```

The dry run prints every file that would be uploaded to pub.dev. Cancel publishing if internal reports, caches, generated graph data, or local-only artifacts appear in that list.

## License

This package is released under the BSD 3-Clause license. See [LICENSE](LICENSE).

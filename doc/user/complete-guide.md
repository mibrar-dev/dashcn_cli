# Complete User Guide

This is the A-Z guide for installing and using `dashcn`. The CLI installs Flutter UI components from a registry into your app, records what it installed in `dashcn.lock`, and gives you commands for discovery, theming, diagnostics and project recovery.

Quick path:

```bash
dart pub global activate dashcn_cli
dashcn init --yes
dashcn add button dialog input select calendar
flutter analyze
flutter build web
```

## 1. Requirements

You need:

- Flutter installed and available on `PATH`
- Dart installed through Flutter or the Dart SDK
- **Dart SDK 3.12.0 or newer** — the registry sources declare no per-file
  `// @dart=` pins, so the installed components compile against your app's SDK
  floor. The newest language feature they use (`private-named-parameters`, a
  `this._keys` field formal in a named-parameter list) shipped in Dart 3.12.0;
  an older floor fails with `experiment_not_enabled`.
- A Flutter project created with `flutter create` or an existing Flutter app
- Network access for the first remote registry fetch

Check your environment:

```bash
flutter --version
dart --version
```

## 2. Install the CLI

Install from pub.dev:

```bash
dart pub global activate dashcn_cli
```

Confirm the executable is available:

```bash
dashcn version
dashcn --help
```

The package also exposes a short `dashcn` alias. If the command is not found, add the Dart pub cache bin directory to your shell path:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

For zsh, put that line in `~/.zshrc`. For bash, put it in `~/.bashrc` or `~/.bash_profile`, then restart the terminal.

## 3. Initialize a Flutter Project

Run `init` from your Flutter project root:

```bash
flutter create --empty my_app
cd my_app
dashcn init --yes
```

What `init` does:

- copies every `foundation/` and `theme/` unit (no component)
- writes `.dashcn/config.json` and `dashcn.lock` (lockfileVersion 2)
- generates `<installRoot>/theme/app_theme.dart` from a preset

Choose a preset, install root, or install mode:

```bash
dashcn init --theme claude --yes
dashcn init --dir lib/dashcn --yes
dashcn init --mode package --yes
```

`--mode package` writes the config without copying any sources; components
then arrive as a pub dependency (see §4). The default `copy` mode owns the
sources in your app.

## 4. Add Components

Install one component:

```bash
dashcn add button
```

Install multiple components:

```bash
dashcn add button dialog input select calendar
```

An `@namespace/` prefix is accepted and stripped:

```bash
dashcn add @dashcn/button
```

Install every component from the selected registry:

```bash
dashcn add --all
```

Include preview files for a component:

```bash
dashcn add button --include-preview
```

### Package mode

Depend on the published package instead of copying sources:

```bash
dashcn add button --package
dashcn add button --package --path ../dashcn-kit/dashcn
```

`--package` runs `flutter pub add dashcn` (or a path dependency), writes no
sources, and records `mode: package` in `dashcn.lock`. Import the component
from the package:

```dart
import 'package:dashcn/components/button.dart';
```

Turn a package dependency back into owned sources with `eject`:

```bash
dashcn eject button
dashcn eject button --with-deps   # also eject transitive components
dashcn eject button --dry-run     # preview only
```

`eject` copies the sources into the install dir, flips the lock to
`mode: copy`, and rewrites your imports (direct imports are retargeted; a
barrel use gains an explicit owned import plus a `hide` on the barrel). It
refuses when a file to write was locally modified, unless `--force`.

## 5. Use Installed Components

After install, run:

```bash
flutter pub get
flutter analyze
```

Import the component from your install root. The default install root is `lib/ui/dashcn`:

```dart
import 'package:my_app/ui/dashcn/components/button/button.dart';
```

The exact import path depends on your app package name and the configured install root.

## 6. Discover Components

```bash
dashcn list
dashcn search toast
dashcn info gooey_toast
```

Use JSON output for scripts:

```bash
dashcn list --json
dashcn search button --json
dashcn info button --json
```

## 7. Preview Changes Before Writing

```bash
dashcn dry-run button dialog
dashcn dry-run --all
dashcn dry-run button dialog --json
```

`dry-run` reports the files, layer units and missing packages an install would involve.

## 8. Update Components

```bash
dashcn update --check
dashcn update button
dashcn update
```

`update` overwrites files whose bytes still match `dashcn.lock`, installs files the manifest has added, adds new pub packages, and reports locally modified files without touching them.

## 9. Remove Components

```bash
dashcn remove button
dashcn remove button badge
dashcn remove --all
dashcn remove button --force
```

Without `--force`, the CLI protects a component another installed component still depends on. User-owned `<name>_theme.dart` files are kept unless you pass `--purge-user-themes`.

## 10. Themes

```bash
dashcn theme list
dashcn theme apply amber-minimal
dashcn theme apply amber-minimal --refresh
```

`app_theme.dart` is user-owned. Without `--refresh`, an edited file is reported as drift (`theme_drift`, exit `80`) and left untouched.

## 11. Registries

```bash
dashcn registries
dashcn registries --json
dashcn default
dashcn default dashcn
```

Point the CLI at a local checkout or a hosted registry:

```bash
dashcn --registry /absolute/path/to/registry list
dashcn --registry https://example.com/registry add button
```

A remote registry is cached under `.dashcn/cache/registry`; `--offline` reads the cache only.

## 12. Sync Project State

Use `sync` after editing config or install paths, or to re-materialize a partially deleted install:

```bash
dashcn sync
```

## 13. Diagnostics

Run these before release:

```bash
dashcn validate
dashcn audit
dashcn doctor
flutter analyze
flutter test
flutter build web
```

What each diagnostic command does:

- `validate`: checks the registry manifest against the v2 schema and referenced files
- `audit`: compares installed files with the hashes in `dashcn.lock`
- `doctor`: reports the registry, install layout, closure gaps, lock drift and pubspec state

Machine-readable diagnostics:

```bash
dashcn validate --json
dashcn audit --json
dashcn doctor --json
dashcn update --check --json
```

## 14. Project Recovery

```bash
dashcn project reset
dashcn project reset --undo
dashcn project refresh
```

Typical use:

- `project reset`: snapshot and remove CLI-managed project artifacts
- `project reset --undo`: restore the latest non-expired reset snapshot
- `project refresh`: repair missing managed files without overwriting installed components

Global reset clears CLI-managed home-directory state:

```bash
dashcn reset
```

Use global reset when the cache or CLI home state is corrupted, not as a normal project cleanup command.

## 15. Tooling Commands

```bash
dashcn version
dashcn version --check
dashcn upgrade
dashcn upgrade --force
dashcn feedback
```

Advanced docs maintenance:

```bash
dashcn --advanced docs --generate
```

## 16. Global Flags

Global flags are passed before the command:

```bash
dashcn --verbose add button
dashcn --offline list
dashcn --registry ../registry add button
dashcn --advanced --help
```

Flags:

- `--verbose`: print extra logs
- `--offline`: disable network calls and use the cache only
- `--registry <path|url>`: override the registry source
- `--registry-name <namespace>`: select the active namespace
- `--advanced`: enable developer commands and options

## 17. Recommended Production Workflow

```bash
dart pub global activate dashcn_cli
dashcn version

flutter create --empty my_app
cd my_app

dashcn init --yes
dashcn registries
dashcn list

dashcn dry-run button dialog input select calendar
dashcn add button dialog input select calendar

flutter pub get
dashcn doctor
dashcn validate
dashcn audit
dashcn update --check

flutter analyze
flutter test
flutter build web
```

Commit these files:

- `.dashcn/config.json`
- `dashcn.lock`
- Generated files under your install root, usually `lib/ui/dashcn/`
- `pubspec.yaml` and `pubspec.lock`

## 18. Troubleshooting

### Command not found

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

Then reopen the terminal.

### Registry fetch fails

```bash
dashcn registries
dashcn doctor
dashcn --verbose list
```

Use `--offline` only after the registry has been cached.

### Analyzer fails after install

```bash
flutter pub get
dashcn doctor
dashcn audit
flutter analyze
```

The registry sources are lint-clean under a stock app's `flutter_lints`, so the install root needs no nested analyzer configuration.

### You need to undo CLI-managed files

```bash
dashcn project reset
dashcn project reset --undo
```

`project reset` creates a snapshot first; `project reset --undo` restores the latest non-expired snapshot.

## 19. Command Index

| Command | Purpose |
| --- | --- |
| `init` | Install the layer core and generate the app theme. |
| `add` | Install components and their closure. |
| `eject` | Turn a package-mode component into owned sources. |
| `remove`, `rm` | Remove installed components and orphaned layer files. |
| `update` | Update installed components from the registry. |
| `dry-run` | Preview installs without writes. |
| `list`, `ls` | List available components. |
| `search` | Search the registry catalog. |
| `info`, `i` | Show a component's closure, files and API. |
| `theme` | List and apply theme presets. |
| `registries` | List configured/discovered registries. |
| `default` | Show or set the default namespace. |
| `sync` | Re-apply the installed closure and locked theme. |
| `project` | Repair or reset CLI-managed project files. |
| `doctor` | Diagnose the manifest, closure, layout and lock drift. |
| `validate` | Validate the registry manifest against the v2 schema. |
| `audit` | Compare installed files against `dashcn.lock`. |
| `reset` | Clear global CLI-managed state. |
| `feedback` | Submit guided feedback or issue reports. |
| `version` | Show the CLI version. |
| `upgrade` | Upgrade the CLI. |
| `docs` | Advanced generated command reference maintenance. |

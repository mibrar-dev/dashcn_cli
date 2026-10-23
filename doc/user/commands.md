# Commands

This page explains every public command in `dashcn`. The CLI installs components and their layer closure from a registry manifest (schemaVersion 2), keeps install state in `dashcn.lock` (lockfileVersion 2), and resolves the registry remotely by default.

For the full installation-to-production workflow, read the [complete user guide](complete-guide.md).

## Global Options

Global options appear before the command.

```bash
dashcn --verbose add button
dashcn --offline list
dashcn --registry ../dashcn-kit/dashcn/lib/src init --yes
dashcn --registry https://example.com/registry validate
```

Options:

- `--verbose`, `-v`: print more detail while commands run.
- `--offline`: disable network calls and use the cached registry only.
- `--registry <path|url>`: override the registry source with a local directory or an `http(s)` URL.
- `--registry-name <namespace>`: select the registry namespace.
- `--advanced`: show and enable developer commands (for example `docs`).
- `--help`, `-h`: show help.

## `init`

Installs the always-on foundation + theme core and generates the app theme.

```bash
dashcn init
dashcn init --theme vercel --yes
dashcn init --dir lib/dashcn --yes
```

What it does:

- copies every `foundation/` and `theme/` unit (no component)
- writes `.dashcn/config.json` and `dashcn.lock` (lockfileVersion 2)
- generates `<installRoot>/theme/app_theme.dart` from the chosen preset

Options:

- `--dir <path>`: install root (default `lib/ui/dashcn`).
- `--theme <id>`: theme preset id (default `vercel`).
- `--yes`, `-y`: run non-interactively and use the default preset.
- `--json`: print machine-readable output.

## `add`

Installs one or more components and their transitive closure.

```bash
dashcn add button
dashcn add button dialog input select calendar
dashcn add --all
```

What it does:

- resolves the closure: requested components, their component/primitive deps, and the foundation + theme core
- refuses an install that would define the same public symbol twice
- copies files verbatim into the depth-preserving layout
- installs component translations into `dashcn_locales/` (English base plus every installed locale, containing only the keys the installed components need; older registries without `localizationKeys` keep the full copy instead)
- adds missing pub packages to `pubspec.yaml` and runs `flutter pub get`
- updates `dashcn.lock`

Options:

- `--all`, `-a`: install every available component.
- `--dry-run`: print the plan without writing anything.
- `--force`, `-f`: overwrite locally modified registry files.
- `--include-preview`: also copy each component's `preview.dart`.
- `--json`: print machine-readable output.

User-owned `<name>_theme.dart` files are never overwritten.

## `remove`

Removes installed components and any layer file no remaining install needs.

```bash
dashcn remove button
dashcn remove --all
dashcn remove button --purge-user-themes
```

Options:

- `--all`, `-a`: remove every installed component.
- `--force`, `-f`: remove even when dependents remain.
- `--purge-user-themes`: also delete `<name>_theme.dart` user files.
- `--json`: print machine-readable output.

Without `--force`, the CLI protects a component that another installed component still depends on. Without `--purge-user-themes`, user-owned theme files stay on disk.

## `update`

Updates installed components to the registry's current files.

```bash
dashcn update
dashcn update button
dashcn update --check
```

What it does:

- overwrites registry-owned files whose bytes still match `dashcn.lock`
- installs files the manifest has added since the install (and their new layer deps)
- reports locally modified files and leaves them untouched
- adds new pub packages the closure needs
- regenerates `app_theme.dart` from the locked preset

Options:

- `--all`, `-a`: update every installed component.
- `--check`: report only; exit `1` when anything is behind or modified.
- `--json`: print machine-readable output.

`update` never reads or writes user-owned `<name>_theme.dart` files.

## `dry-run`

Shows what `add` would do without writing files.

```bash
dashcn dry-run button
dashcn dry-run --all --json
```

Options:

- `--all`, `-a`: include every registry component.
- `--json`: print machine-readable output.

## `list`

Lists available components in the registry.

```bash
dashcn list
dashcn list --json
```

Options:

- `--json`: print machine-readable output.

## `search`

Searches registry components by name, description, or tags.

```bash
dashcn search button
dashcn search form --json
```

Options:

- `--json`: print machine-readable output.

## `info`

Shows a component's closure, files and public API.

```bash
dashcn info button
dashcn info button --json
```

Options:

- `--json`: print machine-readable output.

The `import` field is computed from the install root and the component entry, so it matches the real install layout.

## `theme`

Lists or applies registry theme presets.

```bash
dashcn theme list
dashcn theme apply vercel
dashcn theme apply tangerine --refresh
```

Options:

- `--refresh`: overwrite `app_theme.dart` even when it was edited.
- `--json`: print machine-readable output.

`app_theme.dart` is user-owned: without `--refresh` a locally modified file is reported as drift (`theme_drift`, exit `80`) and left untouched. `theme apply` validates the preset against `themes.schema.json` (schemaVersion 2) and writes the values-only theme file.

## `sync`

Re-applies the installed closure and the locked theme.

```bash
dashcn sync
```

Use `sync` after manually editing config or install paths, or to re-materialize a partially deleted install.

## `locale`

Installs and manages component translations. Class and parameter names stay English; only UI strings are translated.

```bash
dashcn locale add ar
dashcn locale list
dashcn locale remove ar
```

What it does:

- `locale add <code>` installs a language for every installed component; later `dashcn add` runs include it automatically
- `locale list` shows every locale the registry ships and which ones the project has
- `locale remove <code>` drops a language again
- files land in `dashcn_locales/` (`dashcn_locale_<code>.dart` per locale, a `dashcn_locales.dart` barrel exposing `dashcnLocalesDelegates`/`dashcnSupportedLocales`, and `state.json`); every command is idempotent and re-running writes nothing

Wire the barrel into your app alongside the material delegates:

```dart
MaterialApp(
  localizationsDelegates: [
    ...dashcnLocalesDelegates,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: dashcnSupportedLocales,
);
```

Options:

- `--json`: print machine-readable output.

## `project`

Project-scoped repair and cleanup.

```bash
dashcn project reset
dashcn project reset --undo
dashcn project refresh
```

- `project reset`: removes CLI-managed files with a 24-hour undo window.
- `project refresh`: re-applies the installed closure and the locked theme.

## `registries`

Lists configured and discoverable registries.

```bash
dashcn registries
dashcn registries --json
```

Options:

- `--json`: print machine-readable output.

## `default`

Shows or sets the default registry namespace and source mode.

```bash
dashcn default
dashcn default dashcn
dashcn default dashcn --local
dashcn default dashcn --remote
```

Options:

- `--local`: persist a local development registry.
- `--remote`: switch back to the published remote registry.

## `validate`

Validates the registry manifest against the v2 schema.

```bash
dashcn validate
dashcn validate --json
```

What it checks:

- `schemaVersion` is 2 and required top-level keys are present
- every `deps` reference resolves
- every declared file exists and has a `fileHashes` entry
- relative paths and ids match the schema

Options:

- `--json`: print machine-readable output.

## `audit`

Compares installed files against `dashcn.lock`.

```bash
dashcn audit
dashcn audit --json
```

Use this to find drift between installed files and the recorded hashes. User-owned files are reported but never treated as updatable.

Options:

- `--json`: print machine-readable output.

## `doctor`

Diagnoses the manifest, closure, layout and lock drift.

```bash
dashcn doctor
dashcn doctor --json
```

What it reports:

- whether the manifest loads and validates
- whether every installed component's closure is present
- whether the layer directories exist at the right depth
- whether each installed file's hash matches the lock
- whether `pubspec.yaml` has the required SDK dependencies

Exit codes: `0` clean, `1` drift/modified, `2` broken closure, `3` manifest invalid.

Options:

- `--json`: print machine-readable output.

## `reset`

Clears the global CLI-managed cache and home-directory state.

```bash
dashcn reset
```

## `feedback`

Submits feedback or issue reports.

```bash
dashcn feedback
dashcn feedback --type bug --title "Button issue" --body "Describe the issue"
```

Options:

- `--type`, `-t`: `bug`, `feature`, `docs`, `question`, or `other`.
- `--title`: issue title.
- `--body`: issue body.

Without options, the command runs interactively.

## `version`

Shows CLI version information.

```bash
dashcn version
dashcn version --check
```

Options:

- `--check`: check for available updates.

## `upgrade`

Upgrades the CLI from pub.dev.

```bash
dashcn upgrade
dashcn upgrade --force
```

Options:

- `--force`, `-f`: force upgrade even if the installed version appears current.

## `docs` (advanced)

Regenerates the command reference from the CLI metadata.

```bash
dashcn --advanced docs --generate
```

Options:

- `--generate`, `-g`: regenerate `doc/reference/commands`.

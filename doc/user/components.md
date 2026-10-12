# Components

Components are registry-defined installable units such as buttons, dialogs, inputs and calendars. The registry manifest decides which files belong to a component; the CLI installs those files into your configured install root.

## Addressing Components

Use the component id from `list`/`search`:

```bash
dashcn add button
```

An `@namespace/` prefix is accepted and stripped, so `@dashcn/button` installs `button`.

## Source of Truth

The registry manifest (`manifests/registry.json`, schemaVersion 2) is the single source of truth. Each `components/<id>` entry declares:

- `files`: the registry-owned files copied verbatim
- `userOwned`: `<name>_theme.dart` files the CLI writes once and never overwrites
- `deps`: the component/primitive/foundation/theme closure
- `api`: the public symbols, used for the single-owner preflight

## Installing Multiple Components

```bash
dashcn add button dialog input select calendar
```

The CLI resolves the transitive closure, refuses an install that would define the same public symbol twice, copies the files, adds missing pub packages to `pubspec.yaml`, runs `flutter pub get`, and updates `dashcn.lock`.

## Installed Files

The CLI writes:

- the depth-preserving install root (default `lib/ui/dashcn/`): `foundation/`, `theme/`, `primitives/`, `components/<id>/`
- `<installRoot>/theme/app_theme.dart` (generated from a theme preset)
- `.dashcn/config.json` and `dashcn.lock`
- `pubspec.yaml`, when the closure declares managed packages

## User-Owned Theme Files

`<name>_theme.dart` files are yours. `add`, `update` and `remove` never overwrite or delete them; `remove --purge-user-themes` is the only way to delete them.

## Removing Components

```bash
dashcn remove button
```

Removal respects dependency relationships: if another installed component still depends on the one you want to remove, the command refuses.

To override that guard:

```bash
dashcn remove button --force
```

To remove all installed components:

```bash
dashcn remove --all
```

## Updating Components

```bash
dashcn update --check
dashcn update button
```

`update` overwrites files whose bytes still match `dashcn.lock`, installs files the manifest has added since the install, and reports locally modified files without touching them.

## Preview an Install

```bash
dashcn dry-run button
dashcn dry-run button --json
```

`dry-run` shows the planned component files, layer units, dependencies and missing packages without writing them.

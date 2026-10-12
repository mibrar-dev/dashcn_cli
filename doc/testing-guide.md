# Flutter Dashcn CLI Testing And Usage Guide

This guide is written for people who are not working inside the CLI codebase. Send this file to anyone who needs to test the CLI or learn the basic workflow.

Use a disposable Flutter project while testing. Do not run `remove` or `reset` commands inside a real app unless you are sure you want to change it.

## What You Need

Install these first:

```bash
flutter --version
dart --version
```

Install the CLI:

```bash
dart pub global activate dashcn_cli
dashcn version
```

If `dashcn` is not found, add the Dart pub cache bin folder to your shell path:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

## Create A Test App

Create a fresh app for testing:

```bash
flutter create --empty dashcn_cli_test_app
cd dashcn_cli_test_app
flutter pub get
```

All commands below should be run from inside this app folder.

## Quick Use Flow

Run the CLI setup:

```bash
dashcn init --yes
```

Expected result:

- `.dashcn/config.json` exists.
- `dashcn.lock` exists (`lockfileVersion: 2`).
- `lib/ui/dashcn/foundation/` and `lib/ui/dashcn/theme/` exist.
- `lib/ui/dashcn/theme/app_theme.dart` exists.

List components:

```bash
dashcn list
```

Search for a component:

```bash
dashcn search button
```

Preview an install without writing files:

```bash
dashcn dry-run button
```

Install a component:

```bash
dashcn add button
```

Expected result:

- Button files are created under `lib/ui/dashcn/components/button/`.
- The layer closure (primitives, foundation, theme) is present.
- `dashcn.lock` records the component and its files.

Check project health:

```bash
dashcn doctor
dashcn audit
dashcn update --check
flutter analyze
```

Expected result:

- `doctor` completes with exit `0`.
- `audit` reports installed files are present.
- `update --check` reports nothing to do.
- `flutter analyze` finishes with `No issues found!`.

## Test Init In Detail

Start from a clean app, then run:

```bash
dashcn init --yes
```

Check the files created by init:

```bash
find .dashcn -maxdepth 4 -type f | sort
find lib/ui/dashcn/foundation lib/ui/dashcn/theme -type f | sort
```

The important files/folders are:

```text
.dashcn/config.json
dashcn.lock
lib/ui/dashcn/foundation/
lib/ui/dashcn/theme/
```

Run init again:

```bash
dashcn init --yes
```

Expected result:

- It should not corrupt `.dashcn/config.json`.
- It should not duplicate dependencies in `pubspec.yaml`.
- It should not delete installed files.

## Test Every Main Command

Run this command checklist from the test app.

### Help And Version

```bash
dashcn --help
dashcn version
dashcn init --help
dashcn add --help
dashcn remove --help
dashcn update --help
dashcn doctor --help
```

Expected result: every command prints help or version text and exits cleanly.

### Registry Discovery

```bash
dashcn registries
dashcn default
dashcn list
dashcn search button
dashcn info button
```

Expected result:

- `registries` shows the configured registry source.
- `list` shows available components.
- `search button` includes `button`.
- `info button` shows the closure, files and import path.

### Dry Run

```bash
dashcn dry-run button
dashcn dry-run --all
```

Expected result:

- No component files are written by `dry-run`.
- `dry-run button` shows the files and packages that would be installed.

### Add Components

Install a small set first:

```bash
dashcn add button
dashcn add dialog input select calendar
```

Check generated files:

```bash
find lib/ui/dashcn/components -maxdepth 5 -type f | sort
```

Expected result:

- Component Dart files exist.
- Existing files are not duplicated if you run the same `add` again.

Install all components when doing a full QA pass:

```bash
dashcn add --all
dashcn audit
dashcn update --check
flutter analyze
```

Expected result:

- All components install successfully.
- `audit` succeeds.
- `update --check` reports nothing to do.
- `flutter analyze` succeeds.

### Update Components

```bash
dashcn update --check
dashcn update
```

Expected result:

- `--check` reports whether anything is behind or modified and exits `1` when it is.
- `update` overwrites files whose bytes still match `dashcn.lock` and leaves locally modified files alone.

### Remove Components

```bash
dashcn remove button
dashcn audit
dashcn add button
dashcn audit
```

Expected result:

- `remove button` removes the registry-owned button files and keeps `button_theme.dart`.
- `audit` should still work.
- Re-adding `button` should restore it.

### Theme

```bash
dashcn theme list
dashcn theme apply amber-minimal
dashcn theme apply amber-minimal --refresh
```

Expected result:

- Theme list loads.
- Applying a theme writes `<installRoot>/theme/app_theme.dart`.
- `.dashcn/config.json` and `dashcn.lock` record the selected theme.
- Without `--refresh`, an edited `app_theme.dart` is reported as drift (`theme_drift`, exit `80`).

### Sync

```bash
dashcn sync
```

Expected result: `sync` re-applies the installed closure and the locked theme without deleting installed components.

## Test Error Cases

These commands should fail in a clear way.

Missing component:

```bash
dashcn add component_that_does_not_exist
```

Expected result: the CLI exits `30` and says the component was not found.

Missing registry path:

```bash
dashcn --registry /tmp/does-not-exist list
```

Expected result: the CLI exits `10` and says the local registry was not found.

## Test With A Local Registry Checkout

Use this when testing changes before publishing the registry.

```bash
REGISTRY_ROOT=/absolute/path/to/dashcn-kit/dashcn/lib/src
dashcn --registry "$REGISTRY_ROOT" init --yes
dashcn --registry "$REGISTRY_ROOT" add button
dashcn --registry "$REGISTRY_ROOT" doctor
```

The `--registry` override points the CLI at the checkout instead of the remote registry.

## What To Record While Testing

For each failed command, record:

- The command you ran.
- The full output.
- The exit code if available.
- The files that changed.
- Whether this was a published registry or a local registry test.

Useful evidence commands:

```bash
find .dashcn -maxdepth 5 -type f | sort
find lib/ui/dashcn -type f | sort
cat pubspec.yaml
dashcn doctor --json
dashcn audit --json
dashcn update --check --json
flutter analyze
```

## Pass Checklist

Use this checklist for a release test:

- [ ] `dashcn version` works.
- [ ] `dashcn --help` works.
- [ ] `dashcn init --yes` creates `.dashcn/config.json`, `dashcn.lock` and the theme.
- [ ] `list`, `search`, `info`, and `dry-run` work.
- [ ] `add button` installs files and updates the lock.
- [ ] `add --all` installs all registry components.
- [ ] `doctor` passes after install.
- [ ] `audit` passes after install.
- [ ] `update --check` reports nothing to do after a fresh install.
- [ ] `flutter analyze` passes after install.
- [ ] `remove button` and re-add works, keeping `button_theme.dart`.
- [ ] Theme commands behave clearly.
- [ ] Missing component errors are clear.
- [ ] Missing local registry errors are clear.

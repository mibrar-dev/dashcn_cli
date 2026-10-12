# Getting Started

`dashcn` installs Flutter UI components from a registry into your project. It keeps project configuration in `.dashcn/config.json` and install state in `dashcn.lock` (lockfileVersion 2).

## Install

```bash
dart pub global activate dashcn_cli
```

Make sure the Dart pub cache bin directory is on your shell path.

## Initialize a Project

Run this from your Flutter project root:

```bash
dashcn init --yes
```

This copies the always-on foundation + theme layers, writes `.dashcn/config.json` and `dashcn.lock`, and generates `<installRoot>/theme/app_theme.dart` from a preset (`vercel` by default). It does not install any component.

Choose a different preset or install root:

```bash
dashcn init --theme claude --yes
dashcn init --dir lib/dashcn --yes
```

## Add Your First Component

```bash
dashcn add button
```

The CLI resolves the component's closure, copies the files into `lib/ui/dashcn/`, adds any missing pub packages to `pubspec.yaml`, and updates `dashcn.lock`.

## Find Components

```bash
dashcn list
dashcn search button
dashcn info button
```

`list` shows available components, `search` filters by text, and `info` shows a component's closure, files and public API.

## Update and Remove

```bash
dashcn update --check
dashcn update button
dashcn remove button
```

## Themes

```bash
dashcn theme list
dashcn theme apply tangerine
```

## Common Workflow

```bash
dashcn init --yes
dashcn list
dashcn add button
dashcn doctor
```

Use `doctor` after setup or when registry resolution feels wrong.

## More Docs

- Complete A-Z guide: [complete-guide.md](complete-guide.md)
- Command guide: [commands.md](commands.md)
- Components: [components.md](components.md)
- Registries: [registries.md](registries.md)
- Troubleshooting: [troubleshooting.md](troubleshooting.md)

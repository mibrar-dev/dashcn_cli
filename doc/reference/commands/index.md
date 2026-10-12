# Command Reference

Generated from CLI command metadata. Do not edit these files by hand.

## Components

- [`dashcn add`](./components/add.md) - Install one or more components or blocks and their closure.
- [`dashcn eject`](./components/eject.md) - Turn a package-mode component into owned sources.
- [`dashcn remove`](./components/remove.md) - Remove installed components, blocks and orphaned layer files.
- [`dashcn update`](./components/update.md) - Update installed components from the registry.
- [`dashcn dry-run`](./components/dry-run.md) - Preview what add would install.
- [`dashcn list`](./components/list.md) - List available components or blocks, by category.
- [`dashcn search`](./components/search.md) - Search components and blocks by name, description or tag.
- [`dashcn info`](./components/info.md) - Show a component's or block's closure, files and api.

## Project

- [`dashcn init`](./project/init.md) - Install the layer core and generate the app theme.
- [`dashcn registries`](./project/registries.md) - List configured and discoverable registries.
- [`dashcn default`](./project/default.md) - Set or show the default registry namespace.
- [`dashcn sync`](./project/sync.md) - Re-apply the installed closure and locked theme.
- [`dashcn project`](./project/project.md) - Project repair and cleanup commands.
- [`dashcn theme`](./project/theme.md) - List and apply registry theme presets.

## Diagnostics

- [`dashcn reset`](./diagnostics/reset.md) - Clear global CLI-managed cache and home-directory state.
- [`dashcn doctor`](./diagnostics/doctor.md) - Diagnose the manifest, closure, layout and lock drift.
- [`dashcn validate`](./diagnostics/validate.md) - Validate the registry manifest against the v2 schema.
- [`dashcn audit`](./diagnostics/audit.md) - Compare installed files against dashcn.lock.

## Tooling

- [`dashcn feedback`](./tooling/feedback.md) - Submit feedback or report issues.
- [`dashcn version`](./tooling/version.md) - Show the CLI version.
- [`dashcn upgrade`](./tooling/upgrade.md) - Upgrade the CLI to the latest version.

## Advanced

Advanced commands require `--advanced`.

- [`dashcn docs`](./advanced/docs.md) - Regenerate command reference documentation.

# dashcn init

> Install the layer core and generate the app theme.

## Usage

```bash
dashcn init [flags]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--dir <path>` |  |  | Install root (default: lib/ui/dashcn). |
| `--theme <id>` |  |  | Theme preset id (default: neutral). |
| `--mode <mode>` |  |  | `copy` (own the sources) or `package` (pub dep). |
| `--yes` | `-y` | `false` | Non-interactive; use the default preset. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn init
dashcn init --theme vercel --yes
dashcn init --mode package
```

## Notes

Copy mode copies every foundation and theme unit (no component), writes .dashcn/config.json and dashcn.lock v2, and generates <installRoot>/theme/app_theme.dart from the chosen preset. Package mode writes the config only; components then arrive via `dashcn add <id> --package`.

## See Also

- [`dashcn registries`](registries.md)
- [`dashcn default`](default.md)
- [`dashcn theme`](theme.md)
- [`dashcn add`](../components/add.md)

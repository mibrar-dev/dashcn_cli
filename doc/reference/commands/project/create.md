# dashcn create

> Scaffold a runnable app from a starter.

## Usage

```bash
dashcn create <starter> <name> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<starter>` | Yes | Starter id: saas, chat, shop. |
| `<name>` | Yes | App directory to create. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--theme <preset|file.css>` |  |  | Theme preset or CSS file to import. |
| `--mode <mode>` |  |  | `copy` (own the sources) or `package` (pub dep). |
| `--platforms <list>` |  |  | Comma list of platforms. |
| `--org <id>` |  |  | Org for flutter create (default: com.example). |
| `--force` | `-f` | `false` | Overwrite a non-empty target dir. |
| `--dry-run` |  | `false` | Print the plan without writing anything. |
| `--list` |  | `false` | List available starters. |

## Examples

```bash
dashcn create saas my_app
dashcn create chat my_app --theme vercel --mode package
dashcn create --list
```

## Notes

Runs flutter create --empty, then package mode adds the dashcn pub dependency while copy mode owns the sources under lib/ui/dashcn/ via the installer. Templates render with simple {{var}} substitution and the result is dart formatted.

## See Also

- [`dashcn init`](init.md)
- [`dashcn add`](../components/add.md)
- [`dashcn theme`](theme.md)

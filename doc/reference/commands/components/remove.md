# dashcn remove

> Remove installed components, blocks and orphaned layer files.

## Aliases

- `rm`

## Usage

```bash
dashcn remove <component|block...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component|block...>` | No | Installed component or block names to remove. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Remove every installed component and block. |
| `--force` | `-f` | `false` | Remove even when dependents remain. |
| `--purge-user-themes` |  | `false` | Also delete <name>_theme.dart user files. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn remove button
dashcn remove login-01
dashcn rm dialog
```

## Notes

Refuses while another installed component or block still needs the target, unless --force. A block owns no user-owned file, so removing one deletes every path it recorded.

## See Also

- [`dashcn add`](add.md)
- [`dashcn list`](list.md)

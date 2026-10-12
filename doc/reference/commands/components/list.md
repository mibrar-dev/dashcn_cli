# dashcn list

> List available components, blocks or flows, by category.

## Aliases

- `ls`

## Usage

```bash
dashcn list [--blocks] [--flows] [--category <name>] [--json]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--blocks` |  | `false` | List the blocks layer instead of components. |
| `--flows` |  | `false` | List the flows layer instead of components. |
| `--category <name>` |  | `false` | Only entries of that category. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn list
dashcn list --blocks
dashcn list --flows
dashcn list --category "Forms & Inputs"
dashcn ls --json
```

## Notes

Human output groups entries by the category each meta.json declares; the JSON envelope keeps `components`, `blocks` and `flows` so a consumer never has to probe for a key.

## See Also

- [`dashcn search`](search.md)
- [`dashcn info`](info.md)
- [`dashcn add`](add.md)

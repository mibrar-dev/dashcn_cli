# dashcn search

> Search components and blocks by name, description or tag.

## Usage

```bash
dashcn search <query> [--category <name>] [--json]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<query>` | Yes | Search text. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--category <name>` |  | `false` | Only entries of that category. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn search button
dashcn search login --category Authentication
```

## Notes

Both kinds are searched at once, because `add <id>` resolves both. Each result carries its `kind`, `category` and, for a block, its `viewport`.

## See Also

- [`dashcn list`](list.md)
- [`dashcn info`](info.md)

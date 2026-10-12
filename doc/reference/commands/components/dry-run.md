# dashcn dry-run

> Preview what add would install.

## Usage

```bash
dashcn dry-run <component...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component...>` | No | Components to preview. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Preview every component. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn dry-run button
```

## See Also

- [`dashcn add`](add.md)

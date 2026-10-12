# dashcn dry-run

> Preview what add would install (components, blocks, flows).

## Usage

```bash
dashcn dry-run <component|block|flow:flow...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component|block|flow:flow...>` | No | Components, blocks or flows to preview. |

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

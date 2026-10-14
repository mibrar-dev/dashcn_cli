# dashcn info

> Show a component's, block's or flow's closure, files and api.

## Aliases

- `i`

## Usage

```bash
dashcn info <component|block|flow:flow> [--json]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component|block|flow:flow>` | Yes | Component, block or flow:flow name, or @namespace/component address. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn info button
dashcn info login-01
dashcn info flow:auth-01
dashcn i dialog
```

## Notes

A component reports its api and user-owned theme files; a block reports its viewport, its own files and the components it assembles; a flow reports its screens, viewport and components/blocks closure.

## See Also

- [`dashcn list`](list.md)
- [`dashcn search`](search.md)
- [`dashcn add`](add.md)

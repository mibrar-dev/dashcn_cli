# dashcn project

> Project repair and cleanup commands.

## Usage

```bash
dashcn project <reset|refresh> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<reset|refresh>` | Yes | Project-scoped maintenance command to run. |

## Flags

This command does not define command-specific flags.

## Examples

```bash
dashcn project reset
dashcn project reset --undo
dashcn project refresh
```

## Notes

`project reset` removes CLI-managed files with a 24-hour undo window. `project refresh` re-applies the installed closure and locked theme.

## See Also

- [`dashcn sync`](sync.md)
- [`dashcn init`](init.md)
- [`dashcn reset`](../diagnostics/reset.md)

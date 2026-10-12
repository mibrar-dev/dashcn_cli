# dashcn doctor

> Diagnose the manifest, closure, layout and lock drift.

## Usage

```bash
dashcn doctor [--json]
```

## Arguments

This command does not define positional arguments.

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn doctor
```

## Notes

Exit codes: 0 clean, 1 drift/modified, 2 broken closure, 3 manifest invalid.

## See Also

- [`dashcn validate`](validate.md)
- [`dashcn audit`](audit.md)
- [`dashcn update`](../components/update.md)

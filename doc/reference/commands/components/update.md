# dashcn update

> Update installed components from the registry.

## Usage

```bash
dashcn update [component...] [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `[component...]` | No | Components to update (default: all installed). |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Update every installed component. |
| `--check` |  | `false` | Report only; exit 1 when behind or modified. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn update
dashcn update button
dashcn update --check
```

## Notes

Hash-driven: files whose bytes still match dashcn.lock are overwritten with the manifest's current content, locally modified files are reported and left, and user-owned theme files are never touched.

## See Also

- [`dashcn add`](add.md)
- [`dashcn audit`](../diagnostics/audit.md)
- [`dashcn doctor`](../diagnostics/doctor.md)

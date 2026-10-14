# dashcn eject

> Turn a package-mode component into owned sources.

## Usage

```bash
dashcn eject <component> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component>` | Yes | Installed package-mode component to materialise. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--with-deps` |  | `false` | Also eject transitive component dependencies. |
| `--dry-run` |  | `false` | Print the plan without writing anything. |
| `--force` | `-f` | `false` | Overwrite locally modified registry files. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn eject button
dashcn eject button --dry-run
```

## Notes

Copies the component sources (plus unowned transitive entries) into the install dir, flips dashcn.lock to `mode: copy`, and rewrites the app imports: direct package imports are retargeted, and barrel uses gain an explicit owned import plus a `hide` on the barrel.

## See Also

- [`dashcn add`](add.md)
- [`dashcn remove`](remove.md)
- [`dashcn update`](update.md)

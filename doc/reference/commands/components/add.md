# dashcn add

> Install one or more components or blocks and their closure.

## Usage

```bash
dashcn add <component|block...> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<component|block...>` | Yes | Component or block names, or @namespace/component addresses. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--all` | `-a` | `false` | Install every available component. |
| `--blocks` |  | `false` | With --all, install every block too. |
| `--dry-run` |  | `false` | Print the plan without writing anything. |
| `--force` | `-f` | `false` | Overwrite locally modified registry files. |
| `--include-preview` |  | `false` | Also copy each component preview.dart. |
| `--package` |  | `false` | Depend on the dashcn package; copy no sources. |
| `--path <dir>` |  |  | With --package, use a path dependency on this directory. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn add button
dashcn add login-01
dashcn add input select tabs
dashcn add --all --blocks
dashcn add button --package
```

## Notes

Installs the transitive closure: requested components and blocks, their components/primitives deps, and the always-on foundation + theme core. A block lands in blocks/<id>/ together with the components it uses. User-owned <name>_theme.dart files are never overwritten. With --package the CLI runs `flutter pub add dashcn` instead and records `mode: package` in dashcn.lock.

## See Also

- [`dashcn remove`](remove.md)
- [`dashcn update`](update.md)
- [`dashcn list`](list.md)
- [`dashcn info`](info.md)
- [`dashcn dry-run`](dry-run.md)
- [`dashcn eject`](eject.md)

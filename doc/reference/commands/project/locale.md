# dashcn locale

> Install and manage component translations.

## Usage

```bash
dashcn locale <add <code>|list|remove <code>> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<add|list|remove>` | Yes | Locale action to run. |
| `[code]` | No | Locale code for `add`/`remove` (e.g. ar). |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn locale add ar
dashcn locale list
dashcn locale remove ar
```

## Notes

Class and parameter names stay English; only UI strings are translated. `dashcn add` refreshes dashcn_locales/ automatically (English base plus every installed locale, containing only the keys the installed components need); `locale add` installs a language for every installed component so later adds include it. Generated files are idempotent: re-running writes nothing.

## See Also

- [`dashcn add`](../components/add.md)
- [`dashcn remove`](../components/remove.md)
- [`dashcn sync`](sync.md)

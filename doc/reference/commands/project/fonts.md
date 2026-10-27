# dashcn fonts

> Install and manage font packs.

## Usage

```bash
dashcn fonts <add <id>|list> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<add|list>` | Yes | Font action to run. |
| `[id]` | No | Font pack id for `add` (e.g. geist-sans). |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--google` |  | `false` | Add the google_fonts dependency instead of copying font files. |
| `--json` |  | `false` | Output machine-readable JSON. |

## Examples

```bash
dashcn fonts add geist-sans
dashcn fonts add geist-sans --google
dashcn fonts list
```

## Notes

Apps use the platform font by default; Geist is never shipped in the package. `fonts add` copies the pack files into assets/fonts/ with the matching `flutter: fonts:` pubspec entries, while `--google` opts into the google_fonts package and copies nothing. `dashcn add` never installs a font. Generated files are idempotent: re-running writes nothing.

## See Also

- [`dashcn add`](../components/add.md)
- [`dashcn locale`](locale.md)
- [`dashcn sync`](sync.md)

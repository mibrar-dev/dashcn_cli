# dashcn theme

> List and apply registry theme presets.

## Usage

```bash
dashcn theme <list|apply <preset>|import|export> [flags]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `<list|apply|import|export>` | No | Theme action to run. |

## Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--refresh` |  | `false` | Overwrite app_theme.dart even when edited. |
| `--json` |  | `false` | Output machine-readable JSON. |
| `--name <id>` |  |  | Preset id for `theme import`. |
| `--apply` |  | `false` | Apply an import straight to app_theme.dart. |
| `--format <name>` |  | `css` | Export format: css|tailwind|dtcg|json|dart. |
| `--out <file>` |  |  | Write the export to a file instead of stdout. |

## Examples

```bash
dashcn theme list
dashcn theme apply vercel
dashcn theme import theme.css --name tweak --apply
dashcn theme export --format dtcg --out theme.tokens.json
```

## Notes

app_theme.dart is user-owned: without --refresh a locally modified file is reported as drift and left untouched. Import/export need no registry: a web theme (CSS, Tailwind v3 config, preset JSON) becomes <installRoot>/theme/<id>.json, and export renders the current theme back to the web.

## See Also

- [`dashcn init`](init.md)
- [`dashcn add`](../components/add.md)

# Config and State Reference

The v2 CLI keeps two project-local files:

- `.dashcn/config.json` — how to resolve the registry and where to install.
- `dashcn.lock` — lockfileVersion 2: what is installed and the hash of every file.

There is no `.dashcn/state.json` and no `.dashcn/components/` directory; `dashcn.lock` is the single install-state file.

## `.dashcn/config.json`

Written by `dashcn init` and updated by `theme`, `default` and registry commands.

Fields written by the v2 CLI:

- `defaultNamespace`: registry namespace used for unqualified addresses
- `installPath`: the install root (default `lib/ui/dashcn`)
- `themeId`: the selected theme preset id
- `registryMode`: `local` or `remote`
- `registryPath`: local registry root (local mode)
- `registryUrl`: registry URL (remote mode)
- `registries`: optional per-namespace registry configuration

Example:

```json
{
  "defaultNamespace": "dashcn",
  "installPath": "lib/ui/dashcn",
  "themeId": "vercel",
  "registryMode": "remote",
  "registryUrl": "https://raw.githubusercontent.com/…/dashcn/v0.2.7/dashcn/lib/src"
}
```

Missing files are treated as empty defaults. Invalid JSON is a command error and does not silently reset the project.

## `dashcn.lock`

`dashcn.lock` is written by `init`, `add`, `update`, `remove`, `theme apply` and `sync`. Shape:

```json
{
  "lockfileVersion": 2,
  "registry": {
    "name": "dashcn",
    "ref": "refactor/rearchitecture",
    "manifestSha256": "…",
    "generatedAt": "2026-10-09T00:00:00Z"
  },
  "installRoot": "lib/ui/dashcn",
  "theme": {
    "id": "vercel",
    "path": "lib/ui/dashcn/theme/app_theme.dart",
    "sha256": "…"
  },
  "layers": {
    "foundation": { "units": ["data", "gap"], "files": { "lib/ui/dashcn/foundation/data.dart": "…" } },
    "theme": { "units": ["color_tokens"], "files": { "…": "…" } },
    "primitives": { "units": ["clickable"], "files": { "…": "…" } }
  },
  "components": [
    {
      "id": "button",
      "files": { "lib/ui/dashcn/components/button/button.dart": "…" },
      "userOwned": { "lib/ui/dashcn/components/button/button_theme.dart": "…" },
      "deps": { "foundation": [], "theme": [], "primitives": [], "components": [] },
      "api": { "classes": ["Button"] }
    }
  ]
}
```

Rules:

- `files` maps a project-relative path to the sha256 of what the CLI wrote; `update` and `doctor` diff this against disk.
- `userOwned` records a `<name>_theme.dart` path and its install-time hash; `add`/`update` never rewrite it and `remove` never deletes it unless `--purge-user-themes`.
- `layers.*.units` lets `remove` drop a layer unit once no installed component's closure references it.
- `components[].api` lets the single-owner preflight run from the lock alone.
- `registry.manifestSha256` is the digest of `manifests/registry.json`; a mismatch means "the registry moved".

Commit `.dashcn/config.json` and `dashcn.lock` with your project.

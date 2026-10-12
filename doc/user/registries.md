# Registries

A registry publishes a manifest (`manifests/registry.json`, schemaVersion 2) plus the component, primitive, foundation and theme files it describes. The CLI resolves the registry remotely by default and can be pointed at a local checkout or an `http(s)` URL.

## Registry Source

Resolution order:

1. `--registry <path|url>` on the command line.
2. `DASHCN_REGISTRY_ROOT` / `DASHCN_REGISTRY_URL` environment variables.
3. `registryPath` / `registryUrl` in `.dashcn/config.json` (written by `init`).
4. The default remote registry (GitHub raw at the CLI version's ref).

```bash
dashcn --registry ../dashcn-kit/dashcn/lib/src add button
dashcn --registry https://example.com/registry validate
```

A remote registry is cached under `.dashcn/cache/registry`; `--offline` reads the cache and never touches the network.

## List Registries

```bash
dashcn registries
dashcn registries --json
```

## Set the Default Registry

```bash
dashcn default dashcn
dashcn default dashcn --local
dashcn default dashcn --remote
```

To see the current default:

```bash
dashcn default
```

## Component Addresses

Component commands accept an optional `@namespace/` prefix; the CLI strips it and resolves the component from the active registry.

```bash
dashcn add button
dashcn info button
dashcn search button
```

## Offline Mode

```bash
dashcn --offline list
```

Offline mode disables network calls and uses the cache. Use it only after the registry has been fetched once.

## Manifest Resolution

The manifest is the single source of truth for a component:

- `components/<id>` declares the component's files, user-owned files, deps and public API.
- `foundation`, `theme` and `primitives` declare the layer units.
- `fileHashes` records a sha256 for every copyable file.

`validate` checks the manifest against the v2 rules; `doctor` checks the installed project against the manifest and `dashcn.lock`.

## Init

`dashcn init [--dir <path>] [--theme <id>] [--yes]` copies the always-on foundation + theme core, writes `.dashcn/config.json` and `dashcn.lock`, and generates `<installRoot>/theme/app_theme.dart`. It never installs a component.

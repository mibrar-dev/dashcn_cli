# Registry Setup

The CLI stores project registry configuration in `.dashcn/config.json` and install state in `dashcn.lock` (lockfileVersion 2).

Typical setup:

```bash
dashcn init --yes
dashcn registries
dashcn default dashcn
```

Point the CLI at a local registry checkout or a hosted URL:

```bash
dashcn --registry ../dashcn-kit/dashcn/lib/src init --yes
dashcn --registry https://example.com/registry add button
```

The registry is resolved remotely by default (GitHub raw at the CLI version's ref) and cached under `.dashcn/cache/registry` for offline re-installs.

During component install, the registry manifest (`manifests/registry.json`, schemaVersion 2) is the single source of truth: it declares each component's files, user-owned files, dependency closure and public API, plus a sha256 for every copyable file. `validate` checks the manifest; `doctor` checks the installed project against it.

References:

- [Registries](../user/registries.md)
- [Config and state](../reference/config-state.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)

# Component Workflow

Use `init` once per project, then install components with `add`.

```bash
dashcn init --yes
dashcn add button
dashcn add button dialog input select calendar
```

The CLI installs only what each selected component declares: the component files, its transitive layer closure (primitives, foundation, theme) and any pub packages those need. Those writes are recorded in `dashcn.lock` so later `remove`, `update`, `audit` and `doctor` commands can reason from installed state.

Useful follow-up commands:

- `dashcn list` to browse components.
- `dashcn search button` to find matching components.
- `dashcn info button` to inspect one component's closure and API.
- `dashcn dry-run button` to preview writes.
- `dashcn update --check` to see whether the registry moved on.
- `dashcn remove button` to uninstall a component.

References:

- [User commands](../user/commands.md)
- [Components](../user/components.md)
- [Generated command reference](../reference/commands/index.md)
- [Developer docs](../developer/advanced-mode.md)

# Getting Started

Initialize a Flutter project, then add components from the registry.

```bash
dashcn init --yes
dashcn add button
```

An `@namespace/` prefix is accepted on component addresses and stripped:

```bash
dashcn add @dashcn/button
```

Keep the install up to date and inspect it:

```bash
dashcn update --check
dashcn doctor
dashcn theme list
```

Learn more:

- [Installation](installation.md)
- [User getting started](user/getting-started.md)
- [Component workflow](guides/component-workflow.md)
- [Generated command reference](reference/commands/index.md)
- [Developer docs](developer/advanced-mode.md)

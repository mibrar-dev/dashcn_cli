# Troubleshooting

Start with the public diagnostics commands:

```bash
dashcn doctor
dashcn validate
dashcn audit
dashcn update --check
```

For registry-specific issues, point the CLI at a registry explicitly:

```bash
dashcn --registry <path|url> validate
dashcn --registry <path|url> doctor
```

More help:

- [User troubleshooting](user/troubleshooting.md)
- [Diagnostics guide](guides/diagnostics.md)
- [Generated command reference](reference/commands/index.md)
- [Developer docs](developer/advanced-mode.md)

import 'package:dashcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Components command group (`add`, `remove`, `update`, ...).
const CliCommandGroupMeta componentsCommandGroup = CliCommandGroupMeta(
  title: 'Components',
  slug: 'components',
  sortOrder: 10,
  commands: [
    CliCommandMeta(
      id: 'add',
      description: 'Install one or more components, blocks or flows and '
          'their closure.',
      sortOrder: 10,
      usage: 'dashcn add <component|block|flow:flow...> [flags]',
      arguments: [
        CliArgumentMeta(
          '<component|block|flow:flow...>',
          true,
          'Component, block or flow:flow names, or @namespace/component '
              'addresses.',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--all',
          short: '-a',
          defaultValue: 'false',
          description: 'Install every available component.',
        ),
        CliFlagMeta(
          name: '--blocks',
          defaultValue: 'false',
          description: 'With --all, install every block too.',
        ),
        CliFlagMeta(
          name: '--dry-run',
          defaultValue: 'false',
          description: 'Print the plan without writing anything.',
        ),
        CliFlagMeta(
          name: '--force',
          short: '-f',
          defaultValue: 'false',
          description: 'Overwrite locally modified registry files.',
        ),
        CliFlagMeta(
          name: '--include-preview',
          defaultValue: 'false',
          description: 'Also copy each component preview.dart.',
        ),
        CliFlagMeta(
          name: '--package',
          defaultValue: 'false',
          description: 'Depend on the dashcn package; copy no sources.',
        ),
        CliFlagMeta(
          name: '--path <dir>',
          defaultValue: '',
          description: 'With --package, use a path dependency on this '
              'directory.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn add button',
        'dashcn add login-01',
        'dashcn add flow:auth-01',
        'dashcn add input select tabs',
        'dashcn add --all --blocks',
        'dashcn add button --package',
      ],
      notes:
          'Installs the transitive closure: requested components, blocks and flows, their components/primitives deps, and the always-on foundation + theme core. A block lands in blocks/<id>/ together with the components it uses; a flow lands in flows/<id>/ with its components/blocks closure. User-owned <name>_theme.dart files are never overwritten. With --package the CLI runs `flutter pub add dashcn` instead and records `mode: package` in dashcn.lock.',
      seeAlso: ['remove', 'update', 'list', 'info', 'dry-run', 'eject'],
    ),
    CliCommandMeta(
      id: 'eject',
      description: 'Turn a package-mode component into owned sources.',
      sortOrder: 15,
      usage: 'dashcn eject <component> [flags]',
      arguments: [
        CliArgumentMeta(
          '<component>',
          true,
          'Installed package-mode component to materialise.',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--with-deps',
          defaultValue: 'false',
          description: 'Also eject transitive component dependencies.',
        ),
        CliFlagMeta(
          name: '--dry-run',
          defaultValue: 'false',
          description: 'Print the plan without writing anything.',
        ),
        CliFlagMeta(
          name: '--force',
          short: '-f',
          defaultValue: 'false',
          description: 'Overwrite locally modified registry files.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn eject button',
        'dashcn eject button --dry-run',
      ],
      notes:
          'Copies the component sources (plus unowned transitive entries) into the install dir, flips dashcn.lock to `mode: copy`, and rewrites the app imports: direct package imports are retargeted, and barrel uses gain an explicit owned import plus a `hide` on the barrel.',
      seeAlso: ['add', 'remove', 'update'],
    ),
    CliCommandMeta(
      id: 'remove',
      description: 'Remove installed components, blocks, flows and orphaned '
          'layer files.',
      sortOrder: 20,
      aliases: ['rm'],
      usage: 'dashcn remove <component|block|flow:flow...> [flags]',
      arguments: [
        CliArgumentMeta(
          '<component|block|flow:flow...>',
          false,
          'Installed component, block or flow:flow names to remove.',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--all',
          short: '-a',
          defaultValue: 'false',
          description: 'Remove every installed component, block and flow.',
        ),
        CliFlagMeta(
          name: '--force',
          short: '-f',
          defaultValue: 'false',
          description: 'Remove even when dependents remain.',
        ),
        CliFlagMeta(
          name: '--purge-user-themes',
          defaultValue: 'false',
          description: 'Also delete <name>_theme.dart user files.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn remove button',
        'dashcn remove login-01',
        'dashcn rm dialog',
      ],
      notes:
          'Refuses while another installed component, block or flow still needs the target, unless --force. A block or flow owns no user-owned file, so removing one deletes every path it recorded.',
      seeAlso: ['add', 'list'],
    ),
    CliCommandMeta(
      id: 'update',
      description: 'Update installed components from the registry.',
      sortOrder: 30,
      usage: 'dashcn update [component...] [flags]',
      arguments: [
        CliArgumentMeta(
          '[component...]',
          false,
          'Components to update (default: all installed).',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--all',
          short: '-a',
          defaultValue: 'false',
          description: 'Update every installed component.',
        ),
        CliFlagMeta(
          name: '--check',
          defaultValue: 'false',
          description: 'Report only; exit 1 when behind or modified.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn update',
        'dashcn update button',
        'dashcn update --check',
      ],
      notes:
          'Hash-driven: files whose bytes still match dashcn.lock are overwritten with the manifest\'s current content, locally modified files are reported and left, and user-owned theme files are never touched.',
      seeAlso: ['add', 'audit', 'doctor'],
    ),
    CliCommandMeta(
      id: 'dry-run',
      description:
          'Preview what add would install (components, blocks, flows).',
      sortOrder: 40,
      usage: 'dashcn dry-run <component|block|flow:flow...> [flags]',
      arguments: [
        CliArgumentMeta(
          '<component|block|flow:flow...>',
          false,
          'Components, blocks or flows to preview.',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--all',
          short: '-a',
          defaultValue: 'false',
          description: 'Preview every component.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: ['dashcn dry-run button'],
      seeAlso: ['add'],
    ),
    CliCommandMeta(
      id: 'list',
      description: 'List available components, blocks or flows, by category.',
      sortOrder: 50,
      aliases: ['ls'],
      usage: 'dashcn list [--blocks] [--flows] [--category <name>] [--json]',
      flags: [
        CliFlagMeta(
          name: '--blocks',
          defaultValue: 'false',
          description: 'List the blocks layer instead of components.',
        ),
        CliFlagMeta(
          name: '--flows',
          defaultValue: 'false',
          description: 'List the flows layer instead of components.',
        ),
        CliFlagMeta(
          name: '--category <name>',
          defaultValue: 'false',
          description: 'Only entries of that category.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn list',
        'dashcn list --blocks',
        'dashcn list --flows',
        'dashcn list --category "Forms & Inputs"',
        'dashcn ls --json',
      ],
      notes:
          'Human output groups entries by the category each meta.json declares; the JSON envelope keeps `components`, `blocks` and `flows` so a consumer never has to probe for a key.',
      seeAlso: ['search', 'info', 'add'],
    ),
    CliCommandMeta(
      id: 'search',
      description:
          'Search components, blocks and flows by name, description or tag.',
      sortOrder: 60,
      usage: 'dashcn search <query> [--category <name>] [--json]',
      arguments: [CliArgumentMeta('<query>', true, 'Search text.')],
      flags: [
        CliFlagMeta(
          name: '--category <name>',
          defaultValue: 'false',
          description: 'Only entries of that category.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn search button',
        'dashcn search login --category Authentication',
      ],
      notes:
          'All kinds are searched at once, because `add <id>` resolves all. Each result carries its `kind`, `category` and, for a block or flow, its `viewport`.',
      seeAlso: ['list', 'info'],
    ),
    CliCommandMeta(
      id: 'info',
      description:
          'Show a component\'s, block\'s or flow\'s closure, files and api.',
      sortOrder: 70,
      aliases: ['i'],
      usage: 'dashcn info <component|block|flow:flow> [--json]',
      arguments: [
        CliArgumentMeta(
          '<component|block|flow:flow>',
          true,
          'Component, block or flow:flow name, or @namespace/component '
              'address.',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn info button',
        'dashcn info login-01',
        'dashcn info flow:auth-01',
        'dashcn i dialog',
      ],
      notes:
          'A component reports its api and user-owned theme files; a block reports its viewport, its own files and the components it assembles; a flow reports its screens, viewport and components/blocks closure.',
      seeAlso: ['list', 'search', 'add'],
    ),
  ],
);

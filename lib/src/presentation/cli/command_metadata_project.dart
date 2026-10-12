import 'package:dashcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Project command group (`init`, `registries`, `theme`, ...).
const CliCommandGroupMeta projectCommandGroup = CliCommandGroupMeta(
  title: 'Project',
  slug: 'project',
  sortOrder: 20,
  commands: [
    CliCommandMeta(
      id: 'init',
      description: 'Install the layer core and generate the app theme.',
      sortOrder: 10,
      usage: 'dashcn init [flags]',
      flags: [
        CliFlagMeta(
          name: '--dir <path>',
          description: 'Install root (default: lib/ui/dashcn).',
        ),
        CliFlagMeta(
          name: '--theme <id>',
          description: 'Theme preset id (default: neutral).',
        ),
        CliFlagMeta(
          name: '--mode <mode>',
          description: '`copy` (own the sources) or `package` (pub dep).',
        ),
        CliFlagMeta(
          name: '--yes',
          short: '-y',
          defaultValue: 'false',
          description: 'Non-interactive; use the default preset.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn init',
        'dashcn init --theme vercel --yes',
        'dashcn init --mode package',
      ],
      notes:
          'Copy mode copies every foundation and theme unit (no component), writes .dashcn/config.json and dashcn.lock v2, and generates <installRoot>/theme/app_theme.dart from the chosen preset. Package mode writes the config only; components then arrive via `dashcn add <id> --package`.',
      seeAlso: ['registries', 'default', 'theme', 'add'],
    ),
    CliCommandMeta(
      id: 'registries',
      description: 'List configured and discoverable registries.',
      sortOrder: 20,
      usage: 'dashcn registries [--json]',
      flags: [
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: ['dashcn registries'],
      seeAlso: ['default', 'init'],
    ),
    CliCommandMeta(
      id: 'default',
      description: 'Set or show the default registry namespace.',
      sortOrder: 30,
      usage: 'dashcn default [namespace] [--local | --remote]',
      arguments: [
        CliArgumentMeta('[namespace]', false, 'Namespace to set as default.'),
      ],
      examples: [
        'dashcn default',
        'dashcn default dashcn --remote',
      ],
      seeAlso: ['registries', 'init'],
    ),
    CliCommandMeta(
      id: 'sync',
      description: 'Re-apply the installed closure and locked theme.',
      sortOrder: 40,
      usage: 'dashcn sync',
      examples: ['dashcn sync'],
      seeAlso: ['init', 'audit', 'update'],
    ),
    CliCommandMeta(
      id: 'project',
      description: 'Project repair and cleanup commands.',
      sortOrder: 50,
      usage: 'dashcn project <reset|refresh> [flags]',
      arguments: [
        CliArgumentMeta(
          '<reset|refresh>',
          true,
          'Project-scoped maintenance command to run.',
        ),
      ],
      examples: [
        'dashcn project reset',
        'dashcn project reset --undo',
        'dashcn project refresh',
      ],
      notes:
          '`project reset` removes CLI-managed files with a 24-hour undo window. `project refresh` re-applies the installed closure and locked theme.',
      seeAlso: ['sync', 'init', 'reset'],
    ),
    CliCommandMeta(
      id: 'theme',
      description: 'List and apply registry theme presets.',
      sortOrder: 60,
      usage: 'dashcn theme <list|apply <preset>|import|export> [flags]',
      arguments: [
        CliArgumentMeta(
            '<list|apply|import|export>', false, 'Theme action to run.'),
      ],
      flags: [
        CliFlagMeta(
          name: '--refresh',
          defaultValue: 'false',
          description: 'Overwrite app_theme.dart even when edited.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
        CliFlagMeta(
          name: '--name <id>',
          defaultValue: '',
          description: 'Preset id for `theme import`.',
        ),
        CliFlagMeta(
          name: '--apply',
          defaultValue: 'false',
          description: 'Apply an import straight to app_theme.dart.',
        ),
        CliFlagMeta(
          name: '--format <name>',
          defaultValue: 'css',
          description: 'Export format: css|tailwind|dtcg|json|dart.',
        ),
        CliFlagMeta(
          name: '--out <file>',
          defaultValue: '',
          description: 'Write the export to a file instead of stdout.',
        ),
      ],
      examples: [
        'dashcn theme list',
        'dashcn theme apply vercel',
        'dashcn theme import theme.css --name tweak --apply',
        'dashcn theme export --format dtcg --out theme.tokens.json',
      ],
      notes:
          'app_theme.dart is user-owned: without --refresh a locally modified file is reported as drift and left untouched. '
          'Import/export need no registry: a web theme (CSS, Tailwind v3 config, preset JSON) becomes '
          '<installRoot>/theme/<id>.json, and export renders the current theme back to the web.',
      seeAlso: ['init', 'add'],
    ),
  ],
);

import 'package:dashcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Project command group (`init`, `registries`, `theme`, ...).
const CliCommandGroupMeta projectCommandGroup = CliCommandGroupMeta(
  title: 'Project',
  slug: 'project',
  sortOrder: 20,
  commands: [
    CliCommandMeta(
      id: 'create',
      description: 'Scaffold a runnable app from a starter.',
      sortOrder: 5,
      usage: 'dashcn create <starter> <name> [flags]',
      arguments: [
        CliArgumentMeta('<starter>', true, 'Starter id: saas, chat, shop.'),
        CliArgumentMeta('<name>', true, 'App directory to create.'),
      ],
      flags: [
        CliFlagMeta(
          name: '--theme <preset|file.css>',
          description: 'Theme preset or CSS file to import.',
        ),
        CliFlagMeta(
          name: '--mode <mode>',
          description: '`copy` (own the sources) or `package` (pub dep).',
        ),
        CliFlagMeta(
          name: '--platforms <list>',
          description: 'Comma list of platforms.',
        ),
        CliFlagMeta(
          name: '--org <id>',
          description: 'Org for flutter create (default: com.example).',
        ),
        CliFlagMeta(
          name: '--force',
          short: '-f',
          defaultValue: 'false',
          description: 'Overwrite a non-empty target dir.',
        ),
        CliFlagMeta(
          name: '--dry-run',
          defaultValue: 'false',
          description: 'Print the plan without writing anything.',
        ),
        CliFlagMeta(
          name: '--list',
          defaultValue: 'false',
          description: 'List available starters.',
        ),
      ],
      examples: [
        'dashcn create saas my_app',
        'dashcn create chat my_app --theme vercel --mode package',
        'dashcn create --list',
      ],
      notes:
          'Runs flutter create --empty, then package mode adds the dashcn pub dependency while copy mode owns the sources under lib/ui/dashcn/ via the installer. Templates render with simple {{var}} substitution and the result is dart formatted.',
      seeAlso: ['init', 'add', 'theme'],
    ),
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
      id: 'locale',
      description: 'Install and manage component translations.',
      sortOrder: 45,
      usage: 'dashcn locale <add <code>|list|remove <code>> [flags]',
      arguments: [
        CliArgumentMeta(
          '<add|list|remove>',
          true,
          'Locale action to run.',
        ),
        CliArgumentMeta(
          '[code]',
          false,
          'Locale code for `add`/`remove` (e.g. ar).',
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
        'dashcn locale add ar',
        'dashcn locale list',
        'dashcn locale remove ar',
      ],
      notes:
          'Class and parameter names stay English; only UI strings are translated. '
          '`dashcn add` refreshes dashcn_locales/ automatically (English base plus '
          'every installed locale, containing only the keys the installed components need); '
          '`locale add` installs a language for every installed component so later adds '
          'include it. Generated files are idempotent: re-running writes nothing.',
      seeAlso: ['add', 'remove', 'sync'],
    ),
    CliCommandMeta(
      id: 'fonts',
      description: 'Install and manage font packs.',
      sortOrder: 47,
      usage: 'dashcn fonts <add <id>|list> [flags]',
      arguments: [
        CliArgumentMeta(
          '<add|list>',
          true,
          'Font action to run.',
        ),
        CliArgumentMeta(
          '[id]',
          false,
          'Font pack id for `add` (e.g. geist-sans).',
        ),
      ],
      flags: [
        CliFlagMeta(
          name: '--google',
          defaultValue: 'false',
          description: 'Add the google_fonts dependency instead of copying '
              'font files.',
        ),
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: [
        'dashcn fonts add geist-sans',
        'dashcn fonts add geist-sans --google',
        'dashcn fonts list',
      ],
      notes: 'Apps use the platform font by default; Geist is never shipped in '
          'the package. `fonts add` copies the pack files into assets/fonts/ '
          'with the matching `flutter: fonts:` pubspec entries, while '
          '`--google` opts into the google_fonts package and copies nothing. '
          '`dashcn add` never installs a font. '
          'Generated files are idempotent: re-running writes nothing.',
      seeAlso: ['add', 'locale', 'sync'],
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

import 'package:dashcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Tooling command group (`feedback`, `version`, `upgrade`).
const CliCommandGroupMeta toolingCommandGroup = CliCommandGroupMeta(
  title: 'Tooling',
  slug: 'tooling',
  sortOrder: 40,
  commands: [
    CliCommandMeta(
      id: 'feedback',
      description: 'Submit feedback or report issues.',
      sortOrder: 10,
      usage: 'dashcn feedback [flags]',
      flags: [
        CliFlagMeta(
          name: '--type <type>',
          short: '-t',
          description: 'Feedback type: bug, feature, docs, question, other.',
        ),
        CliFlagMeta(name: '--title <title>', description: 'Issue title.'),
        CliFlagMeta(name: '--body <body>', description: 'Issue body.'),
      ],
      examples: ['dashcn feedback'],
      seeAlso: ['doctor', 'version'],
    ),
    CliCommandMeta(
      id: 'version',
      description: 'Show the CLI version.',
      sortOrder: 20,
      usage: 'dashcn version [--check]',
      flags: [
        CliFlagMeta(
          name: '--check',
          defaultValue: 'false',
          description: 'Check for updates.',
        ),
      ],
      examples: ['dashcn version --check'],
      seeAlso: ['upgrade'],
    ),
    CliCommandMeta(
      id: 'upgrade',
      description: 'Upgrade the CLI to the latest version.',
      sortOrder: 30,
      usage: 'dashcn upgrade [--force]',
      flags: [
        CliFlagMeta(
          name: '--force',
          short: '-f',
          defaultValue: 'false',
          description: 'Force upgrade even if already latest.',
        ),
      ],
      examples: ['dashcn upgrade'],
      seeAlso: ['version'],
    ),
  ],
);

/// The Advanced command group (`docs`, behind `--advanced`).
const CliCommandGroupMeta advancedCommandGroup = CliCommandGroupMeta(
  title: 'Advanced',
  slug: 'advanced',
  sortOrder: 50,
  commands: [
    CliCommandMeta(
      id: 'docs',
      description: 'Regenerate command reference documentation.',
      sortOrder: 10,
      advanced: true,
      usage: 'dashcn --advanced docs [--generate]',
      flags: [
        CliFlagMeta(
          name: '--generate',
          short: '-g',
          defaultValue: 'false',
          description: 'Regenerate doc/reference/commands.',
        ),
      ],
      examples: ['dashcn --advanced docs --generate'],
      notes: 'This command requires --advanced.',
    ),
  ],
);

import 'package:dashcn_cli/src/presentation/cli/command_metadata_models.dart';

/// The Diagnostics command group (`reset`, `doctor`, `validate`, `audit`).
const CliCommandGroupMeta diagnosticsCommandGroup = CliCommandGroupMeta(
  title: 'Diagnostics',
  slug: 'diagnostics',
  sortOrder: 30,
  commands: [
    CliCommandMeta(
      id: 'reset',
      description: 'Clear global CLI-managed cache and home-directory state.',
      sortOrder: 5,
      usage: 'dashcn reset',
      examples: ['dashcn reset'],
      seeAlso: ['project', 'doctor'],
    ),
    CliCommandMeta(
      id: 'doctor',
      description: 'Diagnose the manifest, closure, layout and lock drift.',
      sortOrder: 10,
      usage: 'dashcn doctor [--json]',
      flags: [
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: ['dashcn doctor'],
      notes:
          'Exit codes: 0 clean, 1 drift/modified, 2 broken closure, 3 manifest invalid.',
      seeAlso: ['validate', 'audit', 'update'],
    ),
    CliCommandMeta(
      id: 'validate',
      description: 'Validate the registry manifest against the v2 schema.',
      sortOrder: 20,
      usage: 'dashcn validate [--json]',
      flags: [
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: ['dashcn validate'],
      seeAlso: ['doctor', 'audit'],
    ),
    CliCommandMeta(
      id: 'audit',
      description: 'Compare installed files against dashcn.lock.',
      sortOrder: 30,
      usage: 'dashcn audit [--json]',
      flags: [
        CliFlagMeta(
          name: '--json',
          defaultValue: 'false',
          description: 'Output machine-readable JSON.',
        ),
      ],
      examples: ['dashcn audit'],
      seeAlso: ['doctor', 'update'],
    ),
  ],
);

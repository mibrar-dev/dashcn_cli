import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/application/services/package_mode/package_add_service.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';

/// `dashcn add` with component, block and flow ids
/// `[--dry-run] [--json] [--force] [--all] [--blocks] [--include-preview]
/// [--package [--path <dir>]]` (P5_CLI_PLAN.md §2.2, P6-B2, P9-3b).
///
/// Copy mode resolves the transitive closure of every requested id — a
/// component, a block or a `flow:<id>` — applies the single-owner preflight,
/// copies the files verbatim and refreshes `dashcn.lock` v2. A block lands in
/// `blocks/<id>/` together with every component, primitive, theme and
/// foundation unit it needs; a flow lands in `flows/<id>/` with its
/// components/blocks closure.
/// User-owned `<name>_theme.dart` files are never overwritten.
///
/// Package mode (`--package`) adds the `dashcn` pub dependency instead of
/// copying sources and records each component in `dashcn.lock` as
/// `mode: package` (flows resolve to their per-flow library import).
Future<int> runAddCommand({
  required ArgResults addCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(addCommand, 'json');
  final dryRun = commandFlag(addCommand, 'dry-run');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(addCommand, 'help')) {
    _printAddHelp();
    return ExitCodes.success;
  }

  final includeAll = commandFlag(addCommand, 'all');
  final includeBlocks = commandFlag(addCommand, 'blocks');
  final force = commandFlag(addCommand, 'force');
  final includePreview = commandFlag(addCommand, 'include-preview');
  final packageMode = commandFlag(addCommand, 'package');
  final packagePath = commandOption(addCommand, 'path');
  final requested = componentIdsFrom(addCommand);
  if (!includeAll && requested.isEmpty) {
    _printAddHelp();
    return ExitCodes.usage;
  }
  if (includeBlocks && !includeAll) {
    logger.warn('--blocks only widens --all; it does nothing on its own.');
  }
  if (packagePath != null && packagePath.trim().isNotEmpty && !packageMode) {
    logger.warn('--path only applies with --package; it is ignored.');
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final manifest = context.loadedManifest.manifest;
    final ids =
        includeAll ? (manifest.components.keys.toList()..sort()) : requested;
    final (componentIds, flowIds) = _splitFlows(ids);

    if (packageMode) {
      if (includeBlocks) {
        logger.errorToStderr(
          'Error: --blocks cannot be combined with --package.',
        );
        return ExitCodes.usage;
      }
      final service = PackageAddService(
        manifest: manifest,
        projectRoot: projectRoot,
        installRoot: context.installRoot,
        logger: logger,
      );
      final path =
          packagePath?.trim().isNotEmpty == true ? packagePath!.trim() : null;
      final report = await service.add(
        componentIds,
        flowIds: flowIds,
        path: path,
        dryRun: dryRun,
      );
      if (json) {
        printJson(jsonEnvelope(
          command: 'add',
          data: report.toJson(),
          meta: {'exitCode': ExitCodes.success},
        ));
      } else if (dryRun) {
        logger.info('Would run: flutter ${report.pubArgs.join(' ')}');
        for (final id in report.requested) {
          logger.info("  $id -> import '${report.imports[id]}';");
        }
      } else {
        logger.success(
          'Added ${report.requested.length} component(s) from the '
          'dashcn package.',
        );
        for (final id in report.requested) {
          logger.info("  $id -> import '${report.imports[id]}';");
        }
      }
      return ExitCodes.success;
    }

    final report = await context.installer.add(
      componentIds,
      blockIds: includeAll && includeBlocks ? manifest.blocks.keys : const [],
      flowIds: flowIds,
      dryRun: dryRun,
      includePreview: includePreview,
      overwrite: force,
      includeCore: true,
      includeAllPrimitives: includeAll,
    );

    if (json) {
      printJson(jsonEnvelope(
        command: 'add',
        data: report.toJson(),
        meta: {'exitCode': ExitCodes.success},
      ));
    } else if (!report.applied) {
      report.plan.writeHuman(logger);
    } else {
      report.writeHuman(logger);
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

/// Splits `flow:<id>` addresses from component/block ids.
(List<String>, List<String>) _splitFlows(List<String> ids) {
  final components = <String>[];
  final flows = <String>[];
  for (final id in ids) {
    if (isFlowAddress(id)) {
      flows.add(stripFlowPrefix(id));
    } else {
      components.add(id);
    }
  }
  return (components, flows);
}

void _printAddHelp() {
  stdout.writeln('Usage: dashcn add <component|block|flow:flow...> [flags]');
  stdout.writeln('       dashcn add --all [--blocks] [flags]');
  stdout.writeln('');
  stdout.writeln('Installs the transitive closure of every requested id:');
  stdout.writeln('components, blocks, flows, primitives, and the always-on '
      'foundation/theme core.');
  stdout.writeln('A block installs to blocks/<id>/ with the components it '
      'uses.');
  stdout.writeln('A flow installs to flows/<id>/ with the components and '
      'blocks it uses (dashcn add flow:<id>).');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout
      .writeln('  --all               Install every component in the registry');
  stdout.writeln('  --blocks            With --all, install every block too');
  stdout
      .writeln('  --dry-run           Print the plan without writing anything');
  stdout.writeln(
      '  --force             Overwrite locally modified registry files');
  stdout.writeln('  --include-preview   Also copy each component preview.dart');
  stdout.writeln(
      '  --package           Depend on the dashcn package, copy no sources');
  stdout.writeln(
      '  --path <dir>        With --package, use a path dependency instead');
  stdout.writeln('  --json              Machine-readable output on stdout');
  stdout.writeln('  --help, -h          Show this message');
}

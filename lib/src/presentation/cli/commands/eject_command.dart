import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/eject/eject_service.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';

/// `dashcn eject <component> [--with-deps] [--dry-run] [--force] [--json]`.
///
/// Turns a `mode: package` component into owned sources: copies its files
/// (plus unowned transitive entries, or every transitive component with
/// `--with-deps`) into the install dir, flips the lock to `mode: copy`, and
/// rewrites the app's `package:dashcn/...` imports. Refuses on locally
/// modified files unless `--force`.
Future<int> runEjectCommand({
  required ArgResults ejectCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(ejectCommand, 'json');
  final dryRun = commandFlag(ejectCommand, 'dry-run');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(ejectCommand, 'help')) {
    _printEjectHelp();
    return ExitCodes.success;
  }

  final requested = componentIdsFrom(ejectCommand);
  if (requested.isEmpty) {
    _printEjectHelp();
    return ExitCodes.usage;
  }
  if (requested.length > 1) {
    logger.errorToStderr('Error: eject takes a single component id.');
    return ExitCodes.usage;
  }
  final withDeps = commandFlag(ejectCommand, 'with-deps');
  final force = commandFlag(ejectCommand, 'force');

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final service = EjectService(
      manifest: context.loadedManifest.manifest,
      projectRoot: projectRoot,
      reader: RegistrySourceFileReader(context.source),
      installRoot: context.installRoot,
      manifestSha256: context.loadedManifest.sha256,
      logger: logger,
    );
    final report = await service.eject(
      requested.single,
      withDeps: withDeps,
      dryRun: dryRun,
      force: force,
    );
    if (report.applied && !dryRun) {
      // Ejected sources read translations through the installed tree.
      await refreshProjectLocales(
        source: context.source,
        manifest: context.loadedManifest.manifest,
        projectRoot: projectRoot,
        installRoot: context.installRoot,
        logger: logger,
        recordComponents: {report.id},
      );
    }
    if (json) {
      printJson(jsonEnvelope(
        command: 'eject',
        data: report.toJson(),
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }
    if (!report.applied) {
      logger.header('Eject plan for ${report.id} (no changes made)');
      for (final file in report.files) {
        logger.info('  copy $file');
      }
      report.rewrites.forEach((file, notes) {
        for (final note in notes) {
          logger.info('  $file: $note');
        }
      });
      return ExitCodes.success;
    }
    logger.success('Ejected ${report.id} to owned sources.');
    for (final file in report.files) {
      logger.info('  copied $file');
    }
    report.rewrites.forEach((file, notes) {
      for (final note in notes) {
        logger.info('  $file: $note');
      }
    });
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

void _printEjectHelp() {
  stdout.writeln('Usage: dashcn eject <component> [flags]');
  stdout.writeln('');
  stdout.writeln('Turns a mode: package component into owned sources in the');
  stdout.writeln('install dir and rewrites the app imports to match.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
      '  --with-deps         Also eject transitive component dependencies');
  stdout
      .writeln('  --dry-run           Print the plan without writing anything');
  stdout.writeln(
      '  --force             Overwrite locally modified registry files');
  stdout.writeln('  --json              Machine-readable output on stdout');
  stdout.writeln('  --help, -h          Show this message');
}

import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/installer/pub_package_resolver.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/application/services/update/update_service.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';

/// `dashcn update [ids…] [--all] [--check] [--json]`
/// (P5_CLI_PLAN.md §2.3, new in v2).
///
/// Hash-driven: overwrite files whose disk bytes still match the lock, report
/// locally modified files and leave them, and never read or write user-owned
/// `<name>_theme.dart` files.
Future<int> runUpdateCommand({
  required ArgResults updateCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(updateCommand, 'json');
  final check = commandFlag(updateCommand, 'check');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(updateCommand, 'help')) {
    _printUpdateHelp();
    return ExitCodes.success;
  }

  final includeAll = commandFlag(updateCommand, 'all');
  final ids = componentIdsFrom(updateCommand);
  if (!includeAll && ids.isNotEmpty == false) {
    // No ids and no --all: update every installed component.
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    Set<String>? componentFilter;
    Set<String>? blockFilter;
    Set<String>? flowFilter;
    if (!includeAll) {
      // `update <id>` accepts component, block and `flow:<id>` ids: each
      // filter keeps the ids of its own kind, so `update login-01` refreshes
      // the block while `update button` touches no block at all.
      final lock = await LockRepository(projectRoot).load();
      final installedComponents = lock.componentIds.toSet();
      final installedBlocks = lock.blockIds.toSet();
      final installedFlows = lock.flowIds.toSet();
      final stripped = [
        for (final id in ids) _stripFlowPrefix(id),
      ];
      componentFilter = ids.isEmpty
          ? installedComponents
          : stripped.where(installedComponents.contains).toSet();
      blockFilter = ids.isEmpty
          ? installedBlocks
          : stripped.where(installedBlocks.contains).toSet();
      flowFilter = ids.isEmpty
          ? installedFlows
          : stripped.where(installedFlows.contains).toSet();
    }

    final service = UpdateService(
      manifest: context.loadedManifest.manifest,
      reader: RegistrySourceFileReader(context.source),
      projectRoot: projectRoot,
      installRoot: context.installRoot,
      manifestSha256: context.loadedManifest.sha256,
      pubRunner: const ProcessPubCommandRunner(),
      logger: logger,
      themeRegenerator: (presetId) =>
          context.themeService.apply(presetId, refresh: true),
    );
    final report = await service.run(
      componentIds: componentFilter,
      blockIds: blockFilter,
      flowIds: flowFilter,
      check: check,
    );
    if (!check) {
      // A registry upgrade can add keys to a component: re-sync the
      // translations the installed components need.
      final lock = await LockRepository(projectRoot).load();
      await refreshProjectLocales(
        source: context.source,
        manifest: context.loadedManifest.manifest,
        projectRoot: projectRoot,
        installRoot: context.installRoot,
        logger: logger,
        recordComponents: lock.componentIds.toSet(),
      );
    }

    if (json) {
      final exitCode = check && report.needsAttention ? 1 : ExitCodes.success;
      printJson(jsonEnvelope(
        command: 'update',
        data: report.toJson(),
        meta: {'exitCode': exitCode},
      ));
      return exitCode;
    }
    report.writeHuman(logger);
    if (check && report.needsAttention) {
      return 1;
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

String _stripFlowPrefix(String id) {
  final trimmed = id.trim();
  if (trimmed.toLowerCase().startsWith('flow:')) {
    return trimmed.substring('flow:'.length).trim();
  }
  return trimmed;
}

void _printUpdateHelp() {
  stdout.writeln('Usage: dashcn update [component...] [flags]');
  stdout.writeln('       dashcn update --all [flags]');
  stdout.writeln('');
  stdout.writeln(
      'Updates installed components to the registry\'s current files.');
  stdout
      .writeln('Files you edited are reported and left untouched; user-owned');
  stdout.writeln('<name>_theme.dart files are never rewritten.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --all     Update every installed component');
  stdout.writeln(
      '  --check   Report only; exit 1 when anything is behind or modified');
  stdout.writeln('  --json    Machine-readable output on stdout');
}

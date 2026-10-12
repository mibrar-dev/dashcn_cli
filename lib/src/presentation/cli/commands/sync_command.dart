import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';

/// `dashcn sync`: re-materialise the installed closure from the current
/// manifest and refresh `theme/app_theme.dart` from the locked preset
/// (P5_CLI_PLAN.md §2, layer-aware).
Future<int> runSyncCommand({
  required ArgResults command,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(command, 'json');
  final logger = commandLogger(rootArgs, json: json);
  if (commandFlag(command, 'help')) {
    stdout.writeln('Usage: dashcn sync');
    stdout.writeln('');
    stdout.writeln('Re-applies the installed closure and the locked theme.');
    return ExitCodes.success;
  }
  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final lock = await LockRepository(projectRoot).load();
    final report = await context.installer.add(
      lock.componentIds,
      blockIds: lock.blockIds,
      includeCore: true,
    );
    final themeId = lock.theme?.id;
    if (themeId != null && themeId.isNotEmpty) {
      await context.themeService.apply(themeId, refresh: true);
    }
    if (!json) {
      report.writeHuman(logger);
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

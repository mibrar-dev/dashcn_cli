import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_preset_prompt.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';
import 'package:path/path.dart' as p;

/// Preset used by `init --yes` (plan §9.2): neutral black/white, closest to
/// dashcn's default.
const String kDefaultThemePreset = 'neutral';

/// Default install root (plan §2.1).
const String kDefaultInstallRoot = 'lib/ui/dashcn';

/// `dashcn init [--dir <path>] [--theme <id>] [--mode package|copy] [--yes]
/// [--json]` (P5_CLI_PLAN.md §2.1).
///
/// Copy mode installs the always-on foundation + theme core, writes
/// `.dashcn/config.json` and generates `<installRoot>/theme/app_theme.dart`
/// from the chosen preset. Package mode writes the config only (no sources);
/// components then arrive via `dashcn add <id> --package`. It never installs
/// a component.
Future<int> runInitCommand({
  required ArgResults initCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(initCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(initCommand, 'help')) {
    _printInitHelp();
    return ExitCodes.success;
  }

  final assumeYes = commandFlag(initCommand, 'yes');
  final targetDir = commandOption(initCommand, 'dir') ?? kDefaultInstallRoot;
  final requestedTheme = commandOption(initCommand, 'theme');
  final requestedMode = commandOption(initCommand, 'mode');
  final mode = _chooseMode(
    requested: requestedMode,
    assumeYes: assumeYes,
    json: json,
    logger: logger,
  );
  if (mode == null) {
    logger.errorToStderr(
      'Error: --mode must be `package` or `copy` (got `$requestedMode`).',
    );
    return ExitCodes.usage;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      installRootOverride: targetDir,
      offline: offline,
    );

    if (mode == DashcnConfig.installModePackage) {
      final exit = await _runPackageInit(
        context: context,
        targetDir: targetDir,
        json: json,
        logger: logger,
      );
      return exit;
    }

    final coreReport = await context.installer.installCore();
    final themeId = await _chooseTheme(
      context: context,
      requested: requestedTheme,
      assumeYes: assumeYes,
      json: json,
    );
    await _writeConfig(context, themeId, mode);
    final themeResult = await context.themeService.apply(themeId);

    if (json) {
      printJson(jsonEnvelope(
        command: 'init',
        data: {
          'installRoot': context.installRoot,
          'installMode': mode,
          'theme': themeResult.toJson(),
          'core': coreReport.toJson(),
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }

    logger.header('Initialized dashcn');
    logger.info('  install root: ${context.installRoot}');
    logger.info('  theme:        ${themeResult.presetName} '
        '(${themeResult.path})');
    if (coreReport.packagesAdded.isNotEmpty) {
      logger.info('  packages:     ${coreReport.packagesAdded.join(', ')}');
    }
    logger.info('');
    logger.info('Next: dashcn add button');
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

/// Package-mode init: config + empty lock, no sources, no theme generation.
Future<int> _runPackageInit({
  required CommandContext context,
  required String targetDir,
  required bool json,
  required CliLogger logger,
}) async {
  await _writeConfig(
    context,
    null,
    DashcnConfig.installModePackage,
  );
  await LockRepository(context.projectRoot).save(
    DashcnLock(installRoot: targetDir),
  );
  if (json) {
    printJson(jsonEnvelope(
      command: 'init',
      data: {
        'installRoot': targetDir,
        'installMode': DashcnConfig.installModePackage,
      },
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }
  logger.header('Initialized dashcn (package mode)');
  logger.info('  config: ${p.join('.dashcn', 'config.json')}');
  logger.info('');
  logger.info('Next: dashcn add button --package');
  return ExitCodes.success;
}

/// Returns `package`/`copy`, or `null` for an invalid explicit `--mode`.
String? _chooseMode({
  required String? requested,
  required bool assumeYes,
  required bool json,
  required CliLogger logger,
}) {
  final trimmed = requested?.trim().toLowerCase();
  if (trimmed != null && trimmed.isNotEmpty) {
    if (trimmed == DashcnConfig.installModePackage) {
      return DashcnConfig.installModePackage;
    }
    if (trimmed == DashcnConfig.installModeCopy) {
      return DashcnConfig.installModeCopy;
    }
    return null;
  }
  if (assumeYes || json || !stdin.hasTerminal) {
    return DashcnConfig.installModeCopy;
  }
  if (Platform.environment['CI'] == 'true') {
    return DashcnConfig.installModeCopy;
  }
  logger.info('Package or own the code?');
  logger.info('  [1] copy    - sources live in your app (default)');
  logger.info('  [2] package - depend on the dashcn package from pub');
  stdout.write('Choice [1/2] (copy): ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  if (answer == '2' || answer == 'package' || answer == 'p') {
    return DashcnConfig.installModePackage;
  }
  return DashcnConfig.installModeCopy;
}

Future<String> _chooseTheme({
  required CommandContext context,
  required String? requested,
  required bool assumeYes,
  required bool json,
}) async {
  final trimmed = requested?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed;
  }
  if (assumeYes || json || !stdin.hasTerminal) {
    return kDefaultThemePreset;
  }
  final presets = await context.themeService.listPresets();
  context.logger.info('Select a theme preset (press Enter for '
      '$kDefaultThemePreset):');
  final chosen = await promptForThemePreset(
    presets,
    question: 'Theme number: ',
    write: context.logger.info,
  );
  return chosen?.id ?? kDefaultThemePreset;
}

Future<void> _writeConfig(
  CommandContext context,
  String? themeId,
  String mode,
) {
  final source = context.source;
  final updated = context.config.copyWith(
    installPath: context.installRoot,
    themeId: themeId,
    installMode: mode,
    defaultNamespace: context.config.effectiveDefaultNamespace,
    registryPath: source is LocalRegistrySource ? source.localRoot : null,
    registryUrl: source is RemoteRegistrySource ? source.baseUrl : null,
  );
  return DashcnConfig.save(context.projectRoot, updated);
}

void _printInitHelp() {
  stdout.writeln('Usage: dashcn init [flags]');
  stdout.writeln('');
  stdout
      .writeln('Installs the always-on foundation + theme core and generates');
  stdout.writeln('<installRoot>/theme/app_theme.dart from a theme preset.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
      '  --dir <path>     Install root (default: $kDefaultInstallRoot)');
  stdout.writeln(
      '  --theme <id>     Theme preset id (default: $kDefaultThemePreset)');
  stdout.writeln(
      '  --mode <mode>    `copy` (own the sources) or `package` (pub dep)');
  stdout.writeln('  --yes, -y        Non-interactive; use the default preset');
  stdout.writeln('  --json           Machine-readable output on stdout');
  stdout.writeln('  --help, -h       Show this message');
}

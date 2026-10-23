import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/eject/eject_service.dart';
import 'package:dashcn_cli/src/application/services/installer/installer.dart';
import 'package:dashcn_cli/src/application/services/locale/locale_sync_service.dart';
import 'package:dashcn_cli/src/application/services/locale/locale_tables.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/application/services/package_mode/package_add_service.dart';
import 'package:dashcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_models.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';

/// A command reads its flags through these helpers so the parser stays the
/// single source of truth and unknown flags degrade to `false`/`null`.
bool commandFlag(ArgResults args, String name) =>
    optionalBoolOption(args, name);

String? commandOption(ArgResults args, String name) =>
    optionalStringOption(args, name);

/// Builds a logger that keeps STDOUT parseable when `--json` is active: all
/// human lines go to STDERR, warnings/errors to STDERR as well.
CliLogger commandLogger(ArgResults rootArgs, {required bool json}) {
  return CliLogger(
    verbose: commandFlag(rootArgs, 'verbose'),
    useColor: !json,
    writeLine: json ? stderr.writeln : stdout.writeln,
    writeStderrLine: stderr.writeln,
  );
}

/// The global `--registry <path|url>` override, when present.
String? registryOverrideFrom(ArgResults rootArgs) =>
    commandOption(rootArgs, 'registry');

/// Strips a `@namespace/` prefix from a component address; bare ids and
/// malformed refs pass through unchanged.
String bareComponentId(String token) {
  final trimmed = token.trim();
  if (trimmed.startsWith('@') && trimmed.contains('/')) {
    return trimmed.substring(trimmed.indexOf('/') + 1).trim();
  }
  return trimmed;
}

/// Component ids from a command's positional arguments.
List<String> componentIdsFrom(ArgResults command) {
  return [
    for (final token in command.rest)
      if (bareComponentId(token).isNotEmpty) bareComponentId(token),
  ];
}

/// Refreshes `dashcn_locales/` after a copy-mode mutation (add, remove, sync,
/// update, eject, project refresh).
///
/// No-op when the registry has no locale support (older registries keep the
/// historical full copy and no locale files). A missing `locale_tables.json`
/// only warns: translations stay uninstalled but the component install itself
/// succeeds. [recordComponents] are added to the locale state,
/// [forgetComponents] are dropped from it (ids that left the project).
Future<void> refreshProjectLocales({
  required RegistrySource source,
  required RegistryManifest manifest,
  required String projectRoot,
  required String installRoot,
  required CliLogger logger,
  Set<String> recordComponents = const {},
  Set<String> forgetComponents = const {},
}) async {
  final service = LocaleSyncService(
    source: source,
    manifest: manifest,
    projectRoot: projectRoot,
    installRoot: installRoot,
  );
  if (!service.isSupported) {
    return;
  }
  LocaleSyncReport? report;
  try {
    report = await service.refreshAfterInstall(
      components: recordComponents,
      forgetComponents: forgetComponents,
    );
  } on LocaleTablesMissingException catch (error) {
    logger.warn('Locales skipped: ${error.message}');
    return;
  }
  if (report == null || report.written.isEmpty) {
    return;
  }
  logger.success(
    'Locales refreshed '
    '(${report.keys.length} keys for ${report.locales.join(', ')}).',
  );
}

/// Maps a thrown error to a CLI exit code, printing it first.
int reportCommandError(Object error, CliLogger logger) {
  switch (error) {
    case RegistryManifestException():
      for (final line in [error.message, ...error.details]) {
        logger.errorToStderr('Error: $line');
      }
      if (error.notFound) {
        return ExitCodes.registryNotFound;
      }
      return error.isSchemaInvalid
          ? ExitCodes.schemaInvalid
          : ExitCodes.validationFailed;
    case RegistrySourceException():
      for (final line in [error.message, ...error.details]) {
        logger.errorToStderr('Error: $line');
      }
      if (error.message.contains('Offline mode')) {
        return ExitCodes.offlineUnavailable;
      }
      if (error.message.contains('Local registry not found')) {
        return ExitCodes.registryNotFound;
      }
      return ExitCodes.networkError;
    case ManifestClosureException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.componentMissing;
    case PackageAddException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.usage;
    case EjectConflictException():
      for (final line in error.toString().split('\n')) {
        logger.errorToStderr(line.startsWith('Error:') ? line : 'Error: $line');
      }
      return ExitCodes.validationFailed;
    case EjectException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.componentMissing;
    case SingleOwnerViolationException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.validationFailed;
    case LockFileException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.validationFailed;
    case LocaleNotSupportedException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.validationFailed;
    case LocaleTablesMissingException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.validationFailed;
    case UnknownLocaleException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.usage;
    case UnknownLocaleComponentException():
      logger.errorToStderr('Error: $error');
      return ExitCodes.componentMissing;
    case ThemeApplyException():
      for (final line in error.lines) {
        logger.errorToStderr('Error: $line');
      }
      return ExitCodes.validationFailed;
    default:
      logger.errorToStderr('Error: $error');
      return ExitCodes.ioError;
  }
}

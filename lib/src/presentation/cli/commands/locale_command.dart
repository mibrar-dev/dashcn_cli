import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/locale/locale_sync_service.dart';
import 'package:dashcn_cli/src/application/services/locale/locale_tables.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';

/// `dashcn locale add <code>`, `dashcn locale list` and
/// `dashcn locale remove <code>`.
///
/// Class and parameter names stay English; only UI strings are translated.
/// `locale add` installs one language for every installed component (later
/// `dashcn add` runs include it automatically); `locale remove` drops a
/// language again; `locale list` shows every locale the registry ships.
/// All three are idempotent: re-running writes nothing.
Future<int> runLocaleCommand({
  required ArgResults localeCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(localeCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  final sub = localeCommand.command;
  if (commandFlag(localeCommand, 'help') ||
      localeCommand.rest.contains('--help') ||
      localeCommand.rest.contains('-h') ||
      sub == null) {
    if (!json) {
      _printLocaleHelp();
    } else {
      printJson(jsonEnvelope(
        command: 'locale',
        data: const {'help': 'dashcn locale <add|list|remove>'},
        meta: {'exitCode': ExitCodes.success},
      ));
    }
    return sub == null &&
            !localeCommand.rest.contains('--help') &&
            !localeCommand.rest.contains('-h') &&
            !commandFlag(localeCommand, 'help')
        ? ExitCodes.usage
        : ExitCodes.success;
  }
  if (commandFlag(sub, 'help')) {
    _printLocaleHelp();
    return ExitCodes.success;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final service = LocaleSyncService(
      source: context.source,
      manifest: context.loadedManifest.manifest,
      projectRoot: projectRoot,
      installRoot: context.installRoot,
    );
    switch (sub.name) {
      case 'add':
        return await _runAdd(sub, service, json: json, logger: logger);
      case 'remove':
        return await _runRemove(sub, service, json: json, logger: logger);
      case 'list':
        return await _runList(sub, service, json: json);
      default:
        _printLocaleHelp();
        return ExitCodes.usage;
    }
  } on LocaleNotSupportedException catch (error) {
    return _localeFailure(error.toString(), json: json, logger: logger);
  } on LocaleTablesMissingException catch (error) {
    return _localeFailure(error.toString(), json: json, logger: logger);
  } on UnknownLocaleException catch (error) {
    if (!json) {
      logger.errorToStderr('Error: $error');
    } else {
      printJson(jsonEnvelope(
        command: 'locale',
        data: const {},
        errors: [
          jsonError(code: 'unknown_locale', message: error.toString()),
        ],
        meta: {'exitCode': ExitCodes.usage},
      ));
    }
    return ExitCodes.usage;
  } on UnknownLocaleComponentException catch (error) {
    if (!json) {
      logger.errorToStderr('Error: $error');
    }
    return ExitCodes.componentMissing;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

Future<int> _runAdd(
  ArgResults sub,
  LocaleSyncService service, {
  required bool json,
  required CliLogger logger,
}) async {
  final codes = componentIdsFrom(sub);
  if (codes.length != 1) {
    if (!json) {
      _printLocaleHelp();
    }
    return ExitCodes.usage;
  }
  final report = await service.addLocale(codes.single);
  if (json) {
    printJson(jsonEnvelope(
      command: 'locale',
      data: {'action': 'add', 'code': codes.single, ...report.toJson()},
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }
  if (report.written.isEmpty && report.removed.isEmpty) {
    logger.success(
      'Locale ${codes.single} is already installed '
      '(${report.keys.length} keys for ${report.locales.join(', ')}).',
    );
  } else {
    logger.success(
      'Installed locale ${codes.single} '
      '(${report.keys.length} keys for ${report.locales.join(', ')}).',
    );
    for (final path in report.written) {
      logger.info('  $path');
    }
  }
  return ExitCodes.success;
}

Future<int> _runRemove(
  ArgResults sub,
  LocaleSyncService service, {
  required bool json,
  required CliLogger logger,
}) async {
  final codes = componentIdsFrom(sub);
  if (codes.length != 1) {
    if (!json) {
      _printLocaleHelp();
    }
    return ExitCodes.usage;
  }
  final report = await service.removeLocale(codes.single);
  if (json) {
    printJson(jsonEnvelope(
      command: 'locale',
      data: {'action': 'remove', 'code': codes.single, ...report.toJson()},
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }
  if (report.written.isEmpty && report.removed.isEmpty) {
    logger.success('Locale ${codes.single} is not installed; nothing to do.');
  } else {
    logger.success('Removed locale ${codes.single}.');
    for (final path in [...report.removed, ...report.written]) {
      logger.info('  $path');
    }
  }
  return ExitCodes.success;
}

Future<int> _runList(
  ArgResults sub,
  LocaleSyncService service, {
  required bool json,
}) async {
  final entries = await service.listLocales();
  if (json) {
    printJson(jsonEnvelope(
      command: 'locale',
      data: {
        'action': 'list',
        'locales': [for (final entry in entries) entry.toJson()],
      },
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }
  stdout.writeln('code     direction installed keys');
  for (final entry in entries) {
    stdout.writeln(
      '${entry.code.padRight(9)}'
      '${entry.direction.padRight(10)}'
      '${(entry.installed ? 'yes' : 'no').padRight(10)}'
      '${entry.keyCount}',
    );
  }
  stdout.writeln('');
  stdout.writeln(
    'English (en) is always installed; other locales are added with '
    '`dashcn locale add <code>`.',
  );
  return ExitCodes.success;
}

int _localeFailure(String message,
    {required bool json, required CliLogger logger}) {
  if (json) {
    printJson(jsonEnvelope(
      command: 'locale',
      data: const {},
      errors: [
        jsonError(code: 'locale_unsupported', message: message),
      ],
      meta: {'exitCode': ExitCodes.validationFailed},
    ));
  } else {
    logger.errorToStderr('Error: $message');
  }
  return ExitCodes.validationFailed;
}

void _printLocaleHelp() {
  stdout.writeln('Usage: dashcn locale <add|list|remove> [flags]');
  stdout.writeln('');
  stdout.writeln('Installs component translations alongside the sources.');
  stdout.writeln('Class and parameter names stay English; only UI strings');
  stdout.writeln('are translated. Files land in dashcn_locales/.');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln(
      '  add <code>      Install a language for every installed component');
  stdout.writeln('  list [--json]   List every locale the registry ships');
  stdout.writeln('  remove <code>   Remove a language again');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dashcn locale add ar');
  stdout.writeln('  dashcn locale list');
  stdout.writeln('  dashcn locale remove ar');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --json              Machine-readable output on stdout');
  stdout.writeln('  --help, -h          Show this message');
}

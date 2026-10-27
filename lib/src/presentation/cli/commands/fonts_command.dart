import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/fonts/font_sync_service.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';
import 'package:dashcn_cli/src/theme_interop/google_fonts_catalogue.dart';

/// `dashcn fonts add <id> [--google]` and `dashcn fonts list`.
///
/// `fonts add` installs one font pack from the registry's `fonts` map into
/// `assets/fonts/` (plus the `flutter: fonts:` pubspec entries); with
/// `--google` it instead adds the `google_fonts` dependency and copies no
/// files. `fonts list` shows every pack the registry ships. Both are
/// idempotent: re-running writes nothing.
///
/// `dashcn add <component>` never installs a font: apps get the platform
/// font by default and opt into packs or Google Fonts here.
Future<int> runFontsCommand({
  required ArgResults fontsCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(fontsCommand, 'json');
  final logger = commandLogger(rootArgs, json: json);

  final sub = fontsCommand.command;
  if (commandFlag(fontsCommand, 'help') ||
      fontsCommand.rest.contains('--help') ||
      fontsCommand.rest.contains('-h') ||
      sub == null) {
    if (!json) {
      _printFontsHelp();
    } else {
      printJson(jsonEnvelope(
        command: 'fonts',
        data: const {'help': 'dashcn fonts <add|list>'},
        meta: {'exitCode': ExitCodes.success},
      ));
    }
    return sub == null &&
            !fontsCommand.rest.contains('--help') &&
            !fontsCommand.rest.contains('-h') &&
            !commandFlag(fontsCommand, 'help')
        ? ExitCodes.usage
        : ExitCodes.success;
  }
  if (commandFlag(sub, 'help')) {
    _printFontsHelp();
    return ExitCodes.success;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final service = FontSyncService(
      source: context.source,
      manifest: context.loadedManifest.manifest,
      projectRoot: projectRoot,
    );
    switch (sub.name) {
      case 'add':
        return await _runAdd(sub, service, json: json, logger: logger);
      case 'list':
        return await _runList(sub, service, json: json);
      default:
        _printFontsHelp();
        return ExitCodes.usage;
    }
  } on FontNotSupportedException catch (error) {
    return _fontsFailure(error.toString(), json: json, logger: logger);
  } on UnknownFontException catch (error) {
    if (!json) {
      logger.errorToStderr('Error: $error');
    } else {
      printJson(jsonEnvelope(
        command: 'fonts',
        data: const {},
        errors: [
          jsonError(code: 'unknown_font', message: error.toString()),
        ],
        meta: {'exitCode': ExitCodes.usage},
      ));
    }
    return ExitCodes.usage;
  } on FontFileMissingException catch (error) {
    if (!json) {
      logger.errorToStderr('Error: $error');
    }
    return ExitCodes.fileMissing;
  } on FontPubspecMissingException catch (error) {
    if (!json) {
      logger.errorToStderr('Error: $error');
    }
    return ExitCodes.ioError;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

Future<int> _runAdd(
  ArgResults sub,
  FontSyncService service, {
  required bool json,
  required CliLogger logger,
}) async {
  final ids = componentIdsFrom(sub);
  if (ids.length != 1) {
    if (!json) {
      _printFontsHelp();
    }
    return ExitCodes.usage;
  }
  final google = commandFlag(sub, 'google');
  final report = await service.addFont(ids.single, google: google);
  if (json) {
    printJson(jsonEnvelope(
      command: 'fonts',
      data: {'action': 'add', 'google': google, ...report.toJson()},
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }
  if (report.written.isEmpty) {
    logger.success(
      'Font ${ids.single} is already installed '
      '(${report.families.join(', ')}).',
    );
  } else if (google) {
    logger.success(
      'Added $kGoogleFontsPackageName $kGoogleFontsVersionPin '
      'for font ${ids.single} (${report.families.join(', ')}).',
    );
    for (final family in report.families) {
      logger.info('  ${googleFontsGetFontExpression(family)}');
    }
  } else {
    logger.success(
      'Installed font ${ids.single} (${report.families.join(', ')}).',
    );
    for (final path in report.written) {
      logger.info('  $path');
    }
  }
  return ExitCodes.success;
}

Future<int> _runList(
  ArgResults sub,
  FontSyncService service, {
  required bool json,
}) async {
  final entries = await service.listFonts();
  if (json) {
    printJson(jsonEnvelope(
      command: 'fonts',
      data: {
        'action': 'list',
        'fonts': [for (final entry in entries) entry.toJson()],
      },
      meta: {'exitCode': ExitCodes.success},
    ));
    return ExitCodes.success;
  }
  stdout.writeln('id           families             installed');
  for (final entry in entries) {
    stdout.writeln(
      '${entry.id.padRight(13)}'
      '${entry.families.join(', ').padRight(21)}'
      '${entry.installed ? 'yes' : 'no'}',
    );
  }
  stdout.writeln('');
  stdout.writeln(
    'Apps use the platform font by default; add a pack with '
    '`dashcn fonts add <id>`.',
  );
  return ExitCodes.success;
}

int _fontsFailure(String message,
    {required bool json, required CliLogger logger}) {
  if (json) {
    printJson(jsonEnvelope(
      command: 'fonts',
      data: const {},
      errors: [
        jsonError(code: 'fonts_unsupported', message: message),
      ],
      meta: {'exitCode': ExitCodes.validationFailed},
    ));
  } else {
    logger.errorToStderr('Error: $message');
  }
  return ExitCodes.validationFailed;
}

void _printFontsHelp() {
  stdout.writeln('Usage: dashcn fonts <add|list> [flags]');
  stdout.writeln('');
  stdout.writeln('Installs font packs from the registry fonts map into');
  stdout.writeln('assets/fonts/ with the matching `flutter: fonts:` pubspec');
  stdout.writeln('entries. `dashcn add` never installs a font.');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  add <id>         Install a font pack for the project');
  stdout.writeln('  list [--json]    List every font pack the registry ships');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dashcn fonts add geist-sans');
  stdout.writeln('  dashcn fonts add geist-sans --google');
  stdout.writeln('  dashcn fonts list');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout
      .writeln('  --google            Add the google_fonts dependency instead');
  stdout.writeln('                      of copying font files (opt-in)');
  stdout.writeln('  --json              Machine-readable output on stdout');
  stdout.writeln('  --help, -h          Show this message');
}

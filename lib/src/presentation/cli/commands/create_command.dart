import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/application/services/registry_manifest_loader.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/application/services/registry_source_resolver.dart';
import 'package:dashcn_cli/src/application/services/starter/starter_definition.dart';
import 'package:dashcn_cli/src/application/services/starter/starter_template.dart';
import 'package:dashcn_cli/src/application/services/theme/app_theme_generator.dart';
import 'package:dashcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_interop_bridge.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/theme_interop_command.dart';
import 'package:dashcn_cli/src/theme_interop/interop.dart';
import 'package:path/path.dart' as p;

/// Valid starter ids (v1.0, P9-6).
const List<String> kStarterIds = <String>['saas', 'chat', 'shop'];

/// Default org for `flutter create --org`.
const String kCreateDefaultOrg = 'com.example';

/// Allowed `--platforms` values.
const Set<String> kCreatePlatforms = <String>{
  'ios',
  'android',
  'web',
  'macos',
  'windows',
  'linux',
};

/// `dashcn create` scaffolds a starter app.
///
/// Runs `flutter create --empty`, then package mode adds the `dashcn` pub
/// dependency (a path dependency when `DASHCN_KIT_ROOT` is set, for tests),
/// while copy mode owns the sources under `lib/ui/dashcn/` via the installer.
/// Templates use simple `{{var}}` substitution; the result is `dart format`ed.
Future<int> runCreateCommand({
  required ArgResults createCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final logger = commandLogger(rootArgs, json: false);

  if (commandFlag(createCommand, 'help')) {
    _printCreateHelp();
    return ExitCodes.success;
  }
  if (commandFlag(createCommand, 'list')) {
    return _runList(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
  }

  final rest = createCommand.rest;
  if (rest.length != 2) {
    _printCreateHelp();
    return ExitCodes.usage;
  }
  final starterId = rest[0].trim();
  final appDirName = rest[1].trim();
  final themeOpt = commandOption(createCommand, 'theme');
  final modeOpt = commandOption(createCommand, 'mode')?.trim().toLowerCase();
  final mode = modeOpt == null || modeOpt.isEmpty ? 'copy' : modeOpt;
  final platformsOpt = commandOption(createCommand, 'platforms');
  final orgOpt = commandOption(createCommand, 'org')?.trim();
  final force = commandFlag(createCommand, 'force');
  final dryRun = commandFlag(createCommand, 'dry-run');

  if (!kStarterIds.contains(starterId)) {
    logger.errorToStderr(
      'Error: unknown starter "$starterId" '
      '(expected one of ${kStarterIds.join(', ')}).',
    );
    logger.errorToStderr('Run `dashcn create --list` to see starters.');
    return ExitCodes.usage;
  }
  if (mode != 'package' && mode != 'copy') {
    logger.errorToStderr(
      'Error: --mode must be `package` or `copy` (got `$modeOpt`).',
    );
    return ExitCodes.usage;
  }
  final packageName = sanitizePackageName(appDirName);
  if (!isValidPackageName(packageName)) {
    logger.errorToStderr('Error: "$appDirName" is not a valid app name.');
    return ExitCodes.usage;
  }
  final platforms = _parsePlatforms(platformsOpt);
  if (platforms == null) {
    logger.errorToStderr(
      'Error: --platforms must be a comma list of '
      '${kCreatePlatforms.join(', ')}.',
    );
    return ExitCodes.usage;
  }
  final org = orgOpt == null || orgOpt.isEmpty ? kCreateDefaultOrg : orgOpt;
  if (!_isValidOrg(org)) {
    logger.errorToStderr('Error: --org must look like com.example.');
    return ExitCodes.usage;
  }

  final targetDir = p.normalize(
    p.isAbsolute(appDirName) ? appDirName : p.join(projectRoot, appDirName),
  );

  try {
    final context = await _loadRegistryContext(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final starter = await _loadStarter(
      context.source,
      context.loadedManifest.rawJson,
      starterId,
    );
    final themePreset = themeOpt?.trim().isNotEmpty == true
        ? themeOpt!.trim()
        : starter.themePreset;
    final isThemeFile = _isThemeFileRef(themePreset);
    if (!isThemeFile) {
      final presets = _presetIds(context.loadedManifest.rawJson);
      if (!presets.contains(themePreset)) {
        logger.errorToStderr(
          'Error: unknown theme "$themePreset" '
          '(expected a preset or a file.css path).',
        );
        return ExitCodes.usage;
      }
    }

    if (dryRun) {
      _printDryRun(
        logger: logger,
        starter: starter,
        appDirName: appDirName,
        packageName: packageName,
        mode: mode,
        theme: themePreset,
        platforms: platforms,
        org: org,
        targetDir: targetDir,
      );
      return ExitCodes.success;
    }

    if (!_ensureTargetEmpty(targetDir, force, logger)) {
      return ExitCodes.usage;
    }
    return await _runCreate(
      starter: starter,
      appDirName: appDirName,
      packageName: packageName,
      mode: mode,
      theme: themePreset,
      isThemeFile: isThemeFile,
      platforms: platforms,
      org: org,
      targetDir: targetDir,
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

Future<_RegistryContext> _loadRegistryContext({
  required String projectRoot,
  required CliLogger logger,
  String? registryOverride,
  bool offline = false,
}) async {
  final config = await DashcnConfig.load(projectRoot);
  final source = RegistrySourceResolver.resolve(
    projectRoot: projectRoot,
    config: config,
    registryOverride: registryOverride,
    offline: offline,
  );
  final loaded = await RegistryManifestLoader(source).load();
  return _RegistryContext(source: source, loadedManifest: loaded);
}

Future<StarterDefinition> _loadStarter(
  RegistrySource source,
  Map<String, dynamic> rawManifest,
  String id,
) async {
  final starters = rawManifest['starters'];
  if (starters is Map && starters.containsKey(id)) {
    final entry =
        (starters[id] as Map).map((k, v) => MapEntry(k.toString(), v));
    final text = await source.readString('starters/$id/starter.json');
    if (text != null) {
      return StarterDefinition.parse(id, text);
    }
    return StarterDefinition.fromJson(id, entry);
  }
  final text = await source.readString('starters/$id/starter.json');
  if (text == null) {
    throw ManifestClosureException('starter', id);
  }
  return StarterDefinition.parse(id, text);
}

List<String> _presetIds(Map<String, dynamic> rawManifest) {
  final themes = rawManifest['themes'];
  if (themes is! Map) {
    return const <String>[];
  }
  return themes.keys.map((k) => k.toString()).toList()..sort();
}

List<String>? _parsePlatforms(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return kCreatePlatforms.toList()..sort();
  }
  final parts = raw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return null;
  }
  for (final part in parts) {
    if (!kCreatePlatforms.contains(part)) {
      return null;
    }
  }
  return parts.toSet().toList()..sort();
}

bool _isValidOrg(String org) {
  return RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(org);
}

bool _isThemeFileRef(String theme) {
  if (theme.endsWith('.css')) {
    return true;
  }
  if (theme.contains('/') || theme.contains(r'\')) {
    return true;
  }
  return File(theme).existsSync();
}

bool _ensureTargetEmpty(String targetDir, bool force, CliLogger logger) {
  final dir = Directory(targetDir);
  if (!dir.existsSync()) {
    return true;
  }
  final entries = dir.listSync();
  if (entries.isEmpty) {
    return true;
  }
  if (!force) {
    logger.errorToStderr(
      'Error: target "$targetDir" is not empty; '
      'use --force to overwrite.',
    );
    return false;
  }
  return true;
}

void _printDryRun({
  required CliLogger logger,
  required StarterDefinition starter,
  required String appDirName,
  required String packageName,
  required String mode,
  required String theme,
  required List<String> platforms,
  required String org,
  required String targetDir,
}) {
  logger.info('Would create starter "${starter.id}" as "$appDirName":');
  logger.info('  target:    $targetDir');
  logger.info('  package:   $packageName');
  logger.info('  mode:      $mode');
  logger.info('  theme:     $theme');
  logger.info('  platforms: ${platforms.join(',')}');
  logger.info('  org:       $org');
  logger.info('  flows:     ${starter.flows.join(', ')}');
  logger.info(
    '  blocks:    ${starter.blocks.isEmpty ? '(none)' : starter.blocks.join(', ')}',
  );
  logger.info(
    '  components:${starter.components.isEmpty ? ' (none)' : ' ${starter.components.join(', ')}'}',
  );
  logger.info('  files:');
  for (final file in starter.files) {
    logger.info('    ${file.target} (from ${file.template})');
  }
  logger.info(
    mode == 'package'
        ? '  theme file: lib/app_theme.dart (package:dashcn)'
        : '  theme file: lib/ui/dashcn/theme/app_theme.dart',
  );
}

Future<int> _runList({
  required String projectRoot,
  required CliLogger logger,
  String? registryOverride,
  bool offline = false,
}) async {
  try {
    final context = await _loadRegistryContext(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final raw = context.loadedManifest.rawJson;
    final starters = raw['starters'];
    final ids = starters is Map
        ? (starters.keys.map((k) => k.toString()).toList()..sort())
        : kStarterIds;
    logger.info('Available starters (${ids.length}):');
    for (final id in ids) {
      final entry = starters is Map && starters[id] is Map
          ? (starters[id] as Map).map((k, v) => MapEntry(k.toString(), v))
          : null;
      final name = entry?['name'] as String? ?? id;
      final desc = entry?['description'] as String? ?? '';
      logger.info('  $id  $name${desc.isEmpty ? '' : ' — $desc'}');
    }
    logger.info('');
    logger.info('Create one with: dashcn create <starter> <name>');
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}

Future<int> _runCreate({
  required StarterDefinition starter,
  required String appDirName,
  required String packageName,
  required String mode,
  required String theme,
  required bool isThemeFile,
  required List<String> platforms,
  required String org,
  required String targetDir,
  required String projectRoot,
  required CliLogger logger,
  String? registryOverride,
  bool offline = false,
}) async {
  final createResult = await Process.run('flutter', [
    'create',
    '--empty',
    '--org',
    org,
    '--platforms',
    platforms.join(','),
    '--project-name',
    packageName,
    targetDir,
  ]);
  if (createResult.exitCode != 0) {
    logger.errorToStderr(
      'Error: flutter create failed (exit ${createResult.exitCode}).',
    );
    if ((createResult.stdout as Object).toString().isNotEmpty) {
      logger.errorToStderr(createResult.stdout.toString());
    }
    if ((createResult.stderr as Object).toString().isNotEmpty) {
      logger.errorToStderr(createResult.stderr.toString());
    }
    return ExitCodes.ioError;
  }

  final appName = starterAppName(packageName);
  final themeBuild = isThemeFile
      ? starterThemeBuild(starter.themePreset)
      : starterThemeBuild(theme);

  if (mode == 'package') {
    final exit = await _setupPackageMode(
      starter: starter,
      packageName: packageName,
      theme: theme,
      isThemeFile: isThemeFile,
      targetDir: targetDir,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    if (exit != ExitCodes.success) {
      return exit;
    }
  } else {
    final exit = await _setupCopyMode(
      starter: starter,
      theme: theme,
      isThemeFile: isThemeFile,
      targetDir: targetDir,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    if (exit != ExitCodes.success) {
      return exit;
    }
  }

  final writeExit = await _renderTemplates(
    starter: starter,
    appName: appName,
    packageName: packageName,
    mode: mode,
    themeBuild: themeBuild,
    themePreset: isThemeFile ? starter.themePreset : theme,
    targetDir: targetDir,
    logger: logger,
    registryOverride: registryOverride,
    projectRoot: projectRoot,
    offline: offline,
  );
  if (writeExit != ExitCodes.success) {
    return writeExit;
  }

  final formatResult = await Process.run(
    'dart',
    ['format', 'lib', 'test'],
    workingDirectory: targetDir,
  );
  if (formatResult.exitCode != 0) {
    logger.errorToStderr('Warning: dart format failed in $targetDir.');
  }

  logger.header('Created ${starter.id} starter as $appDirName');
  logger.info('  dir:     $targetDir');
  logger.info('  mode:    $mode');
  logger.info('  theme:   $theme');
  logger.info('');
  logger.info('Next:');
  logger.info('  cd $appDirName');
  logger.info('  flutter analyze');
  logger.info('  flutter test');
  logger.info('  flutter run');
  return ExitCodes.success;
}

Future<int> _setupPackageMode({
  required StarterDefinition starter,
  required String packageName,
  required String theme,
  required bool isThemeFile,
  required String targetDir,
  required CliLogger logger,
  String? registryOverride,
  bool offline = false,
}) async {
  final context = await CommandContextResolver.resolve(
    projectRoot: targetDir,
    logger: logger,
    registryOverride: registryOverride,
    offline: offline,
  );
  await DashcnConfig.save(
    targetDir,
    context.config.copyWith(
      installPath: context.installRoot,
      installMode: DashcnConfig.installModePackage,
    ),
  );
  await LockRepository(targetDir).save(
    DashcnLock(installRoot: context.installRoot),
  );

  final kitRoot = _kitPackageDir();
  final pubArgs = kitRoot == null
      ? <String>['pub', 'add', 'dashcn']
      : <String>['pub', 'add', 'dashcn', '--path', kitRoot];
  final pubResult = await Process.run(
    'flutter',
    pubArgs,
    workingDirectory: targetDir,
  );
  if (pubResult.exitCode != 0) {
    logger.errorToStderr(
      'Error: flutter ${pubArgs.join(' ')} failed '
      '(exit ${pubResult.exitCode}).',
    );
    return ExitCodes.ioError;
  }

  // Package apps keep zero copied sources: the theme lands as
  // lib/app_theme.dart importing package:dashcn.

  try {
    await _writePackageTheme(
      theme: theme,
      isThemeFile: isThemeFile,
      targetDir: targetDir,
      logger: logger,
      source: context.source,
    );
  } catch (error) {
    return reportCommandError(error, logger);
  }
  return ExitCodes.success;
}

Future<int> _setupCopyMode({
  required StarterDefinition starter,
  required String theme,
  required bool isThemeFile,
  required String targetDir,
  required CliLogger logger,
  String? registryOverride,
  bool offline = false,
}) async {
  final context = await CommandContextResolver.resolve(
    projectRoot: targetDir,
    logger: logger,
    registryOverride: registryOverride,
    offline: offline,
  );
  await context.installer.installCore();
  await DashcnConfig.save(
    targetDir,
    context.config.copyWith(
      installPath: context.installRoot,
      installMode: DashcnConfig.installModeCopy,
    ),
  );

  final report = await context.installer.add(
    starter.components,
    blockIds: starter.blocks,
    flowIds: starter.flows,
    includeCore: true,
  );
  if (!report.applied) {
    logger.errorToStderr('Error: starter install produced no plan.');
    return ExitCodes.ioError;
  }

  if (isThemeFile) {
    return runThemeImport(
      source: theme,
      name: null,
      apply: true,
      projectRoot: targetDir,
      installRootOverride: context.installRoot,
      logger: logger,
    );
  }
  try {
    await context.themeService.apply(theme);
  } catch (error) {
    return reportCommandError(error, logger);
  }
  return ExitCodes.success;
}

/// Writes `lib/app_theme.dart` for package-mode apps: a single
/// `package:dashcn/dashcn.dart` import plus the preset values, so package
/// ThemeData never duplicates a local copy.
Future<void> _writePackageTheme({
  required String theme,
  required bool isThemeFile,
  required String targetDir,
  required CliLogger logger,
  required RegistrySource source,
}) async {
  final Map<String, Object?> preset;
  if (isThemeFile) {
    final text = await File(theme).readAsString();
    final parsed = parseWebThemeSource(text);
    final id = sanitizePresetIdSafe(
      p.basenameWithoutExtension(theme.split('?').first),
    );
    final jsonText = presetJsonStringFromWebTheme(
      parsed.theme,
      id: id.isEmpty ? 'imported' : id,
      name: id.isEmpty ? 'imported' : id,
    );
    preset = (jsonDecode(jsonText) as Map)
        .map((k, v) => MapEntry(k.toString(), v as Object?));
    for (final line in formatImportReport(parsed.report)) {
      logger.info(line);
    }
  } else {
    final text = await source.readString('themes/$theme.json');
    if (text == null) {
      throw ManifestClosureException('theme', theme);
    }
    preset = (jsonDecode(text) as Map)
        .map((k, v) => MapEntry(k.toString(), v as Object?));
  }
  final values = AppThemeValues.fromJson(preset);
  final full = renderAppTheme(values);
  final packageSource = full.replaceAll(
    "import 'theme.dart';\nimport 'color_tokens.dart';\nimport 'tokens.dart';",
    "import 'package:dashcn/dashcn.dart';",
  );
  final out = File(p.join(targetDir, 'lib', 'app_theme.dart'));
  await out.parent.create(recursive: true);
  await out.writeAsString(packageSource, flush: true);
}

Future<int> _renderTemplates({
  required StarterDefinition starter,
  required String appName,
  required String packageName,
  required String mode,
  required String themeBuild,
  required String themePreset,
  required String targetDir,
  required CliLogger logger,
  String? registryOverride,
  required String projectRoot,
  bool offline = false,
}) async {
  final config = await DashcnConfig.load(projectRoot);
  final source = RegistrySourceResolver.resolve(
    projectRoot: projectRoot,
    config: config,
    registryOverride: registryOverride,
    offline: offline,
  );
  for (final file in starter.files) {
    final text = await source.readString(file.template);
    if (text == null) {
      logger.errorToStderr('Error: starter template missing: ${file.template}');
      return ExitCodes.ioError;
    }
    final imports = starterImports(
      starterId: starter.id,
      target: file.target,
      mode: mode,
    );
    final rendered = renderStarterTemplate(text, {
      'appName': appName,
      'packageName': packageName,
      'imports': imports,
      'themePreset': themePreset,
      'themeBuild': themeBuild,
    });
    final out = File(p.join(targetDir, p.normalize(file.target)));
    await out.parent.create(recursive: true);
    await out.writeAsString(rendered, flush: true);
  }
  final pubspec = File(p.join(targetDir, 'pubspec.yaml'));
  if (await pubspec.exists()) {
    var text = await pubspec.readAsString();
    if (!text.contains('dashcn')) {
      logger.info('Note: add dashcn theming via `dashcn theme apply`.');
    }
  }
  return ExitCodes.success;
}

String? _kitPackageDir() {
  final override = Platform.environment['DASHCN_KIT_ROOT']?.trim();
  if (override == null || override.isEmpty) {
    return null;
  }
  final direct = Directory(p.join(override, 'dashcn'));
  if (File(p.join(direct.path, 'pubspec.yaml')).existsSync()) {
    return direct.path;
  }
  if (File(p.join(override, 'pubspec.yaml')).existsSync()) {
    return p.normalize(override);
  }
  return null;
}

void _printCreateHelp() {
  stdout.writeln('Usage: dashcn create <starter> <name> [flags]');
  stdout.writeln('       dashcn create --list');
  stdout.writeln('');
  stdout.writeln('Scaffolds a runnable app from flows, blocks and a theme.');
  stdout.writeln('');
  stdout.writeln('Arguments:');
  stdout.writeln('  <starter>           One of: ${kStarterIds.join(', ')}');
  stdout.writeln('  <name>              App directory to create');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --theme <preset|file.css>  Theme preset or CSS file');
  stdout.writeln('  --mode <mode>       `copy` (own sources) or `package`');
  stdout.writeln('  --platforms <list>  Comma list (default: all six)');
  stdout.writeln('  --org <id>          Org for flutter create');
  stdout.writeln('                      (default: $kCreateDefaultOrg)');
  stdout.writeln('  --force             Overwrite a non-empty target dir');
  stdout.writeln('  --dry-run           Print the plan without writing');
  stdout.writeln('  --list              List available starters');
  stdout.writeln('  --help, -h          Show this message');
}

class _RegistryContext {
  const _RegistryContext({required this.source, required this.loadedManifest});

  final RegistrySource source;
  final LoadedRegistryManifest loadedManifest;
}

/// Visible for tests: starter template variable names.
const List<String> kStarterTemplateVars = <String>[
  'appName',
  'packageName',
  'imports',
  'themePreset',
  'themeBuild',
];

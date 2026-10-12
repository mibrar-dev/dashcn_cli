import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/theme/app_theme_generator.dart';
import 'package:dashcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_interop_bridge.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_models.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_service.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_target_writer.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/registry/manifest/theme_preset.dart';
import 'package:dashcn_cli/src/theme_interop/interop.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Default install root when no config or registry says otherwise.
const String kDefaultInstallRoot = 'lib/ui/dashcn';

/// `dashcn theme import <file|url> [--name <id>] [--apply]`.
///
/// Parses a web theme (CSS, Tailwind v3 config or preset JSON), prints the
/// import report and stores it as `<installRoot>/theme/<id>.json`. With
/// `--apply` the imported theme also becomes `app_theme.dart`, honoring the
/// same drift rules as `theme apply`.
Future<int> runThemeImport({
  required String? source,
  required String? name,
  required bool apply,
  required String projectRoot,
  required String? installRootOverride,
  required CliLogger logger,
}) async {
  final String ref = (source ?? '').trim();
  if (ref.isEmpty) {
    stderr.writeln('Error: missing <file|url> to import.');
    stderr.writeln(
        'Usage: dashcn theme import <file|url> [--name <id>] [--apply]');
    return ExitCodes.usage;
  }
  final String id = sanitizePresetIdSafe(name ?? _defaultName(ref));
  if (id.isEmpty) {
    stderr.writeln('Error: --name must yield a preset id (a-z, 0-9, dashes).');
    return ExitCodes.usage;
  }
  late final String text;
  try {
    text = await _readSource(ref);
  } on ImportReadException catch (error) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.ioError;
  }
  final WebImportResult parsed;
  try {
    parsed = parseWebThemeSource(text);
  } on FormatException catch (error) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.validationFailed;
  } on WebThemeException catch (error) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.validationFailed;
  }
  final String installRoot = normalizeInstallRoot(installRootOverride);
  final String presetJson = presetJsonStringFromWebTheme(
    parsed.theme,
    id: id,
    name: name?.trim().isNotEmpty == true ? name!.trim() : id,
  );
  final String relativePath =
      normalizeImportPath(p.join(installRoot, 'theme', '$id.json'));
  await _writeProjectFile(
    projectRoot: projectRoot,
    relativePath: relativePath,
    text: presetJson,
  );
  // The import becomes the current theme selection, so a following `export`
  // renders it; `--apply` additionally records the generated `app_theme.dart`.
  await _recordImportSelection(
    projectRoot: projectRoot,
    installRoot: installRoot,
    id: id,
    relativePath: relativePath,
    sha256: _sha256OfText(presetJson),
  );
  logger.success('Imported ${parsed.format.label} as "$id" ($relativePath)');
  for (final String line in formatImportReport(parsed.report)) {
    logger.info(line);
  }
  if (!apply) {
    return ExitCodes.success;
  }
  final Map<String, dynamic> decoded =
      jsonDecode(presetJson) as Map<String, dynamic>;
  try {
    final ThemeApplyResult result = await ThemeTargetWriter(
      projectRoot: projectRoot,
      installRoot: installRoot,
      logger: logger,
    ).writePreset(decoded, sourceFile: relativePath);
    return result.isClean ? ExitCodes.success : ExitCodes.themeDrift;
  } on ThemeApplyException catch (error) {
    for (final String line in error.lines) {
      stderr.writeln('Error: $line');
    }
    return ExitCodes.validationFailed;
  }
}

/// `dashcn theme export --format css|tailwind|dtcg|json|dart [--out <file>]`.
///
/// Exports the app's current theme (the `dashcn.lock` selection): an imported
/// `<installRoot>/theme/<id>.json` wins, otherwise the registry preset the
/// lock points at. Prints to stdout, or writes [--out] (project-relative or
/// absolute).
Future<int> runThemeExport({
  required String? formatName,
  required String? out,
  required String projectRoot,
  required String? installRootOverride,
  required CliLogger logger,
}) async {
  final WebExportFormat? format = formatName == null || formatName.isEmpty
      ? WebExportFormat.css
      : WebExportFormat.parse(formatName);
  if (format == null) {
    stderr.writeln(
      'Error: unknown --format "$formatName" '
      '(css|tailwind|dtcg|json|dart).',
    );
    return ExitCodes.usage;
  }
  final String installRoot = normalizeInstallRoot(installRootOverride);
  final Map<String, dynamic>? preset = await _currentPresetJson(
    projectRoot: projectRoot,
    installRoot: installRoot,
  );
  if (preset == null) {
    stderr.writeln(
      'Error: no theme applied yet (dashcn.lock has no theme entry). '
      'Import one with `dashcn theme import <file>` or apply a preset first.',
    );
    return ExitCodes.validationFailed;
  }
  final String payload;
  try {
    payload = _renderExport(preset, format);
  } on WebThemeException catch (error) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.validationFailed;
  } on FormatException catch (error) {
    stderr.writeln('Error: ${error.message}');
    return ExitCodes.validationFailed;
  }
  final String? target = out?.trim().isNotEmpty == true ? out!.trim() : null;
  if (target == null) {
    stdout.write(payload);
    if (!payload.endsWith('\n')) stdout.writeln();
    return ExitCodes.success;
  }
  await _writeOutFile(projectRoot: projectRoot, out: target, text: payload);
  logger.success('Exported ${format.name} to $target');
  return ExitCodes.success;
}

/// Project-relative install root: the override wins, then `.dashcn/config.json`.
String normalizeInstallRoot(String? override) {
  final String? trimmed = override?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return _normalizeLockPath(trimmed);
  }
  return kDefaultInstallRoot;
}

/// Loads `.dashcn/config.json` install path, or null when absent.
Future<String?> configInstallRoot(String projectRoot) async {
  try {
    final DashcnConfig config = await DashcnConfig.load(projectRoot);
    final String? path = config.installPath?.trim();
    return path != null && path.isNotEmpty ? path : null;
  } on DashcnConfigLoadException {
    return null;
  }
}

String _defaultName(String ref) {
  final String base = p.basenameWithoutExtension(ref.split('?').first);
  return base.isEmpty ? 'imported' : base;
}

String sanitizePresetIdSafe(String name) {
  try {
    return sanitizePresetId(name);
  } on FormatException {
    return '';
  }
}

String normalizeImportPath(String path) => _normalizeLockPath(path);

/// Records an import as the lock's theme selection (without touching
/// `app_theme.dart`): the stored preset JSON becomes what `export` renders.
Future<void> _recordImportSelection({
  required String projectRoot,
  required String installRoot,
  required String id,
  required String relativePath,
  required String sha256,
}) async {
  final LockRepository lockRepo = LockRepository(projectRoot);
  final DashcnLock lock = await lockRepo.load();
  await lockRepo.save(
    lock
        .withTheme(
          LockThemeSelection(
            id: id,
            path: relativePath,
            sha256: sha256,
          ),
        )
        .copyWith(
          installRoot: lock.installRoot.isEmpty ? installRoot : null,
        ),
  );
}

String _normalizeLockPath(String path) =>
    p.normalize(path).replaceAll('\\', '/');

String _sha256OfText(String text) => FileHashing.ofText(text);

Future<String> _readSource(String ref) async {
  if (ref.startsWith('http://') || ref.startsWith('https://')) {
    try {
      final http.Response response =
          await http.get(Uri.parse(ref)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw ImportReadException(
          'GET $ref failed with HTTP ${response.statusCode}.',
        );
      }
      return response.body;
    } on ImportReadException {
      rethrow;
    } on FormatException {
      throw ImportReadException('"$ref" is not a valid URL.');
    } catch (error) {
      throw ImportReadException('Could not download "$ref" ($error).');
    }
  }
  final File file = File(ref);
  if (!await file.exists()) {
    throw ImportReadException('File not found: $ref.');
  }
  try {
    return await file.readAsString();
  } catch (error) {
    throw ImportReadException('Could not read "$ref" ($error).');
  }
}

Future<void> _writeProjectFile({
  required String projectRoot,
  required String relativePath,
  required String text,
}) async {
  final String safePath = ProjectPathGuard.resolveSafeWritePath(
    projectRoot: projectRoot,
    destinationRelativePath: relativePath,
  );
  final File file = File(safePath);
  await file.parent.create(recursive: true);
  await file.writeAsString('$text\n', flush: true);
}

Future<void> _writeOutFile({
  required String projectRoot,
  required String out,
  required String text,
}) async {
  final File file = p.isAbsolute(out)
      ? File(p.normalize(out))
      : File(
          ProjectPathGuard.resolveSafeWritePath(
            projectRoot: projectRoot,
            destinationRelativePath: out,
          ),
        );
  await file.parent.create(recursive: true);
  await file.writeAsString(text.endsWith('\n') ? text : '$text\n', flush: true);
}

/// The current theme preset document: the imported JSON first, then the lock's
/// registry preset.
Future<Map<String, dynamic>?> _currentPresetJson({
  required String projectRoot,
  required String installRoot,
}) async {
  final LockRepository lockRepo = LockRepository(projectRoot);
  DashcnLock lock;
  try {
    lock = await lockRepo.load();
  } catch (_) {
    return null;
  }
  final String? id = lock.theme?.id;
  if (id == null || id.isEmpty) {
    return null;
  }
  final File imported = File(
    p.join(projectRoot,
        _normalizeLockPath(p.join(installRoot, 'theme', '$id.json'))),
  );
  if (await imported.exists()) {
    try {
      final Object? decoded = jsonDecode(await imported.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
  }
  try {
    final ThemeService service = await ThemeService.resolve(
      projectRoot: projectRoot,
      installRoot: installRoot,
    );
    final ThemePreset? preset = service.findPreset(id);
    if (preset == null) {
      return null;
    }
    return await service.source.readJson(preset.file);
  } catch (_) {
    return null;
  }
}

String _renderExport(Map<String, dynamic> preset, WebExportFormat format) {
  if (format == WebExportFormat.json) {
    return const JsonEncoder.withIndent('  ').convert(preset);
  }
  final WebTheme theme = webThemeFromPresetJson(
    preset.map(
      (String key, dynamic value) =>
          MapEntry<String, Object?>(key, value as Object?),
    ),
  );
  switch (format) {
    case WebExportFormat.css:
      return writeWebCss(theme);
    case WebExportFormat.tailwind:
      return writeTailwindV4Theme(theme);
    case WebExportFormat.dtcg:
      return writeDtcgTokens(theme);
    case WebExportFormat.dart:
      return renderAppTheme(AppThemeValues.fromJson(preset));
    case WebExportFormat.json:
      throw StateError('unreachable');
  }
}

/// A web theme source that could not be read.
class ImportReadException implements Exception {
  /// Creates the exception with a human readable [message].
  const ImportReadException(this.message);

  /// Human readable reason.
  final String message;

  @override
  String toString() => 'ImportReadException: $message';
}

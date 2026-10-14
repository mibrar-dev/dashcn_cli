import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/theme/app_theme_generator.dart';
import 'package:dashcn_cli/src/application/services/theme/app_theme_values.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_models.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_preset_validator.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:path/path.dart' as p;

/// Writes a validated preset document to `<installRoot>/theme/app_theme.dart`.
///
/// Shared by `theme apply <preset>` (registry presets) and
/// `theme import <file|url> --apply` (web themes): validate, render, then the
/// same drift-aware write — a locally modified file is refused unless
/// [refresh] is true, and the lock always describes the bytes on disk.
class ThemeTargetWriter {
  /// Creates a writer for [projectRoot] and [installRoot].
  ThemeTargetWriter({
    required this.projectRoot,
    required this.installRoot,
    CliLogger? logger,
  })  : _logger = logger ?? CliLogger(),
        _lock = LockRepository(projectRoot);

  /// Project root (the directory holding `.dashcn/` and `dashcn.lock`).
  final String projectRoot;

  /// Project-relative install root (`lib/ui/dashcn` by default).
  final String installRoot;

  final CliLogger _logger;
  final LockRepository _lock;

  /// Project-relative path of the generated theme file.
  String get appThemeRelativePath =>
      normalizeLockPath(p.join(installRoot, 'theme', 'app_theme.dart'));

  /// Renders [decoded] (schema-v2) into `app_theme.dart`.
  ///
  /// [sourceFile] names the origin in messages and the lock
  /// (`themes/<id>.json` for registry presets, the import path otherwise).
  Future<ThemeApplyResult> writePreset(
    Map<String, dynamic> decoded, {
    required String sourceFile,
    bool refresh = false,
  }) async {
    final validation = ThemePresetValidator.validate(
      decoded,
      label: sourceFile,
    );
    if (!validation.isValid) {
      throw ThemeApplyException(
        'Theme preset $sourceFile is invalid (themes.schema.json v2).',
        details: validation.errors,
      );
    }
    final Object? id = decoded['id'];
    if (id is! String || id.isEmpty) {
      throw ThemeApplyException(
          '$sourceFile: "id" must be a non-empty string.');
    }
    final AppThemeValues values;
    try {
      values = AppThemeValues.fromJson(decoded);
    } on FormatException catch (error) {
      throw ThemeApplyException('$sourceFile: ${error.message}');
    }
    final String rendered = renderAppTheme(values);
    final String renderedSha = FileHashing.ofText(rendered);

    final String relativePath = appThemeRelativePath;
    final DashcnLock lock = await _lock.load();
    final LockThemeSelection? recorded = lock.theme;
    final String? recordedSha = recorded != null &&
            recorded.path == relativePath &&
            recorded.sha256.isNotEmpty
        ? recorded.sha256
        : null;

    final File target = File(p.join(projectRoot, relativePath));
    final String? diskSha = await FileHashing.ofFileIfExists(target);
    final ThemeApplyStatus status;
    ThemeDrift? drift;
    if (diskSha == null) {
      await _write(relativePath, rendered);
      status = ThemeApplyStatus.created;
    } else if (diskSha == renderedSha) {
      status = ThemeApplyStatus.unchanged;
    } else if (recordedSha != null && recordedSha == diskSha) {
      // The lock's digest matches the bytes on disk, so the file is exactly
      // what the CLI wrote: switching presets may rewrite it without refresh.
      await _write(relativePath, rendered);
      status = ThemeApplyStatus.refreshed;
    } else {
      drift = ThemeDrift(
        kind: recordedSha == null
            ? ThemeDriftKind.untracked
            : ThemeDriftKind.modified,
        path: relativePath,
        recordedSha256: recordedSha,
        actualSha256: diskSha,
      );
      if (!refresh) {
        status = ThemeApplyStatus.drift;
      } else {
        await _write(relativePath, rendered);
        status = ThemeApplyStatus.refreshed;
      }
    }
    if (status != ThemeApplyStatus.drift) {
      // The lock must describe the bytes that exist: a refusal leaves the
      // previous selection in place.
      await _recordSelection(lock, id, relativePath, renderedSha);
    }
    await _persistConfigThemeId(id,
        onlyIfApplied: status != ThemeApplyStatus.drift);

    final Object? name = decoded['name'];
    final ThemeApplyResult result = ThemeApplyResult(
      status: status,
      presetId: id,
      presetName: name is String && name.isNotEmpty ? name : id,
      path: relativePath,
      sha256: renderedSha,
      sourceFile: sourceFile,
      drift: drift,
    );
    _report(result);
    return result;
  }

  Future<void> _write(String relativePath, String rendered) async {
    final String safePath = ProjectPathGuard.resolveSafeWritePath(
      projectRoot: projectRoot,
      destinationRelativePath: relativePath,
    );
    final File file = File(safePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(rendered, flush: true);
    _logger.detail('  ↳ wrote $relativePath');
  }

  Future<void> _recordSelection(
    DashcnLock lock,
    String id,
    String relativePath,
    String sha256,
  ) async {
    final LockThemeSelection? existing = lock.theme;
    final bool alreadyRecorded = existing != null &&
        existing.id == id &&
        existing.path == relativePath &&
        existing.sha256 == sha256 &&
        lock.installRoot.isNotEmpty;
    if (alreadyRecorded) return;
    await _lock.save(
      lock
          .withTheme(
            LockThemeSelection(id: id, path: relativePath, sha256: sha256),
          )
          .copyWith(
            installRoot: lock.installRoot.isEmpty ? installRoot : null,
          ),
    );
  }

  Future<void> _persistConfigThemeId(
    String presetId, {
    required bool onlyIfApplied,
  }) async {
    if (!onlyIfApplied) return;
    if (!await DashcnConfig.configFile(projectRoot).exists()) return;
    final DashcnConfig current = await DashcnConfig.load(projectRoot);
    if (current.themeId == presetId) return;
    await DashcnConfig.save(
      projectRoot,
      current.copyWith(themeId: presetId),
    );
  }

  void _report(ThemeApplyResult result) {
    switch (result.status) {
      case ThemeApplyStatus.created:
      case ThemeApplyStatus.refreshed:
        _logger.success('Applied theme ${result.presetName} (${result.path})');
      case ThemeApplyStatus.unchanged:
        _logger.info(
          'Theme ${result.presetName} already applied (${result.path}); '
          'nothing to do.',
        );
      case ThemeApplyStatus.drift:
        final ThemeDrift? drift = result.drift;
        final String reason = drift?.kind == ThemeDriftKind.untracked
            ? 'the file exists but dashcn.lock has no theme entry for it'
            : 'it was modified locally';
        _logger.warnToStderr(
          'Refusing to overwrite ${drift?.path ?? result.path}: $reason '
          '(recorded ${drift?.recordedSha256 ?? '(none)'}, '
          'on disk ${drift?.actualSha256 ?? '(none)'}).',
        );
        _logger.warnToStderr(
          'Re-run with --refresh to regenerate it from ${result.sourceFile}. '
          'Exiting with theme_drift (${ExitCodes.themeDrift}); nothing was '
          'written.',
        );
    }
    _logger.detail('  ↳ sha256 ${result.sha256}');
  }
}

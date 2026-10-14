import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_models.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_registry_source.dart';
import 'package:dashcn_cli/src/application/services/theme/theme_target_writer.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:dashcn_cli/src/registry/manifest/theme_preset.dart';
import 'package:path/path.dart' as p;

/// The theme flow for registry manifest v2: preset list and preset apply.
///
/// One `ThemeService` owns a project root, a registry source (which yields the
/// v2 manifest and the preset JSONs) and the project's `dashcn.lock`. The
/// only file it writes is `<installRoot>/theme/app_theme.dart`, and because
/// that file is user-owned it is only rewritten when the bytes on disk still
/// match the lock or the caller passes `refresh: true`.
///
/// B4 (`init`, `add`) and B5 (`theme`, `update`) call [apply] / [listPresets];
/// nothing else in the CLI needs to know how a preset becomes Dart.
class ThemeService {
  ThemeService({
    required this.projectRoot,
    required this.source,
    required this.manifest,
    this.config,
    this.installRootOverride,
    CliLogger? logger,
  })  : _logger = logger ?? CliLogger(),
        _lock = LockRepository(projectRoot);

  /// Project root (the directory holding `.dashcn/` and `dashcn.lock`).
  final String projectRoot;

  /// Registry the manifest and presets come from.
  final ThemeRegistrySource source;

  /// The validated v2 manifest.
  final RegistryManifest manifest;

  /// Project config, when the caller has it; only used for `installPath`.
  final DashcnConfig? config;

  /// Install root chosen by the caller (B4's `Installer` resolves one for the
  /// whole install). It wins over [config] and the manifest default so
  /// `app_theme.dart` always lands next to the installed `theme/` layer.
  final String? installRootOverride;

  final CliLogger _logger;
  final LockRepository _lock;

  /// `theme` layer directory of the install root.
  static const String themeLayerDir = 'theme';

  /// File name of the generated, values-only theme.
  static const String appThemeFileName = 'app_theme.dart';

  /// Builds a service from `.dashcn/config.json`: resolves the registry,
  /// loads and validates the manifest. Throws [ThemeApplyException] when no
  /// registry is configured or the manifest is invalid.
  static Future<ThemeService> resolve({
    required String projectRoot,
    String? installRoot,
    String? namespace,
    String? registryPathOverride,
    String? registryUrlOverride,
    bool offline = false,
    CliLogger? logger,
  }) async {
    final config = await DashcnConfig.load(projectRoot);
    final source = ThemeRegistrySourceResolver.requireFromConfig(
      config,
      namespace: namespace,
      registryPathOverride: registryPathOverride,
      registryUrlOverride: registryUrlOverride,
      offline: offline,
    );
    return ThemeService(
      projectRoot: projectRoot,
      source: source,
      manifest: await source.loadManifest(),
      config: config,
      installRootOverride: installRoot,
      logger: logger,
    );
  }

  /// Project-relative install root: the caller's override wins, then the
  /// project's `installPath`, then the manifest default.
  String get installRoot {
    final override = installRootOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return normalizeLockPath(override);
    }
    final configured = config?.installPath?.trim();
    if (configured != null && configured.isNotEmpty) {
      return normalizeLockPath(configured);
    }
    final fromManifest = manifest.install.root.trim();
    return normalizeLockPath(
      fromManifest.isEmpty ? 'lib/ui/dashcn' : fromManifest,
    );
  }

  /// Project-relative path of the generated theme file.
  String get appThemeRelativePath =>
      normalizeLockPath(p.join(installRoot, themeLayerDir, appThemeFileName));

  /// Absolute path of the generated theme file.
  File get appThemeFile => File(p.join(projectRoot, appThemeRelativePath));

  /// Every preset in the manifest, sorted by id, with the locked one marked.
  Future<List<ThemeCatalogEntry>> listPresets() async {
    final currentId = (await _lock.load()).theme?.id;
    final entries = manifest.themes.values
        .map((preset) =>
            ThemeCatalogEntry.fromPreset(preset, currentId: currentId))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return entries;
  }

  /// Renders `themes/<presetId>.json` into `<installRoot>/theme/app_theme.dart`.
  ///
  /// [refresh] forces the rewrite when the file on disk drifted. Without it a
  /// drifted file is left alone and the drift is reported.
  Future<ThemeApplyResult> apply(String presetId,
      {bool refresh = false}) async {
    final preset = findPreset(presetId);
    if (preset == null) {
      throw ThemeApplyException(
        'Unknown theme preset "$presetId".',
        details: <String>[
          'Available presets: '
              '${(await listPresets()).map((e) => e.id).join(', ')}',
        ],
      );
    }
    final decoded = await source.readJson(preset.file);
    if (decoded['id'] != preset.id) {
      throw ThemeApplyException(
        'Theme preset ${preset.file} declares id "${decoded['id']}" but the '
        'manifest lists it as "${preset.id}".',
      );
    }
    return ThemeTargetWriter(
      projectRoot: projectRoot,
      installRoot: installRoot,
      logger: _logger,
    ).writePreset(decoded, sourceFile: preset.file, refresh: refresh);
  }

  /// Finds a preset by id, then by display name (both case insensitive).
  ThemePreset? findPreset(String identifier) {
    final needle = identifier.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final preset in manifest.themes.values) {
      if (preset.id.toLowerCase() == needle) return preset;
    }
    for (final preset in manifest.themes.values) {
      if (preset.name.toLowerCase() == needle) return preset;
    }
    return null;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/config/registry_config_entry.dart';
import 'package:dashcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:path/path.dart' as p;

const Object _copyWithUnset = Object();

class DashcnConfigLoadException implements Exception {
  final String path;
  final Object cause;

  const DashcnConfigLoadException({
    required this.path,
    required this.cause,
  });

  @override
  String toString() => 'Failed to load config JSON at $path: $cause';
}

class DashcnConfig {
  static const String fallbackDefaultNamespace = 'dashcn';

  /// Install modes: `copy` owns the sources, `package` depends on pub.
  static const String installModeCopy = 'copy';
  static const String installModePackage = 'package';

  final String? classPrefix;
  final String? themeId;
  final String? registryMode;
  final String? registriesPath;
  final String? registryPath;
  final String? registryUrl;
  final String? installPath;
  final String? sharedPath;
  final bool? includeReadme;
  final bool? includeMeta;
  final bool? includePreview;
  final List<String>? includeFiles;
  final List<String>? excludeFiles;
  final bool? checkUpdates;
  final Map<String, String>? pathAliases;
  final Map<String, Map<String, String>>? platformTargets;
  final String? defaultNamespace;
  final Map<String, RegistryConfigEntry>? registries;

  /// `copy` (default) or `package`; chosen by `init --mode`.
  final String? installMode;

  const DashcnConfig({
    this.classPrefix,
    this.themeId,
    this.registryMode,
    this.registriesPath,
    this.registryPath,
    this.registryUrl,
    this.installPath,
    this.sharedPath,
    this.includeReadme,
    this.includeMeta,
    this.includePreview,
    this.includeFiles,
    this.excludeFiles,
    this.checkUpdates = true,
    this.pathAliases,
    this.platformTargets,
    this.defaultNamespace,
    this.registries,
    this.installMode,
  });

  factory DashcnConfig.fromJson(Map<String, dynamic> json) {
    final parsedRegistries = _parseRegistries(json['registries']);
    final resolvedNamespace = _resolveDefaultNamespace(
      requestedDefaultNamespace: json['defaultNamespace'] as String?,
      registries: parsedRegistries,
    );
    final activeRegistry = parsedRegistries?[resolvedNamespace];

    return DashcnConfig(
      classPrefix: json['classPrefix'] as String?,
      themeId: json['themeId'] as String?,
      registryMode:
          json['registryMode'] as String? ?? activeRegistry?.registryMode,
      registriesPath: json['registriesPath'] as String?,
      registryPath:
          json['registryPath'] as String? ?? activeRegistry?.registryPath,
      registryUrl: json['registryUrl'] as String? ??
          activeRegistry?.registryUrl ??
          activeRegistry?.baseUrl,
      installPath:
          json['installPath'] as String? ?? activeRegistry?.installPath,
      sharedPath: json['sharedPath'] as String? ?? activeRegistry?.sharedPath,
      includeReadme:
          json['includeReadme'] as bool? ?? activeRegistry?.includeReadme,
      checkUpdates: json['checkUpdates'] as bool? ?? true,
      includeMeta: json['includeMeta'] as bool? ?? activeRegistry?.includeMeta,
      includePreview:
          json['includePreview'] as bool? ?? activeRegistry?.includePreview,
      includeFiles: _stringListOrNull(json['includeFiles']) ??
          activeRegistry?.includeFiles,
      excludeFiles: _stringListOrNull(json['excludeFiles']) ??
          activeRegistry?.excludeFiles,
      pathAliases: (json['pathAliases'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      platformTargets: (json['platformTargets'] as Map?)?.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as Map).map(
            (innerKey, innerValue) =>
                MapEntry(innerKey.toString(), innerValue.toString()),
          ),
        ),
      ),
      defaultNamespace: resolvedNamespace,
      registries: parsedRegistries,
      installMode: _normalizeInstallMode(json['installMode']),
    );
  }

  /// `copy` unless the document says `package` (anything else falls back).
  static String _normalizeInstallMode(Object? raw) {
    final value = raw?.toString().trim();
    return value == installModePackage ? installModePackage : installModeCopy;
  }

  /// Effective install mode (`copy` when unset).
  String get effectiveInstallMode => installMode ?? installModeCopy;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'defaultNamespace': effectiveDefaultNamespace,
    };
    void add(String key, Object? value) {
      if (value != null) {
        json[key] = value;
      }
    }

    add('classPrefix', classPrefix);
    add('themeId', themeId);
    add('registryMode', registryMode);
    add('registriesPath', registriesPath);
    add('registryPath', registryPath);
    add('registryUrl', registryUrl);
    add('installPath', installPath);
    add('sharedPath', sharedPath);
    add('includeReadme', includeReadme);
    add('includeMeta', includeMeta);
    add('checkUpdates', checkUpdates);
    add('includePreview', includePreview);
    add('includeFiles', includeFiles);
    add('excludeFiles', excludeFiles);
    add('pathAliases', pathAliases);
    add('platformTargets', platformTargets);
    add('installMode', installMode);
    if (registries != null) {
      json['registries'] = registries!.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
    }
    return json;
  }

  bool get hasRegistries => registries != null && registries!.isNotEmpty;

  String get effectiveDefaultNamespace {
    return _resolveDefaultNamespace(
      requestedDefaultNamespace: defaultNamespace,
      registries: registries,
    );
  }

  RegistryConfigEntry? registryConfig([String? namespace]) {
    final key = namespace?.trim().isNotEmpty == true
        ? namespace!.trim()
        : effectiveDefaultNamespace;
    return registries?[key];
  }

  DashcnConfig withRegistry(String namespace, RegistryConfigEntry entry) {
    final next = Map<String, RegistryConfigEntry>.from(registries ?? const {});
    next[namespace] = entry;
    final defaultNs = defaultNamespace ?? namespace;
    final active = next[defaultNs];
    return copyWith(
      defaultNamespace: defaultNs,
      registries: next,
      registryMode: active?.registryMode ?? registryMode,
      registriesPath: registriesPath,
      registryPath: active?.registryPath ?? registryPath,
      registryUrl: active?.registryUrl ?? active?.baseUrl ?? registryUrl,
      installPath: active?.installPath ?? installPath,
      sharedPath: active?.sharedPath ?? sharedPath,
      includeReadme: active?.includeReadme ?? includeReadme,
      includeMeta: active?.includeMeta ?? includeMeta,
      includePreview: active?.includePreview ?? includePreview,
      includeFiles: active?.includeFiles ?? includeFiles,
      excludeFiles: active?.excludeFiles ?? excludeFiles,
    );
  }

  static File configFile(String targetDir) {
    return File(p.join(targetDir, '.dashcn', 'config.json'));
  }

  static Future<DashcnConfig> load(
    String targetDir, {
    String defaultNamespace = fallbackDefaultNamespace,
  }) async {
    final file = configFile(targetDir);
    if (!await file.exists()) {
      return const DashcnConfig();
    }
    final content = await file.readAsString();
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('config root must be a JSON object');
      }
      final normalized = _normalizeConfigShape(
        decoded,
        defaultNamespace: defaultNamespace,
      );
      final config = DashcnConfig.fromJson(normalized);
      if (_needsConfigNormalization(decoded)) {
        await save(targetDir, config);
      }
      return config;
    } catch (error) {
      throw DashcnConfigLoadException(path: file.path, cause: error);
    }
  }

  static Future<void> save(String targetDir, DashcnConfig config) async {
    final file = File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: targetDir,
        destinationRelativePath: p.join('.dashcn', 'config.json'),
      ),
    );
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  DashcnConfig copyWith({
    Object? classPrefix = _copyWithUnset,
    Object? themeId = _copyWithUnset,
    Object? registryMode = _copyWithUnset,
    Object? registriesPath = _copyWithUnset,
    Object? registryPath = _copyWithUnset,
    Object? registryUrl = _copyWithUnset,
    Object? installPath = _copyWithUnset,
    Object? sharedPath = _copyWithUnset,
    Object? includeReadme = _copyWithUnset,
    Object? includeMeta = _copyWithUnset,
    Object? includePreview = _copyWithUnset,
    Object? includeFiles = _copyWithUnset,
    Object? excludeFiles = _copyWithUnset,
    Object? checkUpdates = _copyWithUnset,
    Object? pathAliases = _copyWithUnset,
    Object? platformTargets = _copyWithUnset,
    Object? defaultNamespace = _copyWithUnset,
    Object? registries = _copyWithUnset,
    Object? installMode = _copyWithUnset,
  }) {
    return DashcnConfig(
      classPrefix: _copyWithValue(classPrefix, this.classPrefix),
      themeId: _copyWithValue(themeId, this.themeId),
      registryMode: _copyWithValue(registryMode, this.registryMode),
      registriesPath: _copyWithValue(registriesPath, this.registriesPath),
      registryPath: _copyWithValue(registryPath, this.registryPath),
      registryUrl: _copyWithValue(registryUrl, this.registryUrl),
      installPath: _copyWithValue(installPath, this.installPath),
      sharedPath: _copyWithValue(sharedPath, this.sharedPath),
      includeReadme: _copyWithValue(includeReadme, this.includeReadme),
      includeMeta: _copyWithValue(includeMeta, this.includeMeta),
      includePreview: _copyWithValue(includePreview, this.includePreview),
      includeFiles: _copyWithValue(includeFiles, this.includeFiles),
      excludeFiles: _copyWithValue(excludeFiles, this.excludeFiles),
      checkUpdates: _copyWithValue(checkUpdates, this.checkUpdates),
      pathAliases: _copyWithValue(pathAliases, this.pathAliases),
      platformTargets: _copyWithValue(platformTargets, this.platformTargets),
      defaultNamespace: _copyWithValue(defaultNamespace, this.defaultNamespace),
      registries: _copyWithValue(registries, this.registries),
      installMode: _copyWithValue(installMode, this.installMode),
    );
  }

  static Map<String, RegistryConfigEntry>? _parseRegistries(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final parsed = <String, RegistryConfigEntry>{};
    raw.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsed[key.toString()] = RegistryConfigEntry.fromJson(value);
        return;
      }
      if (value is Map) {
        parsed[key.toString()] = RegistryConfigEntry.fromJson(
          value.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    });
    return parsed.isEmpty ? null : parsed;
  }

  static String _resolveDefaultNamespace({
    required String? requestedDefaultNamespace,
    required Map<String, RegistryConfigEntry>? registries,
  }) {
    final trimmed = requestedDefaultNamespace?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    if (registries != null && registries.isNotEmpty) {
      return registries.keys.first;
    }
    return fallbackDefaultNamespace;
  }

  static bool _needsConfigNormalization(Map<String, dynamic> raw) {
    if (raw['registries'] is Map) {
      return false;
    }
    return raw.containsKey('installPath') ||
        raw.containsKey('sharedPath') ||
        raw.containsKey('registryMode') ||
        raw.containsKey('registryPath') ||
        raw.containsKey('registryUrl');
  }

  static Map<String, dynamic> _normalizeConfigShape(
    Map<String, dynamic> raw, {
    required String defaultNamespace,
  }) {
    if (!_needsConfigNormalization(raw)) {
      return raw;
    }

    final namespace =
        (raw['defaultNamespace'] as String?)?.trim().isNotEmpty == true
            ? (raw['defaultNamespace'] as String).trim()
            : defaultNamespace;

    final normalized = Map<String, dynamic>.from(raw);
    final registries = <String, dynamic>{
      namespace: {
        'registryMode': raw['registryMode'],
        'registryPath': raw['registryPath'],
        'registryUrl': raw['registryUrl'],
        'installPath': raw['installPath'],
        'sharedPath': raw['sharedPath'],
        'includeReadme': raw['includeReadme'],
        'includeMeta': raw['includeMeta'],
        'includePreview': raw['includePreview'],
        'includeFiles': raw['includeFiles'],
        'excludeFiles': raw['excludeFiles'],
        'enabled': true,
      },
    };
    normalized['defaultNamespace'] = namespace;
    normalized['registries'] = registries;
    return normalized;
  }
}

T? _copyWithValue<T>(Object? value, T? current) {
  if (identical(value, _copyWithUnset)) {
    return current;
  }
  return value as T?;
}

List<String>? _stringListOrNull(dynamic raw) {
  if (raw is! List) {
    return null;
  }
  final values = raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
  return values.isEmpty ? null : values;
}

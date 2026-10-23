import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/locale/locale_codegen.dart';
import 'package:dashcn_cli/src/application/services/locale/locale_tables.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Outcome of one locale sync: the keys every locale now carries and the
/// project-relative files that changed.
class LocaleSyncReport {
  const LocaleSyncReport({
    required this.keys,
    required this.locales,
    required this.written,
    required this.removed,
  });

  /// Sorted locale keys the installed components need.
  final List<String> keys;

  /// Sorted installed locales, English base first when present.
  final List<String> locales;

  /// Project-relative paths written (locale files, barrel, state, delegate).
  final List<String> written;

  /// Project-relative paths deleted (`locale remove` only).
  final List<String> removed;

  Map<String, dynamic> toJson() => {
        'keys': keys,
        'keyCount': keys.length,
        'locales': locales,
        'written': written,
        'removed': removed,
      };
}

/// One row of `dashcn locale list`.
class InstalledLocaleEntry {
  const InstalledLocaleEntry({
    required this.code,
    required this.direction,
    required this.keyCount,
    required this.installed,
  });

  final String code;
  final String direction;
  final int keyCount;
  final bool installed;

  Map<String, dynamic> toJson() => {
        'code': code,
        'direction': direction,
        'keys': keyCount,
        'installed': installed,
      };
}

/// Installs component translations into `<projectRoot>/dashcn_locales/`.
///
/// The CLI port of the kit's `tool/locale.dart`: after `dashcn add` copies
/// the sources, this syncs the locale files for every locale the project
/// already has (English base always); `dashcn locale add <code>` installs one
/// more language for every installed component. Only the keys the installed
/// components need are overridden; everything else falls back to English.
/// Only changed files are written, so repeating a command is a no-op.
///
/// The needed keys are the union of `localizationKeys` over the components
/// the lock records plus the components recorded in `dashcn_locales/state.json`
/// (the same union the kit tool computes, so the two interoperate).
class LocaleSyncService {
  LocaleSyncService({
    required this.source,
    required this.manifest,
    required this.projectRoot,
    required this.installRoot,
  });

  final RegistrySource source;
  final RegistryManifest manifest;

  /// Absolute project root.
  final String projectRoot;

  /// Project-relative install root, e.g. `lib/ui/dashcn`.
  final String installRoot;

  LocaleTables? _tables;

  /// False for registries that predate the locale installer (no component
  /// records `localizationKeys`): every entry point treats that as "locale
  /// support off" and leaves the project untouched.
  bool get isSupported => manifest.hasLocalizationKeys;

  void _requireSupported() {
    if (!isSupported) {
      throw const LocaleNotSupportedException(
        'This registry provides no component translations: no component '
        'records localizationKeys. Upgrade the registry to install locales.',
      );
    }
  }

  Future<LocaleTables> _tablesOrThrow() async {
    final cached = _tables;
    if (cached != null) {
      return cached;
    }
    _requireSupported();
    final loaded = await loadLocaleTables(source);
    _tables = loaded;
    return loaded;
  }

  /// Brings `dashcn_locales/` in line after an install: records [components],
  /// forgets [forgetComponents] (ids that left the project, e.g. via
  /// `dashcn remove`) and refreshes every installed locale. Returns `null`
  /// when the registry has no locale support (the caller skips silently).
  Future<LocaleSyncReport?> refreshAfterInstall({
    Set<String> components = const {},
    Set<String> forgetComponents = const {},
  }) async {
    if (!isSupported) {
      return null;
    }
    final tables = await _tablesOrThrow();
    final state = _readState();
    return _sync(
      tables,
      recorded: {...state.components, ...components}
        ..removeAll(forgetComponents),
      locales: {...state.locales, kLocaleBase},
    );
  }

  /// Installs [code] for every component in the project.
  ///
  /// Idempotent: nothing is written when the project already has it.
  Future<LocaleSyncReport> addLocale(String code) async {
    final tables = await _tablesOrThrow();
    tables.checkCode(code);
    final state = _readState();
    return _sync(
      tables,
      recorded: state.components,
      locales: {...state.locales, code},
    );
  }

  /// Removes [code] from the project and deletes its locale file.
  ///
  /// Idempotent: nothing is written when the project does not have it. The
  /// English base cannot be removed while components are installed.
  Future<LocaleSyncReport> removeLocale(String code) async {
    final tables = await _tablesOrThrow();
    tables.checkCode(code);
    final state = _readState();
    final lockComponents = await _lockedComponentIds();
    if (code == kLocaleBase &&
        {...state.components, ...lockComponents}.isNotEmpty) {
      throw const LocaleNotSupportedException(
        'Cannot remove the English base locale while components are '
        'installed.',
      );
    }
    final locales = {...state.locales}..remove(code);
    // The base is implied by an empty locale set: keep the file layout stable
    // and let the next install re-add it.
    final report = await _sync(
      tables,
      recorded: state.components,
      locales: locales,
    );
    final target = p.join(kLocalesDirName, localeFileName(code));
    final file = File(p.join(projectRoot, target));
    var removed = report.removed;
    if (await file.exists()) {
      await file.delete();
      removed = [...removed, target];
    }
    return LocaleSyncReport(
      keys: report.keys,
      locales: report.locales,
      written: report.written,
      removed: removed,
    );
  }

  /// Every locale the registry ships, flagged with whether the project has it.
  Future<List<InstalledLocaleEntry>> listLocales() async {
    final tables = await _tablesOrThrow();
    final installed = _readState().locales;
    return [
      InstalledLocaleEntry(
        code: kLocaleBase,
        direction: 'ltr',
        keyCount: tables.keyCount,
        installed: installed.contains(kLocaleBase),
      ),
      for (final code in tables.supportedCodes)
        InstalledLocaleEntry(
          code: code,
          direction: tables.locales[code]!['direction'] as String? ?? 'ltr',
          keyCount: (tables.locales[code]!['overrides'] as Map).length,
          installed: installed.contains(code),
        ),
    ];
  }

  /// The keys [componentId] needs, from the registry manifest. Throws for an
  /// unknown component.
  List<String> componentKeys(String componentId) {
    final component = manifest.components[componentId];
    if (component == null) {
      final known = manifest.components.keys.toList()..sort();
      throw UnknownLocaleComponentException(componentId, known);
    }
    return component.localizationKeys;
  }

  Future<LocaleSyncReport> _sync(
    LocaleTables tables, {
    required Set<String> recorded,
    required Set<String> locales,
  }) async {
    final keys = <String>{};
    final components = manifest.components;
    for (final component in {...recorded, ...await _lockedComponentIds()}) {
      if (components.containsKey(component)) {
        keys.addAll(componentKeys(component));
      }
    }
    final written = <String>[];
    final dir = Directory(p.join(projectRoot, kLocalesDirName))
      ..createSync(recursive: true);
    final sorted = locales.toList()..sort();
    final import = _localizationsImport();
    for (final code in sorted) {
      final target = p.join(kLocalesDirName, localeFileName(code));
      final content = generateLocaleFile(
        tables: tables,
        code: code,
        keys: keys,
        localizationsImport: import,
      );
      if (_writeIfChanged(File(p.join(projectRoot, target)), content)) {
        written.add(target);
      }
    }
    final barrelTarget = p.join(kLocalesDirName, 'dashcn_locales.dart');
    if (_writeIfChanged(
      File(p.join(projectRoot, barrelTarget)),
      generateLocaleBarrel(codes: sorted, localizationsImport: import),
    )) {
      written.add(barrelTarget);
    }
    final stateTarget = p.join(kLocalesDirName, kLocaleStateFileName);
    if (_writeIfChanged(
      File(p.join(projectRoot, stateTarget)),
      _stateJson(recorded, locales),
    )) {
      written.add(stateTarget);
    }
    final delegateTarget = p.join(
      installRoot,
      'primitives',
      'localizations',
      'localizations_delegate.dart',
    );
    if (_writeIfChanged(
      File(p.join(projectRoot, p.normalize(delegateTarget))),
      generateSlimDelegate(),
    )) {
      written.add(p.normalize(delegateTarget));
    }
    // Prune locale files for locales the project no longer has (a stale file
    // from a hand-edited state.json must not linger).
    final removed = <String>[];
    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is! File) {
          continue;
        }
        final name = p.basename(entity.path);
        if (!_isGeneratedLocaleFile(name, sorted)) {
          continue;
        }
        await entity.delete();
        removed.add(p.join(kLocalesDirName, name));
      }
    }
    return LocaleSyncReport(
      keys: keys.toList()..sort(),
      locales: sorted,
      written: written..sort(),
      removed: removed..sort(),
    );
  }

  bool _isGeneratedLocaleFile(String name, List<String> locales) {
    if (!name.startsWith('dashcn_locale_') || !name.endsWith('.dart')) {
      return false;
    }
    final wanted = {for (final code in locales) localeFileName(code)};
    return !wanted.contains(name);
  }

  /// Import of the installed `localizations.dart` used by every generated
  /// file: a `package:` import of the app's own package when the install
  /// root sits under `lib/` (so `flutter analyze` stays lint-clean),
  /// otherwise a relative path from `dashcn_locales/`.
  String _localizationsImport() {
    final packageName = _appPackageName();
    final posixRoot = installRoot.replaceAll('\\', '/');
    final String? underLib = posixRoot == 'lib'
        ? ''
        : posixRoot.startsWith('lib/')
            ? posixRoot.substring('lib/'.length)
            : null;
    if (packageName != null && underLib != null) {
      final inside = underLib.isEmpty
          ? 'primitives/localizations/localizations.dart'
          : '$underLib/primitives/localizations/localizations.dart';
      return 'package:$packageName/$inside';
    }
    final target = p.join(
      installRoot,
      'primitives',
      'localizations',
      'localizations.dart',
    );
    final relative = p.relative(target, from: kLocalesDirName);
    return relative.replaceAll('\\', '/');
  }

  /// The app's package name from `pubspec.yaml`, or `null` when it cannot be
  /// read (the generator falls back to a relative import).
  String? _appPackageName() {
    try {
      final file = File(p.join(projectRoot, 'pubspec.yaml'));
      if (!file.existsSync()) {
        return null;
      }
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) {
        return null;
      }
      final name = doc['name'];
      return name is String && name.isNotEmpty ? name : null;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _lockedComponentIds() async {
    final lock = await LockRepository(projectRoot).load();
    return lock.componentIds.toSet();
  }

  _LocaleProjectState _readState() {
    final file =
        File(p.join(projectRoot, kLocalesDirName, kLocaleStateFileName));
    if (!file.existsSync()) {
      return const _LocaleProjectState(
        components: {},
        locales: {},
      );
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return _LocaleProjectState(
      components: _stringSet(json['components']),
      locales: _stringSet(json['locales']),
    );
  }

  static Set<String> _stringSet(Object? value) {
    if (value is! List) {
      return {};
    }
    return value.whereType<String>().toSet();
  }

  static String _stateJson(Set<String> components, Set<String> locales) {
    final sortedComponents = components.toList()..sort();
    final sortedLocales = locales.toList()..sort();
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert(<String, Object>{
      'components': sortedComponents,
      'locales': sortedLocales,
    });
    return '$json\n';
  }

  static bool _writeIfChanged(File file, String content) {
    if (file.existsSync() && file.readAsStringSync() == content) {
      return false;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return true;
  }
}

class _LocaleProjectState {
  const _LocaleProjectState({required this.components, required this.locales});

  final Set<String> components;
  final Set<String> locales;
}

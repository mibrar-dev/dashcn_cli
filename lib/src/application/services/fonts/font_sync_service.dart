import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/pubspec/pubspec_editor.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_fonts.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:dashcn_cli/src/theme_interop/google_fonts_catalogue.dart';
import 'package:path/path.dart' as p;

/// The registry ships no `fonts` map: `fonts` commands cannot run against it.
class FontNotSupportedException implements Exception {
  const FontNotSupportedException(this.message);

  final String message;

  @override
  String toString() => 'FontNotSupportedException: $message';
}

/// No font pack with this id exists in the registry's `fonts` map.
class UnknownFontException implements Exception {
  UnknownFontException(this.id, Iterable<String> known)
      : known = known.toList()..sort();

  final String id;
  final List<String> known;

  @override
  String toString() => known.isEmpty
      ? 'Unknown font "$id".'
      : 'Unknown font "$id". Known fonts: ${known.join(', ')}.';
}

/// The project has no `pubspec.yaml`, so no font block or dependency can be
/// merged.
class FontPubspecMissingException implements Exception {
  const FontPubspecMissingException(this.message);

  final String message;

  @override
  String toString() => 'FontPubspecMissingException: $message';
}

/// A font file the `fonts` map declares is missing from the registry source.
class FontFileMissingException implements Exception {
  const FontFileMissingException(this.relPath);

  final String relPath;

  @override
  String toString() =>
      'Registry file "$relPath" is declared by the fonts map but missing '
      'from the registry source.';
}

/// Outcome of one `fonts add`: the families installed and the
/// project-relative files that changed.
class FontSyncReport {
  const FontSyncReport({
    required this.id,
    required this.google,
    required this.families,
    required this.written,
  });

  /// The font pack id that was installed.
  final String id;

  /// True for the `--google` opt-in path (dependency only, no files).
  final bool google;

  /// Sorted family names the pack provides.
  final List<String> families;

  /// Project-relative paths written (font files, pubspec.yaml, state file).
  final List<String> written;

  Map<String, dynamic> toJson() => {
        'id': id,
        'google': google,
        'families': families,
        'written': written,
      };
}

/// One row of `dashcn fonts list`.
class InstalledFontEntry {
  const InstalledFontEntry({
    required this.id,
    required this.families,
    required this.installed,
  });

  final String id;
  final List<String> families;
  final bool installed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'families': families,
        'installed': installed,
      };
}

/// Installs font packs from the registry's `fonts` map into
/// `<projectRoot>/assets/fonts/`.
///
/// `addFont` copies each declared file through the shared [RegistrySource]
/// bytes path (binary-safe, same mechanism the installer uses for other
/// files) and merges the `flutter: fonts:` pubspec entries with the
/// line-preserving [PubspecEditor]. Only changed files are written, so
/// repeating a command is a no-op. The `--google` opt-in path instead adds
/// the `google_fonts` dependency and copies nothing.
///
/// Installed ids are recorded in `assets/fonts/state.json`, the way locale
/// state is recorded in `dashcn_locales/state.json`.
class FontSyncService {
  FontSyncService({
    required this.source,
    required this.manifest,
    required this.projectRoot,
  });

  final RegistrySource source;
  final RegistryManifest manifest;

  /// Absolute project root.
  final String projectRoot;

  /// Project-relative directory installed font files land in.
  static const String fontsDirName = 'assets/fonts';

  /// Project-relative state file recording the installed font ids.
  static const String stateFileName = 'state.json';

  /// False for registries that predate the fonts map: every entry point
  /// treats that as "fonts support off" and leaves the project untouched.
  bool get isSupported => manifest.fonts.isNotEmpty;

  void _requireSupported() {
    if (!isSupported) {
      throw const FontNotSupportedException(
        'This registry provides no fonts: no `fonts` map in '
        'manifests/registry.json. Upgrade the registry to install fonts.',
      );
    }
  }

  RegistryFontPack _packOrThrow(String id) {
    _requireSupported();
    final pack = manifest.fonts[id];
    if (pack == null) {
      throw UnknownFontException(id, manifest.fonts.keys);
    }
    return pack;
  }

  /// Every font pack the registry ships, flagged with whether the project
  /// has it.
  Future<List<InstalledFontEntry>> listFonts() async {
    _requireSupported();
    final installed = _readState();
    return [
      for (final entry in manifest.fonts.entries)
        InstalledFontEntry(
          id: entry.key,
          families: entry.value.familyNames,
          installed: installed.contains(entry.key),
        ),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Installs the [id] pack.
  ///
  /// Idempotent: nothing is written when the project already has it. With
  /// [google], only the `google_fonts` dependency is added and no font file
  /// is copied.
  Future<FontSyncReport> addFont(String id, {bool google = false}) async {
    final pack = _packOrThrow(id);
    if (google) {
      return _addGoogle(id, pack);
    }
    return _addLocal(id, pack);
  }

  Future<FontSyncReport> _addGoogle(String id, RegistryFontPack pack) async {
    final written = <String>[];
    if (_addDependency(kGoogleFontsPackageName, kGoogleFontsVersionPin)) {
      written.add('pubspec.yaml');
    }
    if (_writeState({..._readState(), id})) {
      written.add(p.join(fontsDirName, stateFileName).replaceAll('\\', '/'));
    }
    return FontSyncReport(
      id: id,
      google: true,
      families: pack.familyNames,
      written: written..sort(),
    );
  }

  Future<FontSyncReport> _addLocal(String id, RegistryFontPack pack) async {
    final written = <String>[];
    final families = <PubspecFontFamily>[];
    for (final family in pack.families) {
      final assets = <PubspecFontAsset>[];
      for (final file in family.files) {
        final bytes = await source.readBytes(file.path);
        if (bytes == null) {
          throw FontFileMissingException(file.path);
        }
        final target =
            p.join(fontsDirName, p.basename(file.path)).replaceAll('\\', '/');
        if (_writeBytesIfChanged(target, bytes)) {
          written.add(target);
        }
        assets.add(PubspecFontAsset(
          target,
          weight: file.weight,
          style: file.style,
        ));
      }
      assets.sort((a, b) => a.asset.compareTo(b.asset));
      families.add(PubspecFontFamily(family.family, assets));
    }
    families.sort((a, b) => a.family.compareTo(b.family));
    if (_addFlutterFonts(families)) {
      written.add('pubspec.yaml');
    }
    if (_writeState({..._readState(), id})) {
      written.add(p.join(fontsDirName, stateFileName).replaceAll('\\', '/'));
    }
    return FontSyncReport(
      id: id,
      google: false,
      families: pack.familyNames,
      written: written..sort(),
    );
  }

  /// Merges one dependency into the project's pubspec; false when nothing
  /// changed. Throws [FontPubspecMissingException] without a pubspec.
  bool _addDependency(String package, String constraint) {
    final file = _pubspecOrThrow();
    final editor = PubspecEditor(file.readAsStringSync());
    editor.addDependencies({package: constraint});
    return _writeTextIfChanged(file, editor.toString());
  }

  /// Merges the `flutter: fonts:` entries; false when nothing changed.
  bool _addFlutterFonts(List<PubspecFontFamily> families) {
    final file = _pubspecOrThrow();
    final editor = PubspecEditor(file.readAsStringSync());
    editor.addFlutterFonts(families);
    return _writeTextIfChanged(file, editor.toString());
  }

  File _pubspecOrThrow() {
    final file = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!file.existsSync()) {
      throw const FontPubspecMissingException(
        'pubspec.yaml not found in project root; cannot install fonts.',
      );
    }
    return file;
  }

  Set<String> _readState() {
    final file = File(p.join(projectRoot, fontsDirName, stateFileName));
    if (!file.existsSync()) {
      return {};
    }
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map) {
      return {};
    }
    final fonts = json['fonts'];
    if (fonts is! List) {
      return {};
    }
    return fonts.whereType<String>().toSet();
  }

  bool _writeState(Set<String> ids) {
    final sorted = ids.toList()..sort();
    const encoder = JsonEncoder.withIndent('  ');
    final json = encoder.convert(<String, Object>{'fonts': sorted});
    return _writeTextIfChanged(
      File(p.join(projectRoot, fontsDirName, stateFileName)),
      '$json\n',
    );
  }

  bool _writeBytesIfChanged(String target, List<int> bytes) {
    final absolute = ProjectPathGuard.resolveSafeWritePath(
      projectRoot: projectRoot,
      destinationRelativePath: target,
    );
    final file = File(absolute);
    if (file.existsSync() && _bytesEqual(file.readAsBytesSync(), bytes)) {
      return false;
    }
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
    return true;
  }

  bool _writeTextIfChanged(File file, String content) {
    if (file.existsSync() && file.readAsStringSync() == content) {
      return false;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return true;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

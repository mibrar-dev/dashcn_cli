import 'dart:io';

import 'package:dashcn_cli/src/registry/manifest/manifest_block_checks.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_component_checks.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_flow_checks.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_theme_checks.dart';
import 'package:dashcn_cli/src/registry/schema_validation_result.dart';
import 'package:path/path.dart' as p;

/// Validates parsed registry manifest JSON (`manifests/registry.json`)
/// against the v2 rules (see `rearch/reports/registry_manifest.v2.schema.json`
/// and `rearch/reports/P5_CLI_PLAN.md` §6.1):
///
/// - `schemaVersion` must be 2; required top-level keys present, no unknown keys.
/// - Layer unit / component / theme-preset ids match the v2 id pattern.
/// - `files` / `userOwned` / `entry` / preset `file` are relPaths (forward
///   slashes, no leading `./` or `/`, `.dart`/`.json`/`.md` suffix) and live
///   under the directory their owner implies. `.md` is allowed because a block
///   `docs` entry and a block README digest are markdown.
/// - `deps` blocks have exactly the documented keys and every referenced id
///   exists in the corresponding map (deps closure). Primitive→primitive
///   cycles are LEGAL (plan §9.7): the real graph has cycles
///   (`clickable ↔ clickable_state`, the overlay/popover cluster), so closure
///   resolution is cycle-tolerant and the validator must not reject them.
/// - `fileHashes` values are lowercase sha256 hex and cover every copyable
///   file declared by the manifest. `themes/*.json` are consumed to generate
///   `theme/app_theme.dart`, never copied, so they are not required here.
/// - When [registryRoot] is given, every listed file must exist on disk.
///
/// The `blocks` map is OPTIONAL: a registry that predates the blocks layer
/// (P6-B1) simply has none, and every command treats that as "no blocks".
///
/// The component / block / theme-preset / fileHashes block checks live in
/// `ManifestComponentChecks` (same directory) to keep this file focused.
class ManifestSchemaValidator {
  /// v2 id pattern: a layer unit stem (`data`), a folder name (`form_core`),
  /// a nested stem (`icons/lucide_icons`) or a hyphenated block id
  /// (`login-01`).
  static final RegExp idPattern = RegExp(
    r'^[a-z0-9][a-z0-9_\-]*(/[a-z0-9][a-z0-9_\-]*)?$',
  );

  /// v2 relPath pattern, identical to the JSON Schema (backslashes are
  /// schema-allowed but rejected with a clearer message by the checks).
  /// `.tmpl` is allowed for starter templates (P9-6); components, blocks
  /// and flows still emit only `.dart`/`.json`/`.md`.
  static final RegExp relPathPattern = RegExp(
    r'^[A-Za-z0-9_][A-Za-z0-9_./\\-]*\.(dart|json|md|tmpl)$',
  );

  static const List<String> _requiredKeys = [
    'schemaVersion',
    'registry',
    'install',
    'foundation',
    'theme',
    'primitives',
    'components',
    'themes',
    'fileHashes',
  ];

  static const Set<String> _allowedTopLevel = {
    ..._requiredKeys,
    'blocks',
    'flows',
    'fonts',
    'starters',
    r'$schema',
  };

  /// Validates [data] (the decoded `registry.json`). Pass [registryRoot] to
  /// additionally verify that every listed file exists on disk.
  static SchemaValidationResult validate(
    Map<String, dynamic> data, {
    String? registryRoot,
  }) {
    final errors = <String>[];

    if (data['schemaVersion'] != 2) {
      errors.add(
        'schemaVersion must be 2 (got ${data['schemaVersion']})',
      );
    }
    for (final key in _requiredKeys) {
      if (!data.containsKey(key)) {
        errors.add('missing required top-level key "$key"');
      }
    }
    for (final key in data.keys) {
      if (!_allowedTopLevel.contains(key)) {
        errors.add('unknown top-level key "$key"');
      }
    }

    _checkRegistryInfo(data['registry'], errors);
    _checkInstall(data['install'], errors);
    final foundation = _checkUnitMap(data['foundation'], 'foundation', errors);
    final theme = _checkUnitMap(data['theme'], 'theme', errors);
    final primitives = _checkPrimitiveMap(data['primitives'], errors);
    final components = ManifestComponentChecks.checkComponents(
      data['components'],
      foundation,
      theme,
      primitives,
      errors,
    );
    final blocks = ManifestBlockChecks.checkBlocks(
      data['blocks'],
      foundation,
      theme,
      primitives,
      components,
      errors,
    );
    final flows = ManifestFlowChecks.checkFlows(
      data['flows'],
      foundation,
      theme,
      primitives,
      components,
      blocks,
      errors,
    );
    ManifestThemeChecks.checkThemes(
      data['themes'],
      errors,
    );
    final fontFiles = checkFonts(data['fonts'], errors);
    final declaredFiles = _declaredFiles(
      foundation: foundation,
      theme: theme,
      primitives: primitives,
      components: components,
      blocks: blocks,
      flows: flows,
    );
    ManifestComponentChecks.checkFileHashes(
      data['fileHashes'],
      declaredFiles,
      errors,
    );

    if (registryRoot != null && registryRoot.isNotEmpty) {
      _checkFilesOnDisk(registryRoot, declaredFiles, errors);
      _checkFilesOnDisk(registryRoot, fontFiles, errors);
    }

    return SchemaValidationResult(isValid: errors.isEmpty, errors: errors);
  }

  static void _checkRegistryInfo(Object? raw, List<String> errors) {
    if (raw is! Map) {
      if (raw != null) errors.add('registry: expected an object');
      return;
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    for (final key in json.keys) {
      if (!{'name', 'version', 'ref', 'generatedAt'}.contains(key)) {
        errors.add('registry: unknown key "$key"');
      }
    }
    for (final key in ['name', 'version']) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        errors.add('registry.$key: must be a non-empty string');
      }
    }
  }

  static void _checkInstall(Object? raw, List<String> errors) {
    if (raw is! Map) {
      if (raw != null) errors.add('install: expected an object');
      return;
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    for (final key in json.keys) {
      if (!{
        'root',
        'componentsDir',
        'blocksDir',
        'flowsDir',
        'layerDirs',
        'userOwnedSuffix'
      }.contains(key)) {
        errors.add('install: unknown key "$key"');
      }
    }
    final root = json['root'];
    if (root is! String || root.isEmpty) {
      errors.add('install.root: must be a non-empty string');
    }
    if (json['componentsDir'] != 'components') {
      errors.add('install.componentsDir: must be "components"');
    }
    if (json['blocksDir'] != null && json['blocksDir'] != 'blocks') {
      errors.add('install.blocksDir: must be "blocks"');
    }
    if (json['flowsDir'] != null && json['flowsDir'] != 'flows') {
      errors.add('install.flowsDir: must be "flows"');
    }
    final layerDirs = json['layerDirs'];
    if (layerDirs is! Map) {
      errors.add('install.layerDirs: expected an object');
    } else {
      final dirs =
          layerDirs.map((key, value) => MapEntry(key.toString(), value));
      for (final layer in ['foundation', 'theme', 'primitives']) {
        if (!dirs.containsKey(layer)) {
          errors.add('install.layerDirs: missing "$layer"');
        } else if (dirs[layer] != layer) {
          errors.add('install.layerDirs.$layer: must be "$layer"');
        }
      }
      for (final key in dirs.keys) {
        if (!{'foundation', 'theme', 'primitives'}.contains(key)) {
          errors.add('install.layerDirs: unknown key "$key"');
        }
      }
    }
    if (json['userOwnedSuffix'] != '_theme.dart') {
      errors.add('install.userOwnedSuffix: must be "_theme.dart"');
    }
  }

  /// Validates a foundation/theme unit map; returns id -> files.
  static Map<String, List<String>> _checkUnitMap(
    Object? raw,
    String layer,
    List<String> errors,
  ) {
    if (raw is! Map) {
      if (raw != null) errors.add('$layer: expected an object');
      return const {};
    }
    final result = <String, List<String>>{};
    raw.forEach((key, value) {
      final id = key.toString();
      if (!idPattern.hasMatch(id)) {
        errors.add('$layer.$id: invalid unit id');
      }
      if (value is! Map) {
        errors.add('$layer.$id: expected an object');
        return;
      }
      final json = value.map((k, v) => MapEntry(k.toString(), v));
      for (final k in json.keys) {
        if (!{'files', 'packages'}.contains(k)) {
          errors.add('$layer.$id: unknown key "$k"');
        }
      }
      final files = ManifestComponentChecks.checkFiles(
        json['files'],
        '$layer.$id.files',
        errors,
      );
      for (final file in files) {
        if (!file.startsWith('$layer/')) {
          errors.add('$layer.$id.files: "$file" is not under $layer/');
        }
      }
      ManifestComponentChecks.checkPackages(
        json['packages'],
        '$layer.$id.packages',
        errors,
      );
      result[id] = files;
    });
    return result;
  }

  /// Validates the primitive map (units + deps); returns id -> files.
  static Map<String, List<String>> _checkPrimitiveMap(
    Object? raw,
    List<String> errors,
  ) {
    if (raw is! Map) {
      if (raw != null) errors.add('primitives: expected an object');
      return const {};
    }
    final units = <String, Map<String, dynamic>>{};
    final unitFiles = <String, List<String>>{};
    raw.forEach((key, value) {
      final id = key.toString();
      if (!idPattern.hasMatch(id)) {
        errors.add('primitives.$id: invalid unit id');
      }
      if (value is! Map) {
        errors.add('primitives.$id: expected an object');
        return;
      }
      final json = value.map((k, v) => MapEntry(k.toString(), v));
      for (final k in json.keys) {
        if (!{'files', 'deps', 'packages'}.contains(k)) {
          errors.add('primitives.$id: unknown key "$k"');
        }
      }
      final files = ManifestComponentChecks.checkFiles(
        json['files'],
        'primitives.$id.files',
        errors,
      );
      for (final file in files) {
        if (!file.startsWith('primitives/')) {
          errors.add('primitives.$id.files: "$file" is not under primitives/');
        }
      }
      ManifestComponentChecks.checkPackages(
        json['packages'],
        'primitives.$id.packages',
        errors,
      );
      units[id] = json;
      unitFiles[id] = files;
    });

    for (final entry in units.entries) {
      final id = entry.key;
      final deps = entry.value['deps'];
      if (deps == null) {
        continue;
      }
      if (deps is! Map) {
        errors.add('primitives.$id.deps: expected an object');
        continue;
      }
      final depKeys = deps.map((k, v) => MapEntry(k.toString(), v));
      for (final key in depKeys.keys) {
        if (key != 'primitives') {
          errors.add('primitives.$id.deps: unknown key "$key"');
        }
      }
      final primitiveDeps = depKeys['primitives'];
      if (primitiveDeps is! List) {
        errors.add('primitives.$id.deps.primitives: expected an array');
        continue;
      }
      for (final dep in primitiveDeps) {
        if (dep is! String) {
          errors.add('primitives.$id.deps.primitives: entries must be strings');
        } else if (!units.containsKey(dep)) {
          errors.add(
            'primitives.$id.deps.primitives: unknown primitive id "$dep"',
          );
        }
      }
    }

    return unitFiles;
  }

  /// Validates the optional top-level `fonts` map; returns every font file
  /// path it declares. A manifest that predates the fonts map simply has
  /// none. Font files are installed only by `dashcn fonts add`, so they stay
  /// out of the copyable `declaredFiles` set (and out of `fileHashes`).
  static Set<String> checkFonts(Object? raw, List<String> errors) {
    final paths = <String>{};
    if (raw == null) {
      return paths;
    }
    if (raw is! Map) {
      errors.add('fonts: expected an object');
      return paths;
    }
    raw.forEach((key, value) {
      final id = key.toString();
      if (!idPattern.hasMatch(id)) {
        errors.add('fonts.$id: invalid font pack id');
      }
      if (value is! Map) {
        errors.add('fonts.$id: expected an object');
        return;
      }
      final json = value.map((k, v) => MapEntry(k.toString(), v));
      for (final k in json.keys) {
        if (k != 'families') {
          errors.add('fonts.$id: unknown key "$k"');
        }
      }
      final families = json['families'];
      if (families is! List || families.isEmpty) {
        errors.add('fonts.$id.families: expected a non-empty array');
        return;
      }
      for (var i = 0; i < families.length; i++) {
        final family = families[i];
        final where = 'fonts.$id.families[$i]';
        if (family is! Map) {
          errors.add('$where: expected an object');
          continue;
        }
        final familyJson = family.map((k, v) => MapEntry(k.toString(), v));
        for (final k in familyJson.keys) {
          if (k != 'family' && k != 'files') {
            errors.add('$where: unknown key "$k"');
          }
        }
        final name = familyJson['family'];
        if (name is! String || name.trim().isEmpty) {
          errors.add('$where.family: must be a non-empty string');
        }
        final files = familyJson['files'];
        if (files is! List || files.isEmpty) {
          errors.add('$where.files: expected a non-empty array');
          continue;
        }
        for (var j = 0; j < files.length; j++) {
          final file = files[j];
          final fileWhere = '$where.files[$j]';
          if (file is! Map) {
            errors.add('$fileWhere: expected an object');
            continue;
          }
          final fileJson = file.map((k, v) => MapEntry(k.toString(), v));
          for (final k in fileJson.keys) {
            if (k != 'path' && k != 'weight' && k != 'style') {
              errors.add('$fileWhere: unknown key "$k"');
            }
          }
          final path = fileJson['path'];
          if (path is! String || !_isFontPath(path)) {
            errors.add(
              '$fileWhere.path: must be a font file under assets/fonts/ '
              '(.otf, .ttf, .woff or .woff2)',
            );
          } else {
            paths.add(path);
          }
          final weight = fileJson['weight'];
          if (weight is! int || weight < 100 || weight > 900) {
            errors.add('$fileWhere.weight: must be an int from 100 to 900');
          }
          final style = fileJson['style'];
          if (style != null && style != 'italic' && style != 'normal') {
            errors.add('$fileWhere.style: must be "italic" or "normal"');
          }
        }
      }
    });
    return paths;
  }

  static bool _isFontPath(String path) {
    if (path.isEmpty ||
        path.startsWith('./') ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('..')) {
      return false;
    }
    if (!path.startsWith('assets/fonts/')) {
      return false;
    }
    final lower = path.toLowerCase();
    return lower.endsWith('.otf') ||
        lower.endsWith('.ttf') ||
        lower.endsWith('.woff') ||
        lower.endsWith('.woff2');
  }

  static Set<String> _declaredFiles({
    required Map<String, List<String>> foundation,
    required Map<String, List<String>> theme,
    required Map<String, List<String>> primitives,
    required Map<String, Map<String, dynamic>> components,
    required Map<String, Map<String, dynamic>> blocks,
    required Map<String, Map<String, dynamic>> flows,
  }) {
    final paths = <String>{};
    for (final files in [...foundation.values, ...theme.values]) {
      paths.addAll(files);
    }
    for (final files in primitives.values) {
      paths.addAll(files);
    }
    for (final entry in components.values) {
      final files = entry['files'];
      if (files is List) {
        paths.addAll(files.whereType<String>());
      }
      final userOwned = entry['userOwned'];
      if (userOwned is List) {
        paths.addAll(userOwned.whereType<String>());
      }
    }
    for (final entry in blocks.values) {
      final files = entry['files'];
      if (files is List) {
        paths.addAll(files.whereType<String>());
      }
    }
    for (final entry in flows.values) {
      final files = entry['files'];
      if (files is List) {
        paths.addAll(files.whereType<String>());
      }
    }
    return paths;
  }

  static void _checkFilesOnDisk(
    String registryRoot,
    Set<String> declaredFiles,
    List<String> errors,
  ) {
    for (final file in declaredFiles) {
      if (!File(p.join(registryRoot, file)).existsSync()) {
        errors.add('file not found in registry: "$file"');
      }
    }
  }
}

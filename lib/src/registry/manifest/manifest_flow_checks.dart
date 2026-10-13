import 'package:dashcn_cli/src/registry/manifest/manifest_component_checks.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_flow.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_schema_validator.dart';

/// Checks for the `flows` map of a registry manifest (P9-3b layer 5).
///
/// Internal helper for [ManifestSchemaValidator]; not part of the public
/// CLI API.
class ManifestFlowChecks {
  /// Keys of a `flows.<id>` entry (P9-3b). A flow has no `category` (the
  /// blocks taxonomy does not fit flows) and no `api`/`userOwned`/`theme`;
  /// it adds `type`, `screens` and `docs`, and its `deps` gains `blocks`.
  static const Set<String> _flowKeys = {
    'type',
    'name',
    'description',
    'viewport',
    'screens',
    'entry',
    'files',
    'docs',
    'deps',
    'tags',
    'install',
    'import',
    'packages',
  };

  /// Validates the `flows` map (registry layer 5); returns id -> parsed
  /// entry maps.
  ///
  /// Absent `flows` is valid: a registry written before the layer existed
  /// has none. A flow id must not collide with a component or block id (one
  /// shared address space for `add <id>`), its `files` are Dart only under
  /// `flows/<id>/`, and `deps.blocks` may name blocks only — never another
  /// flow.
  static Map<String, Map<String, dynamic>> checkFlows(
    Object? raw,
    Map<String, List<String>> foundation,
    Map<String, List<String>> theme,
    Map<String, List<String>> primitives,
    Map<String, Map<String, dynamic>> components,
    Map<String, Map<String, dynamic>> blocks,
    List<String> errors,
  ) {
    if (raw == null) {
      return const {};
    }
    if (raw is! Map) {
      errors.add('flows: expected an object');
      return const {};
    }
    final entries = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      final id = key.toString();
      if (value is! Map) {
        errors.add('flows.$id: expected an object');
        return;
      }
      entries[id] = value.map((k, v) => MapEntry(k.toString(), v));
    });

    for (final entry in entries.entries) {
      final id = entry.key;
      final json = entry.value;
      for (final k in json.keys) {
        if (!_flowKeys.contains(k)) {
          errors.add('flows.$id: unknown key "$k"');
        }
      }
      if (!ManifestSchemaValidator.idPattern.hasMatch(id)) {
        errors.add('flows.$id: invalid flow id');
      }
      if (components.containsKey(id) || blocks.containsKey(id)) {
        errors.add(
          'flows.$id: the id is already a component or block; all layers '
          'share one address space',
        );
      }
      if (json['type'] != 'flow') {
        errors.add('flows.$id.type: must be "flow"');
      }
      for (final field in ['name', 'description']) {
        final value = json[field];
        if (value is! String || value.isEmpty) {
          errors.add('flows.$id.$field: must be a non-empty string');
        }
      }
      final viewport = json['viewport'];
      if (viewport is! String || !manifestFlowViewports.contains(viewport)) {
        errors.add(
          'flows.$id.viewport: must be one of '
          '${manifestFlowViewports.join(', ')} (got "$viewport")',
        );
      }
      final screens = json['screens'];
      if (screens is! List || screens.isEmpty) {
        errors.add('flows.$id.screens: must be a non-empty list');
      }
      final entryPath = json['entry'];
      if (entryPath is! String ||
          !ManifestSchemaValidator.relPathPattern.hasMatch(entryPath)) {
        errors.add('flows.$id.entry: invalid relPath "$entryPath"');
      } else if (entryPath != 'flows/$id/flow.dart') {
        errors.add(
          'flows.$id.entry: "$entryPath" is not flows/$id/flow.dart',
        );
      }
      final files = ManifestComponentChecks.checkFiles(
          json['files'], 'flows.$id.files', errors);
      for (final file in files) {
        if (!file.startsWith('flows/$id/')) {
          errors.add('flows.$id.files: "$file" is not under flows/$id/');
        } else if (!file.endsWith('.dart')) {
          errors.add('flows.$id.files: "$file" is not a Dart file');
        }
      }
      final docs = ManifestComponentChecks.checkDocs(
          json['docs'], 'flows.$id.docs', errors);
      for (final doc in docs) {
        if (!doc.startsWith('flows/$id/')) {
          errors.add('flows.$id.docs: "$doc" is not under flows/$id/');
        }
      }
      _checkFlowDeps(
        json['deps'],
        id,
        foundation,
        theme,
        primitives,
        components,
        blocks,
        errors,
      );
      ManifestComponentChecks.checkTags(json['tags'], 'flows.$id.tags', errors);
      for (final key in const ['install', 'import']) {
        final value = json[key];
        if (value != null && value is! String) {
          errors.add('flows.$id.$key: must be a string');
        }
      }
      ManifestComponentChecks.checkPackages(
          json['packages'], 'flows.$id.packages', errors);
    }
    return entries;
  }

  static void _checkFlowDeps(
    Object? raw,
    String id,
    Map<String, List<String>> foundation,
    Map<String, List<String>> theme,
    Map<String, List<String>> primitives,
    Map<String, Map<String, dynamic>> components,
    Map<String, Map<String, dynamic>> blocks,
    List<String> errors,
  ) {
    if (raw is! Map) {
      return;
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    // The shared checker knows exactly the four component keys; validate
    // those through it and check `blocks` below.
    final withoutBlocks = Map<String, Object?>.of(json)..remove('blocks');
    ManifestComponentChecks.checkComponentDeps(
      withoutBlocks,
      id,
      foundation,
      theme,
      primitives,
      components,
      errors,
      label: 'flows',
    );
    for (final key in json.keys) {
      if (!const {'foundation', 'theme', 'primitives', 'components', 'blocks'}
          .contains(key)) {
        errors.add('flows.$id.deps: unknown key "$key"');
      }
    }
    if (!json.containsKey('blocks')) {
      errors.add('flows.$id.deps: missing required key "blocks"');
    }
    final blockDeps = json['blocks'];
    if (blockDeps == null) {
      errors.add('flows.$id.deps: missing "blocks"');
      return;
    }
    if (blockDeps is! List) {
      errors.add('flows.$id.deps.blocks: expected a list');
      return;
    }
    for (final dep in blockDeps) {
      final name = dep.toString();
      if (!blocks.containsKey(name)) {
        errors.add(
          'flows.$id.deps.blocks: unknown block "$name"',
        );
      } else if (name == id) {
        errors.add('flows.$id.deps.blocks: a flow cannot depend on itself');
      }
    }
  }
}

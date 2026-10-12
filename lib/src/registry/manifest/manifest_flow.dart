import 'package:dashcn_cli/src/registry/manifest/manifest_component.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_unit.dart';

/// Flow models from the generated `manifests/registry.json` `flows` map
/// (P9-3: registry layer 5, the dashcn "Flows" section).
///
/// A flow is a navigable mini-app (`auth-01`, `chat-01`) assembled from
/// components and blocks. It may import foundation/theme/primitives/
/// components/blocks and never another flow, which is why its `deps` block
/// has the four component keys plus `blocks`.
///
/// A flow has no `api` block and no user-owned file, like a block.

/// The viewports a flow may be designed for (docs hint only).
const Set<String> manifestFlowViewports = {'desktop', 'mobile'};

/// The `deps` block of a flow: the four component keys plus `blocks`.
class ManifestFlowDeps {
  final List<String> foundation;
  final List<String> theme;
  final List<String> primitives;
  final List<String> components;
  final List<String> blocks;

  const ManifestFlowDeps({
    this.foundation = const [],
    this.theme = const [],
    this.primitives = const [],
    this.components = const [],
    this.blocks = const [],
  });

  factory ManifestFlowDeps.fromJson(Map<String, dynamic> json) {
    return ManifestFlowDeps(
      foundation: ManifestUnit.pathListFromJson(json['foundation']),
      theme: ManifestUnit.pathListFromJson(json['theme']),
      primitives: ManifestUnit.pathListFromJson(json['primitives']),
      components: ManifestUnit.pathListFromJson(json['components']),
      blocks: ManifestUnit.pathListFromJson(json['blocks']),
    );
  }
}

/// One installable flow from the manifest `flows` map.
class ManifestFlow {
  const ManifestFlow({
    required this.id,
    required this.name,
    required this.description,
    required this.viewport,
    required this.screens,
    required this.entry,
    required this.files,
    required this.docs,
    required this.deps,
    required this.tags,
    this.install,
    this.import,
    this.packages = const [],
  });

  factory ManifestFlow.fromJson(String id, Map<String, dynamic> json) {
    return ManifestFlow(
      id: id,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      viewport: json['viewport'] as String? ?? '',
      screens: ManifestUnit.pathListFromJson(json['screens']),
      entry: json['entry'] as String? ?? '',
      files: ManifestUnit.pathListFromJson(json['files']),
      docs: ManifestUnit.pathListFromJson(json['docs']),
      deps: json['deps'] is Map
          ? ManifestFlowDeps.fromJson(
              (json['deps'] as Map)
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : const ManifestFlowDeps(),
      tags: ManifestUnit.pathListFromJson(json['tags']),
      install: json['install'] as String?,
      import: json['import'] as String?,
      packages: PackageRef.listFromJson(json['packages']),
    );
  }

  /// Registry flow id (== directory name), e.g. `auth-01`.
  final String id;

  final String name;

  final String description;

  /// `desktop` or `mobile` (see [manifestFlowViewports]).
  final String viewport;

  /// Display screen names from `meta.json` (`Sign in`, `Cart`, ...).
  final List<String> screens;

  /// Registry-relative entry file, `flows/<id>/flow.dart`.
  final String entry;

  /// Registry-relative Dart files the CLI copies into the app.
  final List<String> files;

  /// Registry-relative documentation files. Never copied into an app.
  final List<String> docs;

  final ManifestFlowDeps deps;

  final List<String> tags;

  /// The flow's own install command, e.g. `dashcn add flow:auth-01`.
  final String? install;

  /// The import line an app writes, `package:<your_app>/...` placeholder.
  final String? import;

  final List<PackageRef> packages;

  /// Every copyable registry relPath of this flow.
  List<String> get allFiles => files;

  /// Deps in the component shape (for lock records shared with blocks).
  ManifestComponentDeps get componentDeps => ManifestComponentDeps(
        foundation: foundationCopy(deps.foundation),
        theme: foundationCopy(deps.theme),
        primitives: foundationCopy(deps.primitives),
        components: foundationCopy(deps.components),
      );

  static List<String> foundationCopy(List<String> values) =>
      List<String>.of(values);
}

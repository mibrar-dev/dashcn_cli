import 'package:dashcn_cli/src/application/services/lockfile/lock_file_exception.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_install_state.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_json.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_layer.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_block.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_component.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_flow.dart';

/// The only supported lock format version.
const int kLockfileVersion = 2;

/// `dashcn.lock` lockfileVersion 2 (P5_CLI_PLAN.md §4).
///
/// Clean break: there is no v1 compatibility path and nothing is synthesised
/// from the deleted `.dashcn/components/*.json` files.
///
/// `blocks` records the P6-B2 layer 4 installs. A lock written before the
/// layer existed simply has none, so the field is absent-tolerant.
///
/// `flows` records the P9-3b layer 5 installs the same way.
class DashcnLock {
  const DashcnLock({
    this.lockfileVersion = kLockfileVersion,
    this.registry = const LockRegistry(),
    this.installRoot = '',
    this.theme,
    this.layers = const {},
    this.components = const [],
    this.blocks = const [],
    this.flows = const [],
  });

  /// Parses a lock document, rejecting anything that is not v2.
  factory DashcnLock.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final version = (json['lockfileVersion'] as num?)?.toInt();
    if (version != kLockfileVersion) {
      throw LockFileException(
        'Unsupported lockfileVersion ${version ?? '(missing)'}; expected '
        '$kLockfileVersion. dashcn.lock v1 is no longer supported: delete '
        'the file and re-run `dashcn init`.',
        sourcePath,
      );
    }
    final layers = <LockLayer, LockLayerState>{};
    final layersJson = json['layers'];
    if (layersJson != null && layersJson is! Map) {
      throw LockFileException('`layers` must be an object.', sourcePath);
    }
    if (layersJson is Map) {
      layersJson.forEach((key, value) {
        final layer = LockLayer.fromKey(key.toString());
        if (layer == null) {
          return;
        }
        if (value is! Map<String, dynamic>) {
          throw LockFileException(
            '`layers.$key` must be an object.',
            sourcePath,
          );
        }
        layers[layer] = LockLayerState.fromJson({
          ...value,
          'layer': layer.key,
        }, sourcePath: sourcePath);
      });
    }
    final componentsJson = json['components'];
    if (componentsJson != null && componentsJson is! List) {
      throw LockFileException('`components` must be an array.', sourcePath);
    }
    final blocksJson = json['blocks'];
    if (blocksJson != null && blocksJson is! List) {
      throw LockFileException('`blocks` must be an array.', sourcePath);
    }
    final flowsJson = json['flows'];
    if (flowsJson != null && flowsJson is! List) {
      throw LockFileException('`flows` must be an array.', sourcePath);
    }
    return DashcnLock(
      registry: json['registry'] is Map<String, dynamic>
          ? LockRegistry.fromJson(
              json['registry']! as Map<String, dynamic>,
              sourcePath: sourcePath,
            )
          : const LockRegistry(),
      installRoot: normalizeLockPath(json['installRoot']?.toString() ?? ''),
      theme: json['theme'] is Map<String, dynamic>
          ? LockThemeSelection.fromJson(
              json['theme']! as Map<String, dynamic>,
              sourcePath: sourcePath,
            )
          : null,
      layers: layers,
      components: componentsJson is List
          ? componentsJson
              .whereType<Map<String, dynamic>>()
              .map(
                (component) => LockComponent.fromJson(
                  component,
                  sourcePath: sourcePath,
                ),
              )
              .toList()
          : const [],
      blocks: blocksJson is List
          ? blocksJson
              .whereType<Map<String, dynamic>>()
              .map(
                (block) => LockBlock.fromJson(
                  block,
                  sourcePath: sourcePath,
                ),
              )
              .toList()
          : const [],
      flows: flowsJson is List
          ? flowsJson
              .whereType<Map<String, dynamic>>()
              .map(
                (flow) => LockFlow.fromJson(
                  flow,
                  sourcePath: sourcePath,
                ),
              )
              .toList()
          : const [],
    );
  }

  final int lockfileVersion;
  final LockRegistry registry;

  /// Project relative install root, e.g. `lib/ui/dashcn`.
  final String installRoot;

  final LockThemeSelection? theme;
  final Map<LockLayer, LockLayerState> layers;
  final List<LockComponent> components;

  /// Installed blocks, sorted by id.
  final List<LockBlock> blocks;

  /// Installed flows, sorted by id (P9-3b layer 5).
  final List<LockFlow> flows;

  /// State of [layer]; empty when the layer was never installed.
  LockLayerState layerState(LockLayer layer) =>
      layers[layer] ?? const LockLayerState();

  List<String> get componentIds =>
      components.map((component) => component.id).toList()..sort();

  List<String> get blockIds => blocks.map((block) => block.id).toList()..sort();

  List<String> get flowIds => flows.map((flow) => flow.id).toList()..sort();

  bool get isEmpty =>
      components.isEmpty &&
      blocks.isEmpty &&
      flows.isEmpty &&
      layers.values.every((l) => l.isEmpty);

  /// Every registry-owned path: layer files, component files, block files,
  /// flow files and the generated theme file.
  Set<String> get registryOwnedPaths => {
        for (final layer in LockLayer.values) ...layerState(layer).files.keys,
        for (final component in components) ...component.files.keys,
        for (final block in blocks) ...block.files.keys,
        for (final flow in flows) ...flow.files.keys,
        if (theme != null && theme!.path.isNotEmpty) theme!.path,
      };

  /// Every user-owned path; never updatable, never deleted.
  Set<String> get userOwnedPaths => {
        for (final component in components) ...component.userOwnedPaths,
      };

  /// Registry-owned paths minus user-owned ones: exactly what `update` may
  /// overwrite.
  Set<String> get updatablePaths =>
      registryOwnedPaths.difference(userOwnedPaths);

  bool isUserOwned(String path) => userOwnedPaths.contains(path);

  /// Component id, block id, flow id, or layer key, that owns [path];
  /// `null` when unowned.
  String? ownerOf(String path) {
    final normalized = normalizeLockPath(path);
    for (final component in components) {
      if (component.allPaths.contains(normalized)) {
        return component.id;
      }
    }
    for (final block in blocks) {
      if (block.files.containsKey(normalized)) {
        return block.id;
      }
    }
    for (final flow in flows) {
      if (flow.files.containsKey(normalized)) {
        return flow.id;
      }
    }
    if (theme != null && theme!.path == normalized) {
      return LockLayer.theme.key;
    }
    for (final layer in LockLayer.values) {
      if (layerState(layer).files.containsKey(normalized)) {
        return layer.key;
      }
    }
    return null;
  }

  /// Component, block and flow ids that own at least one of [paths] in
  /// any role.
  Set<String> dependentsOf(Set<String> paths) {
    return {
      for (final component in components)
        if (component.ownsAny(paths)) component.id,
      for (final block in blocks)
        if (block.ownsAny(paths)) block.id,
      for (final flow in flows)
        if (flow.ownsAny(paths)) flow.id,
    };
  }

  DashcnLock copyWith({
    LockRegistry? registry,
    String? installRoot,
    LockThemeSelection? theme,
    bool clearTheme = false,
    Map<LockLayer, LockLayerState>? layers,
    List<LockComponent>? components,
    List<LockBlock>? blocks,
    List<LockFlow>? flows,
  }) {
    return DashcnLock(
      lockfileVersion: lockfileVersion,
      registry: registry ?? this.registry,
      installRoot: installRoot ?? this.installRoot,
      theme: clearTheme ? null : (theme ?? this.theme),
      layers: layers ?? this.layers,
      components: components ?? this.components,
      blocks: blocks ?? this.blocks,
      flows: flows ?? this.flows,
    );
  }

  DashcnLock withRegistry(LockRegistry value) => copyWith(registry: value);

  DashcnLock withTheme(LockThemeSelection? value) =>
      value == null ? copyWith(clearTheme: true) : copyWith(theme: value);

  DashcnLock putLayer(LockLayer layer, LockLayerState state) {
    return copyWith(layers: {...layers, layer: state});
  }

  /// Adds units and files to [layer] without dropping what is already there.
  DashcnLock mergeLayer(
    LockLayer layer, {
    Set<String> units = const {},
    Map<String, String> files = const {},
  }) {
    final current = layerState(layer);
    return putLayer(
      layer,
      LockLayerState(
        units: lockSortedList([...current.units, ...units]),
        files: {...current.files, ...files},
      ),
    );
  }

  /// Replaces the record for [component], keeping the list sorted by id.
  DashcnLock upsertComponent(LockComponent component) {
    final next =
        components.where((existing) => existing.id != component.id).toList()
          ..add(component)
          ..sort((a, b) => a.id.compareTo(b.id));
    return copyWith(components: next);
  }

  /// Drops [id] from the lock.
  ///
  /// `remove` deletes the component's registry-owned files; its user-owned
  /// files stay on disk unless `--purge-user-themes` is given, which the
  /// caller decides from the dropped record
  /// (`lock.componentFor(id)?.userOwnedPaths`) read before this call.
  DashcnLock removeComponent(String id) {
    return copyWith(
      components: components.where((component) => component.id != id).toList(),
    );
  }

  LockComponent? componentFor(String id) {
    for (final component in components) {
      if (component.id == id) {
        return component;
      }
    }
    return null;
  }

  LockBlock? blockFor(String id) {
    for (final block in blocks) {
      if (block.id == id) {
        return block;
      }
    }
    return null;
  }

  LockFlow? flowFor(String id) {
    for (final flow in flows) {
      if (flow.id == id) {
        return flow;
      }
    }
    return null;
  }

  /// Replaces the record for [block], keeping the list sorted by id.
  DashcnLock upsertBlock(LockBlock block) {
    final next = blocks.where((existing) => existing.id != block.id).toList()
      ..add(block)
      ..sort((a, b) => a.id.compareTo(b.id));
    return copyWith(blocks: next);
  }

  /// Drops [id] from the lock. A block owns no user-owned file, so every path
  /// it recorded is deletable.
  DashcnLock removeBlock(String id) {
    return copyWith(
      blocks: blocks.where((block) => block.id != id).toList(),
    );
  }

  /// Replaces the record for [flow], keeping the list sorted by id.
  DashcnLock upsertFlow(LockFlow flow) {
    final next = flows.where((existing) => existing.id != flow.id).toList()
      ..add(flow)
      ..sort((a, b) => a.id.compareTo(b.id));
    return copyWith(flows: next);
  }

  /// Drops [id] from the lock. A flow owns no user-owned file, so every
  /// path it recorded is deletable.
  DashcnLock removeFlow(String id) {
    return copyWith(
      flows: flows.where((flow) => flow.id != id).toList(),
    );
  }

  /// Union with [other]: components, blocks and flows are upserted by id,
  /// layer units and files are unioned and [other]'s hashes win because it
  /// was written last.
  DashcnLock mergeWith(DashcnLock other) {
    var merged = copyWith(
      registry: other.registry.name.isEmpty ? registry : other.registry,
      installRoot: other.installRoot.isEmpty ? installRoot : other.installRoot,
      theme: other.theme ?? theme,
    );
    for (final layer in LockLayer.values) {
      final otherState = other.layerState(layer);
      if (otherState.isEmpty) {
        continue;
      }
      merged = merged.putLayer(layer, layerState(layer).mergeWith(otherState));
    }
    for (final component in other.components) {
      merged = merged.upsertComponent(component);
    }
    for (final block in other.blocks) {
      merged = merged.upsertBlock(block);
    }
    for (final flow in other.flows) {
      merged = merged.upsertFlow(flow);
    }
    return merged;
  }

  Map<String, dynamic> toJson() {
    final sortedComponents = components.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final sortedBlocks = blocks.toList()..sort((a, b) => a.id.compareTo(b.id));
    final sortedFlows = flows.toList()..sort((a, b) => a.id.compareTo(b.id));
    return {
      'lockfileVersion': lockfileVersion,
      'registry': registry.toJson(),
      'installRoot': installRoot,
      'theme': theme?.toJson(),
      'layers': {
        for (final layer in LockLayer.values)
          layer.key: layerState(layer).toJson(),
      },
      'components':
          sortedComponents.map((component) => component.toJson()).toList(),
      'blocks': sortedBlocks.map((block) => block.toJson()).toList(),
      'flows': sortedFlows.map((flow) => flow.toJson()).toList(),
    };
  }
}

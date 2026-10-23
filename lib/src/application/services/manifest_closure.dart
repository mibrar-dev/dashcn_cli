import 'package:dashcn_cli/src/registry/manifest/manifest_unit.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';

/// Raised when a component or unit id referenced by a closure is not in the
/// manifest. Clean break: there is no fallback resolution and no v1 graph.
class ManifestClosureException implements Exception {
  const ManifestClosureException(this.kind, this.id, {this.referencedBy});

  /// `component`, `block`, `primitive`, `foundation` or `theme`.
  final String kind;

  /// The unknown id.
  final String id;

  /// The component or block whose dependency block referenced [id], when known.
  final String? referencedBy;

  @override
  String toString() {
    final source =
        referencedBy == null ? '' : ' (referenced by "$referencedBy")';
    return 'Unknown $kind id "$id" in the registry manifest$source.';
  }
}

/// The transitive closure of a set of components, blocks and flows: every
/// component, block, flow, layer unit and file the install needs.
///
/// Layers are implicit (plan §1.2): foundation/theme/primitives are never
/// addressed as components, only pulled in here. The primitive graph contains
/// cycles (plan §9.7), so resolution uses a visited-set DFS and never rejects
/// a cycle; install order is irrelevant because files are copied verbatim.
class ManifestClosure {
  const ManifestClosure({
    this.components = const [],
    this.blocks = const [],
    this.flows = const [],
    this.foundation = const [],
    this.theme = const [],
    this.primitives = const [],
    this.files = const [],
    this.packages = const [],
  });

  /// Component ids, sorted.
  final List<String> components;

  /// Block ids, sorted.
  final List<String> blocks;

  /// Flow ids, sorted (P9-3b layer 5).
  final List<String> flows;

  /// Foundation unit ids, sorted.
  final List<String> foundation;

  /// Theme unit ids, sorted.
  final List<String> theme;

  /// Primitive unit ids, sorted.
  final List<String> primitives;

  /// Registry-relative copyable files (foundation/theme/primitives/components/
  /// blocks/flows), sorted. Excludes `themes/` JSON, block/flow `docs` and
  /// user-owned files.
  final List<String> files;

  /// Union of the `packages` declared by every unit, component and block in
  /// the closure, sorted by name (plan §9.1).
  final List<PackageRef> packages;

  bool get isEmpty =>
      components.isEmpty &&
      blocks.isEmpty &&
      flows.isEmpty &&
      foundation.isEmpty &&
      theme.isEmpty &&
      primitives.isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'components': components,
      'blocks': blocks,
      'flows': flows,
      'foundation': foundation,
      'theme': theme,
      'primitives': primitives,
      'files': files,
      'packages': packages
          .map(
            (package) => {
              'name': package.name,
              if (package.sdk) 'sdk': true,
              if (package.constraint != null) 'constraint': package.constraint,
            },
          )
          .toList(),
    };
  }
}

/// Registry-relative directory of the locale tables.
const String kLocalizationsPrimitiveDir = 'primitives/localizations';

/// Basename of the kit locale delegate: it imports every per-locale table, so
/// a slim install replaces it with a generated English-fallback delegate
/// (see `LocaleSyncService`) instead of copying it.
const String kLocaleDelegateFile = 'localizations_delegate.dart';

/// Locale-neutral files of the `localizations` primitive: the base
/// `ComponentLocalizations` class, the domain mixins, the formatting
/// extensions and the date/time part enums.
///
/// This mirrors the kit layout the same way `layerDirs` and `componentsDir`
/// do: everything else in that directory is a per-locale table
/// (`localizations_<locale>.dart`) or the kit delegate above. A slim install
/// (any registry whose components record `localizationKeys`) copies only
/// these files; the per-project `dashcn_locales/` output carries the
/// translations the installed components need.
const Set<String> kLocaleNeutralFiles = {
  'locale_parts.dart',
  'localizations.dart',
  'localizations_blocks.dart',
  'localizations_chrome.dart',
  'localizations_dashcn.dart',
  'localizations_date_time.dart',
  'localizations_error.dart',
  'localizations_extensions.dart',
  'localizations_files.dart',
  'localizations_form.dart',
  'localizations_media.dart',
  'localizations_misc.dart',
  'localizations_overlay.dart',
};

/// True when [relPath] is a locale table or the kit delegate: skipped by a
/// slim install and regenerated per project by the locale sync.
bool isSlimmedLocaleFile(String relPath) {
  const prefix = '$kLocalizationsPrimitiveDir/';
  if (!relPath.startsWith(prefix)) {
    return false;
  }
  final name = relPath.substring(prefix.length);
  if (name.contains('/')) {
    return false;
  }
  return !kLocaleNeutralFiles.contains(name);
}

/// Resolves the component + block + layer closure from a [RegistryManifest].
class ManifestClosureResolver {
  const ManifestClosureResolver(this.manifest);

  final RegistryManifest manifest;

  /// Transitive closure of [ids] plus [blockIds] plus [flowIds].
  ///
  /// [ids] may name a component, a block or a flow: that is the `add <id>`
  /// contract, so `add login-01` resolves exactly like `add button`. A
  /// `flow:<id>` address always resolves as a flow (`add flow:auth-01`).
  /// [blockIds] is the explicit form a caller uses when it knows the ids are
  /// blocks and nothing else (`add --all --blocks`, `sync`, `project
  /// refresh`); [flowIds] is the same for flows.
  ///
  /// [includeCore] adds every foundation and theme unit (the always-on core
  /// `init` copies, plan §2.1); `add` keeps it on so the layer core is present
  /// even on a project that was never `init`ed.
  ///
  /// [includeAllPrimitives] adds every primitive unit, even those no requested
  /// component uses. `add --all` sets it so the install matches the registry
  /// mirror (docs `sync_registry.sh` copies every file); selective adds keep
  /// it off so unused primitives never bloat the app.
  ///
  /// An id that names nothing is a [ManifestClosureException], so a typo never
  /// silently installs nothing.
  ManifestClosure resolve(
    Iterable<String> ids, {
    Iterable<String> blockIds = const [],
    Iterable<String> flowIds = const [],
    bool includeCore = true,
    bool includeAllPrimitives = false,
  }) {
    final components = <String>{};
    final blocks = <String>{};
    final flows = <String>{};
    final primitives = <String>{};
    final foundation = <String>{};
    final theme = <String>{};

    final queue = <_Seed>[];
    for (final raw in ids) {
      _seed(raw, components, blocks, flows, queue);
    }
    for (final raw in blockIds) {
      final id = raw.trim();
      if (id.isEmpty) {
        continue;
      }
      _requireBlock(id);
      if (blocks.add(id)) {
        queue.add(_Seed.block(id));
      }
    }
    for (final raw in flowIds) {
      final id = stripFlowPrefix(raw).trim();
      if (id.isEmpty) {
        continue;
      }
      _requireFlow(id);
      if (flows.add(id)) {
        queue.add(_Seed.flow(id));
      }
    }

    while (queue.isNotEmpty) {
      final seed = queue.removeLast();
      switch (seed.kind) {
        case _SeedKind.component:
          final deps = manifest.components[seed.id]!.deps;
          _collectDeps(
            deps.components,
            deps.primitives,
            deps.foundation,
            deps.theme,
            seed.id,
            components,
            primitives,
            foundation,
            theme,
            queue,
          );
        case _SeedKind.block:
          final deps = manifest.blocks[seed.id]!.deps;
          _collectDeps(
            deps.components,
            deps.primitives,
            deps.foundation,
            deps.theme,
            seed.id,
            components,
            primitives,
            foundation,
            theme,
            queue,
          );
        case _SeedKind.flow:
          final deps = manifest.flows[seed.id]!.deps;
          _collectDeps(
            deps.components,
            deps.primitives,
            deps.foundation,
            deps.theme,
            seed.id,
            components,
            primitives,
            foundation,
            theme,
            queue,
          );
          for (final dep in deps.blocks) {
            _requireBlock(dep, referencedBy: seed.id);
            if (blocks.add(dep)) {
              queue.add(_Seed.block(dep));
            }
          }
      }
    }

    if (includeCore) {
      foundation.addAll(manifest.foundation.keys);
      theme.addAll(manifest.theme.keys);
    }

    if (includeAllPrimitives) {
      primitives.addAll(manifest.primitives.keys);
    }

    return ManifestClosure(
      components: _sorted(components),
      blocks: _sorted(blocks),
      flows: _sorted(flows),
      foundation: _sorted(foundation),
      theme: _sorted(theme),
      primitives: _sorted(primitives),
      files: _sorted(
        _filesOf(components, blocks, flows, primitives, foundation, theme),
      ),
      packages: _packagesOf(
        components,
        blocks,
        flows,
        primitives,
        foundation,
        theme,
      ),
    );
  }

  void _collectDeps(
    List<String> componentDeps,
    List<String> primitiveDeps,
    List<String> foundationDeps,
    List<String> themeDeps,
    String referrer,
    Set<String> components,
    Set<String> primitives,
    Set<String> foundation,
    Set<String> theme,
    List<_Seed> queue,
  ) {
    for (final dep in componentDeps) {
      _requireComponent(dep, referencedBy: referrer);
      if (components.add(dep)) {
        queue.add(_Seed.component(dep));
      }
    }
    for (final dep in primitiveDeps) {
      _addPrimitive(dep, primitives, referencedBy: referrer);
    }
    for (final dep in foundationDeps) {
      _requireFoundation(dep, referencedBy: referrer);
      foundation.add(dep);
    }
    for (final dep in themeDeps) {
      _requireTheme(dep, referencedBy: referrer);
      theme.add(dep);
    }
  }

  void _requireComponent(String id, {String? referencedBy}) {
    if (!manifest.components.containsKey(id)) {
      throw ManifestClosureException(
        'component',
        id,
        referencedBy: referencedBy,
      );
    }
  }

  /// Seeds one user-typed id: `flow:<id>` always resolves as a flow,
  /// otherwise a component when the manifest has one, a block when it has
  /// that, a flow when it has that, an error when it has none.
  void _seed(
    String raw,
    Set<String> components,
    Set<String> blocks,
    Set<String> flows,
    List<_Seed> queue,
  ) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (isFlowAddress(trimmed)) {
      final id = stripFlowPrefix(trimmed);
      _requireFlow(id);
      if (flows.add(id)) {
        queue.add(_Seed.flow(id));
      }
      return;
    }
    final id = trimmed;
    if (manifest.components.containsKey(id)) {
      _requireComponent(id);
      if (components.add(id)) {
        queue.add(_Seed.component(id));
      }
      return;
    }
    if (manifest.blocks.containsKey(id)) {
      if (blocks.add(id)) {
        queue.add(_Seed.block(id));
      }
      return;
    }
    if (manifest.flows.containsKey(id)) {
      if (flows.add(id)) {
        queue.add(_Seed.flow(id));
      }
      return;
    }
    final kinds = [
      'component',
      if (manifest.blocks.isNotEmpty) 'block',
      if (manifest.flows.isNotEmpty) 'flow',
    ];
    throw ManifestClosureException(
      kinds.length == 1
          ? kinds.single
          : kinds.join(', ').replaceAll(
                ', ${kinds.last}',
                ' or ${kinds.last}',
              ),
      id,
    );
  }

  void _requireFlow(String id, {String? referencedBy}) {
    if (!manifest.flows.containsKey(id)) {
      throw ManifestClosureException(
        'flow',
        id,
        referencedBy: referencedBy,
      );
    }
  }

  void _requireBlock(String id, {String? referencedBy}) {
    if (!manifest.blocks.containsKey(id)) {
      throw ManifestClosureException(
        'block',
        id,
        referencedBy: referencedBy,
      );
    }
  }

  void _requireFoundation(String id, {String? referencedBy}) {
    if (!manifest.foundation.containsKey(id)) {
      throw ManifestClosureException(
        'foundation',
        id,
        referencedBy: referencedBy,
      );
    }
  }

  void _requireTheme(String id, {String? referencedBy}) {
    if (!manifest.theme.containsKey(id)) {
      throw ManifestClosureException('theme', id, referencedBy: referencedBy);
    }
  }

  /// Cycle-tolerant DFS over the primitive graph.
  void _addPrimitive(String id, Set<String> into, {String? referencedBy}) {
    final stack = <String>[id];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (!into.add(current)) {
        continue;
      }
      final unit = manifest.primitives[current];
      if (unit == null) {
        throw ManifestClosureException(
          'primitive',
          current,
          referencedBy: referencedBy,
        );
      }
      for (final dep in unit.deps.primitives) {
        if (!into.contains(dep)) {
          stack.add(dep);
        }
      }
    }
  }

  Iterable<String> _filesOf(
    Set<String> components,
    Set<String> blocks,
    Set<String> flows,
    Set<String> primitives,
    Set<String> foundation,
    Set<String> theme,
  ) {
    // A locale-aware registry installs translations per project
    // (`dashcn_locales/`): the per-locale tables and the kit delegate that
    // imports all of them never reach the app. Older registries (no
    // `localizationKeys`) keep the historical full copy.
    final slim = manifest.hasLocalizationKeys;
    final files = <String>{};
    void add(Iterable<String> paths) {
      for (final path in paths) {
        if (slim && isSlimmedLocaleFile(path)) {
          continue;
        }
        files.add(path);
      }
    }

    for (final id in components) {
      add(manifest.components[id]!.files);
    }
    for (final id in blocks) {
      add(manifest.blocks[id]!.files);
    }
    for (final id in flows) {
      add(manifest.flows[id]!.files);
    }
    for (final id in primitives) {
      add(manifest.primitives[id]!.files);
    }
    for (final id in foundation) {
      add(manifest.foundation[id]!.files);
    }
    for (final id in theme) {
      add(manifest.theme[id]!.files);
    }
    return files;
  }

  List<PackageRef> _packagesOf(
    Set<String> components,
    Set<String> blocks,
    Set<String> flows,
    Set<String> primitives,
    Set<String> foundation,
    Set<String> theme,
  ) {
    final byName = <String, PackageRef>{};
    void collect(Iterable<PackageRef> packages) {
      for (final package in packages) {
        if (package.name.isEmpty) {
          continue;
        }
        byName.putIfAbsent(package.name, () => package);
      }
    }

    for (final id in _sorted(components)) {
      collect(manifest.components[id]!.packages);
    }
    for (final id in _sorted(blocks)) {
      collect(manifest.blocks[id]!.packages);
    }
    for (final id in _sorted(flows)) {
      collect(manifest.flows[id]!.packages);
    }
    for (final id in _sorted(primitives)) {
      collect(manifest.primitives[id]!.packages);
    }
    for (final id in _sorted(foundation)) {
      collect(manifest.foundation[id]!.packages);
    }
    for (final id in _sorted(theme)) {
      collect(manifest.theme[id]!.packages);
    }
    final names = byName.keys.toList()..sort();
    return [for (final name in names) byName[name]!];
  }

  static List<String> _sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();
}

enum _SeedKind { component, block, flow }

/// One queue entry: an id plus which map it came from.
class _Seed {
  const _Seed.component(this.id) : kind = _SeedKind.component;
  const _Seed.block(this.id) : kind = _SeedKind.block;
  const _Seed.flow(this.id) : kind = _SeedKind.flow;

  final String id;
  final _SeedKind kind;
}

/// Whether [raw] is a `flow:<id>` address (P9-3b).
bool isFlowAddress(String raw) {
  final trimmed = raw.trim().toLowerCase();
  return trimmed.startsWith('flow:') && trimmed.length > 'flow:'.length;
}

/// Strips the `flow:` prefix; bare ids pass through unchanged.
String stripFlowPrefix(String raw) {
  final trimmed = raw.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('flow:')) {
    return trimmed.substring('flow:'.length).trim();
  }
  return trimmed;
}

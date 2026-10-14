import 'package:dashcn_cli/src/application/services/installer/installer_lock_part.dart';
import 'package:dashcn_cli/src/application/services/installer/pub_package_resolver.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/application/services/version/version_manager.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_component.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';

/// `dashcn add <id> --package`: depend on the published `dashcn` package
/// instead of copying sources.
///
/// Runs `flutter pub add dashcn:^0.1.0` (or `--path <dir>`), writes no
/// sources, and records each component in `dashcn.lock` as `mode: package`
/// with its closure and api symbols so `dashcn eject` can materialise it
/// later. Blocks cannot be package dependencies: they are app screens.
/// Flows resolve to their per-flow library (`package:dashcn/flows/<stem>.dart`,
/// underscores) and are recorded in the lock's `flows` list with no files.
class PackageAddService {
  PackageAddService({
    required this.manifest,
    required this.projectRoot,
    required this.installRoot,
    LockRepository? lockRepo,
    PubCommandRunner? pubRunner,
    CliLogger? logger,
  })  : _lockRepo = lockRepo ?? LockRepository(projectRoot),
        _pubRunner = pubRunner ?? const ProcessPubCommandRunner(),
        logger = logger ?? CliLogger();

  final RegistryManifest manifest;
  final String projectRoot;
  final String installRoot;
  final LockRepository _lockRepo;
  final PubCommandRunner _pubRunner;
  final CliLogger logger;

  /// The hosted constraint added for package mode.
  static String hostedConstraint() =>
      'dashcn:^${VersionManager.currentVersion}';

  /// Package import for a component [id] (the public per-component library).
  static String importFor(String id) => 'package:dashcn/components/$id.dart';

  /// Package import for a flow [id] (the public per-flow library; the
  /// hyphenated id maps to an underscored stem, matching `gen_exports`).
  static String importForFlow(String id) =>
      'package:dashcn/flows/${id.replaceAll('-', '_')}.dart';

  Future<PackageAddReport> add(
    Iterable<String> componentIds, {
    Iterable<String> flowIds = const [],
    String? path,
    bool dryRun = false,
  }) async {
    final ids = componentIds.toList();
    final flows = flowIds.map(stripFlowPrefix).toList();
    for (final id in ids) {
      if (manifest.blocks.containsKey(id)) {
        throw PackageAddException(
          'Block `$id` cannot be added with --package: blocks are app '
          'screens. Add it without --package to copy its sources.',
        );
      }
      if (manifest.flows.containsKey(id)) {
        throw PackageAddException(
          'Use `flow:$id` to add a flow with --package.',
        );
      }
      if (!manifest.components.containsKey(id)) {
        throw ManifestClosureException('component', id);
      }
    }
    for (final id in flows) {
      if (!manifest.flows.containsKey(id)) {
        throw ManifestClosureException('flow', id);
      }
    }
    final report = PackageAddReport(
      requested: [...ids, for (final id in flows) 'flow:$id'],
      imports: {
        for (final id in ids) id: importFor(id),
        for (final id in flows) 'flow:$id': importForFlow(id),
      },
      pubArgs: path == null
          ? ['pub', 'add', hostedConstraint()]
          : ['pub', 'add', 'dashcn', '--path', path],
      applied: !dryRun,
    );
    if (dryRun) {
      return report;
    }
    if (path == null) {
      await _pubRunner.pubAdd(projectRoot, [hostedConstraint()]);
    } else {
      await _pubRunner.pubAddPath(projectRoot, 'dashcn', path);
    }
    final current = await _lockRepo.load();
    var next = current;
    for (final id in ids) {
      final component = manifest.components[id]!;
      next = next.upsertComponent(
        LockComponent(
          id: id,
          version: manifest.registry.version,
          deps: _depsOf(component.deps),
          api: lockApiFor(component.api),
          mode: LockComponentMode.package,
        ),
      );
    }
    for (final id in flows) {
      final flow = manifest.flows[id]!;
      next = next.upsertFlow(
        LockFlow(
          id: id,
          version: manifest.registry.version,
          deps: LockComponentDeps(
            foundation: lockSortedList(flow.deps.foundation),
            theme: lockSortedList(flow.deps.theme),
            primitives: lockSortedList(flow.deps.primitives),
            components: lockSortedList(flow.deps.components),
          ),
        ),
      );
    }
    if (next.installRoot.isEmpty) {
      next = next.copyWith(installRoot: installRoot);
    }
    await _lockRepo.save(next);
    return report;
  }

  static LockComponentDeps _depsOf(ManifestComponentDeps deps) {
    return LockComponentDeps(
      foundation: lockSortedList(deps.foundation),
      theme: lockSortedList(deps.theme),
      primitives: lockSortedList(deps.primitives),
      components: lockSortedList(deps.components),
    );
  }
}

/// `add --package` was refused before anything was written.
class PackageAddException implements Exception {
  const PackageAddException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What `add --package` planned (or did).
class PackageAddReport {
  const PackageAddReport({
    required this.requested,
    required this.imports,
    required this.pubArgs,
    required this.applied,
  });

  final List<String> requested;
  final Map<String, String> imports;
  final List<String> pubArgs;
  final bool applied;

  Map<String, dynamic> toJson() {
    return {
      'requested': requested,
      'imports': imports,
      'pubArgs': pubArgs,
      'applied': applied,
    };
  }
}

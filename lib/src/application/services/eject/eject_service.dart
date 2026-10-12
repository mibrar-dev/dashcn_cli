import 'package:dashcn_cli/src/application/services/eject/import_rewriter.dart';
import 'package:dashcn_cli/src/application/services/installer/dry_run_plan.dart';
import 'package:dashcn_cli/src/application/services/installer/installer.dart';
import 'package:dashcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:dashcn_cli/src/application/services/installer/installer_lock_part.dart';
import 'package:dashcn_cli/src/application/services/installer/pub_package_resolver.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';

/// `dashcn eject <id>`: turns a `mode: package` component into owned sources.
///
/// Copies the component's files (plus the transitive closure entries not
/// already owned; with `--with-deps` every transitive component) into the
/// install dir, flips the lock entries to `mode: copy`, and rewrites the
/// app's `package:dashcn/...` imports to the owned files. Refuses when a
/// file to write was locally modified, unless `--force`.
class EjectService {
  EjectService({
    required this.manifest,
    required this.projectRoot,
    required RegistryFileReader reader,
    required this.installRoot,
    this.manifestSha256 = '',
    LockRepository? lockRepo,
    PubCommandRunner? pubRunner,
    CliLogger? logger,
  })  : _reader = reader,
        _lockRepo = lockRepo ?? LockRepository(projectRoot),
        _pubRunner = pubRunner,
        logger = logger ?? CliLogger();

  final RegistryManifest manifest;
  final String projectRoot;
  final String installRoot;
  final String manifestSha256;
  final RegistryFileReader _reader;
  final LockRepository _lockRepo;
  final PubCommandRunner? _pubRunner;
  final CliLogger logger;

  Installer get _installer => Installer(
        manifest: manifest,
        projectRoot: projectRoot,
        reader: _reader,
        installRoot: installRoot,
        manifestSha256: manifestSha256,
        logger: logger,
        pubRunner: _pubRunner,
      );

  Future<EjectReport> eject(
    String id, {
    bool withDeps = false,
    bool dryRun = false,
    bool force = false,
  }) async {
    final lock = await _lockRepo.load();
    final entry = lock.componentFor(id);
    if (entry == null) {
      throw EjectException(
        'Component `$id` is not installed (no entry in dashcn.lock).',
      );
    }
    if (entry.mode != LockComponentMode.package) {
      throw EjectException(
        'Component `$id` is already owned (mode: copy). Nothing to eject.',
      );
    }
    final closure = ManifestClosureResolver(manifest).resolve(
      [id],
      includeCore: false,
    );
    final toCopy = withDeps ? closure.components.toList() : [id];
    // The manifest's primitive -> layer edges are partial (a primitive may
    // import sibling layer files outside its recorded deps), so eject
    // materialises the whole foundation + theme core exactly like a copy-mode
    // `add` does. Files already owned are skipped by the plan.
    final plan = await _installer.plan(
      toCopy,
      includeCore: true,
      overwrite: force,
    );
    final conflicts = [
      for (final file in plan.files)
        if (file.action == PlanAction.skip && file.reason == 'locally modified')
          file.target,
    ];
    if (conflicts.isNotEmpty && !force) {
      throw EjectConflictException(id, conflicts);
    }
    final ownedEntry = '$installRoot/${manifest.components[id]!.entry}';
    final apiSymbols = manifestSymbols(manifest.components[id]!.api);
    if (dryRun) {
      final preview = await ImportRewriter.rewrite(
        projectRoot: projectRoot,
        id: id,
        apiSymbols: apiSymbols,
        ownedEntry: ownedEntry,
        dryRun: true,
      );
      return EjectReport(
        id: id,
        applied: false,
        files: [for (final file in plan.files) file.target],
        rewrites: preview,
      );
    }
    final applied = await _installer.add(
      toCopy,
      includeCore: true,
      overwrite: force,
    );
    var next = await _lockRepo.load();
    for (final copied in toCopy) {
      final recorded = next.componentFor(copied);
      if (recorded != null && recorded.mode != LockComponentMode.copy) {
        next = next.upsertComponent(
          recorded.copyWith(mode: LockComponentMode.copy),
        );
      }
    }
    await _lockRepo.save(next);
    final rewrites = await ImportRewriter.rewrite(
      projectRoot: projectRoot,
      id: id,
      apiSymbols: apiSymbols,
      ownedEntry: ownedEntry,
    );
    return EjectReport(
      id: id,
      applied: true,
      files: applied.written,
      rewrites: rewrites,
    );
  }
}

/// `eject` was refused before anything was written.
class EjectException implements Exception {
  const EjectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `eject` would overwrite locally modified files; re-run with `--force`.
class EjectConflictException extends EjectException {
  const EjectConflictException(String id, this.conflicts)
      : super('Component `$id` has locally modified files.');

  final List<String> conflicts;

  @override
  String toString() => '${super.message} Re-run with --force to overwrite:\n'
      '${conflicts.map((path) => '  $path').join('\n')}';
}

/// What `eject` planned (or did).
class EjectReport {
  const EjectReport({
    required this.id,
    required this.applied,
    required this.files,
    required this.rewrites,
  });

  final String id;
  final bool applied;
  final List<String> files;
  final Map<String, List<String>> rewrites;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'applied': applied,
      'files': files,
      'rewrites': rewrites,
    };
  }
}

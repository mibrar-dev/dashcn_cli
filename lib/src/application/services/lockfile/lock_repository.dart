import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_drift_report.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_file_exception.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_json.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_layer.dart';
import 'package:dashcn_cli/src/application/services/lockfile/dashcn_lock_v2.dart';
import 'package:path/path.dart' as p;

export 'package:dashcn_cli/src/application/services/lockfile/hashing.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_drift_report.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_file_exception.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_install_state.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_json.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_layer.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_block.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_component.dart';
export 'package:dashcn_cli/src/application/services/lockfile/lock_flow.dart';
export 'package:dashcn_cli/src/application/services/lockfile/dashcn_lock_v2.dart';

/// Reads, writes and diffs `<projectRoot>/dashcn.lock` (lockfileVersion 2).
///
/// The lock is the only install-state file: no `.dashcn/state.json`, no
/// `.dashcn/components/*.json`, and no v1 lockfileVersion.
class LockRepository {
  const LockRepository(this.projectRoot);

  final String projectRoot;

  File get file => File(p.join(projectRoot, kLockFileName));

  bool existsSync() => file.existsSync();

  Future<bool> exists() => file.exists();

  /// Absolute path of [relativePath] inside the project.
  File resolve(String relativePath) => File(p.join(projectRoot, relativePath));

  /// Loads the lock.
  ///
  /// A missing lock is not an error: it yields an empty v2 lock. A lock that
  /// exists but cannot be parsed raises [LockFileException] so callers can
  /// tell "fresh project" apart from "corrupt install state".
  Future<DashcnLock> load() async {
    if (!await file.exists()) {
      return const DashcnLock();
    }
    return parse(await file.readAsString());
  }

  /// [load], or `null` when no lock file exists at all.
  Future<DashcnLock?> loadIfPresent() async {
    if (!await file.exists()) {
      return null;
    }
    return parse(await file.readAsString());
  }

  /// Parses [source] as a v2 lock. Shared with `validate` and the tests.
  DashcnLock parse(String source, {String sourcePath = kLockFileName}) {
    if (source.trim().isEmpty) {
      throw LockFileException('The lock file is empty.', sourcePath);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw LockFileException(
        'The lock file is not valid JSON (${error.message}).',
        sourcePath,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw LockFileException(
        'The lock file must contain a JSON object.',
        sourcePath,
      );
    }
    return DashcnLock.fromJson(decoded, sourcePath: sourcePath);
  }

  /// Writes [lock] deterministically: sorted keys, sorted components, two
  /// space indent and a trailing newline, so diffs stay reviewable.
  Future<void> save(DashcnLock lock) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final payload = const JsonEncoder.withIndent('  ').convert(lock.toJson());
    await file.writeAsString('$payload\n', flush: true);
  }

  /// Read-modify-write helper for sequential `init`/`add`/`remove` runs.
  Future<DashcnLock> update(
    DashcnLock Function(DashcnLock current) mutate,
  ) async {
    final next = mutate(await load());
    await save(next);
    return next;
  }

  /// Merges [incoming] into the stored lock and returns the result.
  Future<DashcnLock> merge(DashcnLock incoming) =>
      update((current) => current.mergeWith(incoming));

  Future<void> delete() async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Hashes every file the lock tracks and reports drift.
  ///
  /// [componentIds] narrows the scan to a subset (used by `update <ids>`).
  /// [manifestSha256] is the digest of the manifest on disk; pass it to get
  /// the "registry moved" flag.
  Future<LockDriftReport> inspect(
    DashcnLock lock, {
    Set<String>? componentIds,
    String? manifestSha256,
  }) async {
    final entries = <_TrackedFile>[];
    for (final layer in LockLayer.values) {
      final state = lock.layerState(layer);
      for (final file in state.files.entries) {
        entries.add(_TrackedFile(file.key, layer.key, file.value, false));
      }
    }
    final theme = lock.theme;
    if (theme != null && theme.path.isNotEmpty && theme.sha256.isNotEmpty) {
      entries.add(
        _TrackedFile(theme.path, LockLayer.theme.key, theme.sha256, false),
      );
    }
    for (final component in lock.components) {
      if (componentIds != null && !componentIds.contains(component.id)) {
        continue;
      }
      for (final file in component.files.entries) {
        entries.add(_TrackedFile(file.key, component.id, file.value, false));
      }
      for (final file in component.userOwned.entries) {
        entries.add(_TrackedFile(file.key, component.id, file.value, true));
      }
    }
    for (final block in lock.blocks) {
      for (final file in block.files.entries) {
        entries.add(_TrackedFile(file.key, block.id, file.value, false));
      }
    }
    for (final flow in lock.flows) {
      for (final file in flow.files.entries) {
        entries.add(_TrackedFile(file.key, flow.id, file.value, false));
      }
    }

    final byPath = <String, _TrackedFile>{};
    for (final entry in entries) {
      final existing = byPath[entry.path];
      // A user-owned flag always wins: such a path is never updatable.
      byPath[entry.path] = existing == null || entry.userOwned
          ? entry
          : existing.copyWith(userOwned: true);
    }

    final files = <LockFileDrift>[];
    for (final entry in byPath.values) {
      final actual = await FileHashing.ofFileIfExists(resolve(entry.path));
      final status = actual == null
          ? LockFileStatus.missing
          : FileHashing.matches(entry.expectedSha, actual)
              ? LockFileStatus.unchanged
              : LockFileStatus.modified;
      files.add(
        LockFileDrift(
          path: entry.path,
          owner: entry.owner,
          status: status,
          expectedSha: entry.expectedSha,
          actualSha: actual,
          userOwned: entry.userOwned,
        ),
      );
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    return LockDriftReport(
      files: files,
      currentManifestSha256: manifestSha256,
      registryMoved: manifestSha256 == null
          ? false
          : lock.registry.hasMoved(manifestSha256),
    );
  }

  /// [inspect] for the lock currently on disk.
  Future<LockDriftReport> inspectInstalled({
    Set<String>? componentIds,
    String? manifestSha256,
  }) async {
    return inspect(
      await load(),
      componentIds: componentIds,
      manifestSha256: manifestSha256,
    );
  }

  /// sha256 of the files at [relativePaths] that exist, keyed by path.
  Future<Map<String, String>> hashInstalled(Iterable<String> relativePaths) {
    return FileHashing.ofFiles(
      relativePaths.map(resolve),
      keyOf: (file) =>
          normalizeLockPath(p.relative(file.path, from: projectRoot)),
    );
  }
}

class _TrackedFile {
  const _TrackedFile(this.path, this.owner, this.expectedSha, this.userOwned);

  final String path;
  final String owner;
  final String expectedSha;
  final bool userOwned;

  _TrackedFile copyWith({bool? userOwned}) =>
      _TrackedFile(path, owner, expectedSha, userOwned ?? this.userOwned);
}

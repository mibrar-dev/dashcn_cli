import 'package:dashcn_cli/src/application/services/lockfile/lock_file_exception.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_json.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_component.dart';

/// One installed flow (registry layer 5, P9-3b): the files the CLI wrote and
/// the closure the flow needs.
///
/// A flow mirrors [LockBlock]: it declares no public symbols and has no
/// user-owned file (every byte under `flows/<id>/` belongs to the registry).
class LockFlow {
  LockFlow({
    required this.id,
    this.version,
    Map<String, String> files = const {},
    this.deps = const LockComponentDeps(),
    String sourcePath = kLockFileName,
  }) : files = _cleanHashes(files, sourcePath) {
    if (id.trim().isEmpty) {
      throw LockFileException(
        'A flow entry is missing its `id`.',
        sourcePath,
      );
    }
  }

  factory LockFlow.fromJson(
    Map<String, dynamic> json, {
    String sourcePath = kLockFileName,
  }) {
    final id = json['id']?.toString() ?? '';
    return LockFlow(
      id: id,
      version: json['version']?.toString(),
      files: lockHashMap(json['files'], 'flows[$id].files', sourcePath),
      deps: json['deps'] is Map<String, dynamic>
          ? LockComponentDeps.fromJson(
              json['deps']! as Map<String, dynamic>,
              sourcePath: sourcePath,
            )
          : const LockComponentDeps(),
      sourcePath: sourcePath,
    );
  }

  static Map<String, String> _cleanHashes(
    Map<String, String> value,
    String sourcePath,
  ) =>
      lockHashMap(value, 'flow files', sourcePath);

  /// Registry flow id (== directory name), e.g. `auth-01`.
  final String id;

  /// Registry version, when the manifest publishes one.
  final String? version;

  /// Project relative path -> sha256 of the bytes the CLI wrote.
  final Map<String, String> files;

  final LockComponentDeps deps;

  List<String> get paths => lockSortedList(files.keys);

  /// True when this flow owns at least one of [paths].
  bool ownsAny(Set<String> paths) => paths.any(files.containsKey);

  LockFlow withFile(String path, String sha256) {
    return copyWith(files: {...files, normalizeLockPath(path): sha256});
  }

  LockFlow copyWith({
    String? id,
    String? version,
    Map<String, String>? files,
    LockComponentDeps? deps,
  }) {
    return LockFlow(
      id: id ?? this.id,
      version: version ?? this.version,
      files: files ?? this.files,
      deps: deps ?? this.deps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (version != null && version!.isNotEmpty) 'version': version,
      'files': lockSortedStringMap(files),
      'deps': deps.toJson(),
    };
  }
}

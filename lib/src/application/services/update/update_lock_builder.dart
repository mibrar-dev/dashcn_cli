import 'package:dashcn_cli/src/application/services/installer/installer_lock_part.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_component.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';

/// Applies an `update` run's findings to the v2 lock.
///
/// Kept separate from [UpdateService] so the file stays small: this class only
/// knows how to merge refreshed hashes, newly installed files, the closure's
/// layer units and the refreshed component records into a lock.
class UpdateLockBuilder {
  const UpdateLockBuilder({
    required this.manifest,
    this.manifestSha256 = '',
  });

  final RegistryManifest manifest;
  final String manifestSha256;

  DashcnLock build(
    DashcnLock lock, {
    required Map<String, String> newHashes,
    required Map<LockLayer, Map<String, String>> newLayerFiles,
    required Map<String, Map<String, String>> newComponentFiles,
    required Map<String, Map<String, String>> newBlockFiles,
    required Map<String, Map<String, String>> newFlowFiles,
    required Map<String, Map<String, String>> newUserOwned,
    required ManifestClosure closure,
  }) {
    var next = _applyHashes(lock, newHashes);

    final closureUnits = <LockLayer, Set<String>>{
      LockLayer.foundation: closure.foundation.toSet(),
      LockLayer.theme: closure.theme.toSet(),
      LockLayer.primitives: closure.primitives.toSet(),
    };
    for (final layer in LockLayer.values) {
      final units = closureUnits[layer] ?? const <String>{};
      final files = newLayerFiles[layer] ?? const <String, String>{};
      if (units.isNotEmpty || files.isNotEmpty) {
        next = next.mergeLayer(layer, units: units, files: files);
      }
    }

    for (final id in closure.components) {
      final manifestComponent = manifest.components[id];
      if (manifestComponent == null) {
        continue;
      }
      final existing = next.componentFor(id);
      final files = {...?existing?.files, ...?newComponentFiles[id]};
      final userOwned = {...?existing?.userOwned, ...?newUserOwned[id]};
      for (final path in files.keys.toList()) {
        userOwned.remove(path);
      }
      next = next.upsertComponent(
        LockComponent(
          id: id,
          version: existing?.version,
          files: files,
          userOwned: userOwned,
          deps: _lockDeps(manifestComponent.deps),
          api: lockApiFor(manifestComponent.api),
        ),
      );
    }

    // A block owns no user-owned file, so its record is exactly the registry
    // files on disk; an unknown block (registry moved on) keeps its record.
    for (final id in closure.blocks) {
      final manifestBlock = manifest.blocks[id];
      if (manifestBlock == null) {
        continue;
      }
      final existing = next.blockFor(id);
      final files = {...?existing?.files, ...?newBlockFiles[id]};
      next = next.upsertBlock(
        LockBlock(
          id: id,
          version: existing?.version,
          files: files,
          deps: _lockDeps(manifestBlock.deps),
        ),
      );
    }

    // A flow mirrors a block: no user-owned file, no public symbols.
    for (final id in closure.flows) {
      final manifestFlow = manifest.flows[id];
      if (manifestFlow == null) {
        continue;
      }
      final existing = next.flowFor(id);
      final files = {...?existing?.files, ...?newFlowFiles[id]};
      next = next.upsertFlow(
        LockFlow(
          id: id,
          version: existing?.version,
          files: files,
          deps: LockComponentDeps(
            foundation: _sorted(manifestFlow.deps.foundation),
            theme: _sorted(manifestFlow.deps.theme),
            primitives: _sorted(manifestFlow.deps.primitives),
            components: _sorted(manifestFlow.deps.components),
          ),
        ),
      );
    }

    if (manifestSha256.isNotEmpty) {
      next = next.withRegistry(
        next.registry.copyWith(manifestSha256: manifestSha256),
      );
    }
    return next;
  }

  DashcnLock _applyHashes(DashcnLock lock, Map<String, String> newHashes) {
    if (newHashes.isEmpty) {
      return lock;
    }
    var next = lock;
    for (final layer in LockLayer.values) {
      final state = lock.layerState(layer);
      final files = {...state.files};
      var changed = false;
      for (final entry in newHashes.entries) {
        if (files.containsKey(entry.key)) {
          files[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        next = next.putLayer(
          layer,
          LockLayerState(units: state.units, files: files),
        );
      }
    }
    for (final component in lock.components) {
      final files = {...component.files};
      var changed = false;
      for (final entry in newHashes.entries) {
        if (files.containsKey(entry.key)) {
          files[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        next = next.upsertComponent(component.copyWith(files: files));
      }
    }
    for (final block in lock.blocks) {
      final files = {...block.files};
      var changed = false;
      for (final entry in newHashes.entries) {
        if (files.containsKey(entry.key)) {
          files[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        next = next.upsertBlock(block.copyWith(files: files));
      }
    }
    for (final flow in lock.flows) {
      final files = {...flow.files};
      var changed = false;
      for (final entry in newHashes.entries) {
        if (files.containsKey(entry.key)) {
          files[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        next = next.upsertFlow(flow.copyWith(files: files));
      }
    }
    return next;
  }

  static LockComponentDeps _lockDeps(ManifestComponentDeps deps) {
    return LockComponentDeps(
      foundation: _sorted(deps.foundation),
      theme: _sorted(deps.theme),
      primitives: _sorted(deps.primitives),
      components: _sorted(deps.components),
    );
  }

  static List<String> _sorted(Iterable<String> values) =>
      values.toSet().toList()..sort();
}

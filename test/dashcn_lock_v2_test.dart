import 'dart:convert';

import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:test/test.dart';

String sha(String content) => FileHashing.ofText(content);

LockComponent buttonComponent() {
  return LockComponent(
    id: 'button',
    version: '1.0.0',
    files: {
      'lib/ui/dashcn/components/button/button.dart': sha('button.dart'),
      'lib/ui/dashcn/components/button/button_style.dart':
          sha('button_style.dart'),
    },
    userOwned: {
      'lib/ui/dashcn/components/button/button_theme.dart':
          sha('button_theme.dart'),
    },
    deps: const LockComponentDeps(
      foundation: ['data', 'gap'],
      theme: ['theme'],
      primitives: ['clickable'],
    ),
    api: const LockComponentApi(
      byKind: {
        'classes': ['Button', 'ButtonGroup'],
        'enums': ['ButtonVariant'],
      },
    ),
  );
}

DashcnLock sampleLock() {
  return DashcnLock(
    registry: LockRegistry(
      name: 'dashcn',
      ref: 'refactor/rearchitecture',
      manifestSha256: sha('manifest.json'),
      generatedAt: '2026-10-09T00:00:00Z',
    ),
    installRoot: 'lib/ui/dashcn',
    theme: LockThemeSelection(
      id: 'vercel',
      path: 'lib/ui/dashcn/theme/app_theme.dart',
      sha256: sha('app_theme.dart'),
    ),
    layers: {
      LockLayer.foundation: LockLayerState(
        units: ['data', 'gap'],
        files: {'lib/ui/dashcn/foundation/data.dart': sha('data.dart')},
      ),
      LockLayer.theme: LockLayerState(
        units: ['theme'],
        files: {'lib/ui/dashcn/theme/theme.dart': sha('theme.dart')},
      ),
      LockLayer.primitives: LockLayerState(
        units: ['clickable'],
        files: {
          'lib/ui/dashcn/primitives/clickable.dart': sha('clickable.dart')
        },
      ),
    },
    components: [buttonComponent()],
  );
}

void main() {
  group('DashcnLock round-trip', () {
    test('survives toJson -> fromJson unchanged', () {
      final lock = sampleLock();
      final encoded = jsonEncode(lock.toJson());
      final reparsed = DashcnLock.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(jsonEncode(reparsed.toJson()), encoded);
      expect(reparsed.lockfileVersion, kLockfileVersion);
      expect(reparsed.registry.name, 'dashcn');
      expect(reparsed.registry.ref, 'refactor/rearchitecture');
      expect(reparsed.registry.manifestSha256, sha('manifest.json'));
      expect(reparsed.installRoot, 'lib/ui/dashcn');
      expect(reparsed.theme!.id, 'vercel');
      expect(reparsed.layerState(LockLayer.foundation).units, ['data', 'gap']);
      expect(reparsed.componentIds, ['button']);
      expect(reparsed.componentFor('button')!.userOwnedPaths, [
        'lib/ui/dashcn/components/button/button_theme.dart',
      ]);
      expect(reparsed.componentFor('button')!.api.symbols, {
        'Button',
        'ButtonGroup',
        'ButtonVariant',
      });
    });

    test('component mode defaults to copy and round-trips package', () {
      final copy = LockComponent(id: 'button');
      expect(copy.mode, LockComponentMode.copy);
      expect(
        LockComponent.fromJson(copy.toJson()).mode,
        LockComponentMode.copy,
      );

      final package =
          LockComponent(id: 'button', mode: LockComponentMode.package);
      expect(package.toJson()['mode'], 'package');
      expect(
        LockComponent.fromJson(package.toJson()).mode,
        LockComponentMode.package,
      );
      final withoutMode = Map<String, dynamic>.from(package.toJson())
        ..remove('mode');
      expect(
        LockComponent.fromJson(withoutMode).mode,
        LockComponentMode.copy,
      );
    });

    test('serialises deterministically: sorted keys, sorted components', () {
      final lock = DashcnLock(
        installRoot: 'lib/ui/dashcn',
        components: [
          LockComponent(
              id: 'tabs', files: {'b.dart': sha('b'), 'a.dart': sha('a')}),
          LockComponent(id: 'button', files: {'z.dart': sha('z')}),
        ],
      );

      final json = lock.toJson();
      final components = json['components']! as List;
      expect((components.first as Map)['id'], 'button');
      expect(
        ((components.last as Map)['files']! as Map).keys,
        ['a.dart', 'b.dart'],
      );
      expect(
          (json['layers']! as Map).keys, ['foundation', 'theme', 'primitives']);
    });

    test('tolerates a minimal document', () {
      final lock = DashcnLock.fromJson(const {'lockfileVersion': 2});

      expect(lock.components, isEmpty);
      expect(lock.layers, isEmpty);
      expect(lock.theme, isNull);
      expect(lock.installRoot, '');
      expect(lock.isEmpty, isTrue);
      expect(lock.layerState(LockLayer.theme).isEmpty, isTrue);
    });

    test('rejects a v1 lock', () {
      expect(
        () => DashcnLock.fromJson(const {
          'lockfileVersion': 1,
          'registries': <String, dynamic>{},
          'components': <dynamic>[],
        }),
        throwsA(
          isA<LockFileException>().having(
            (error) => error.message,
            'message',
            contains('no longer supported'),
          ),
        ),
      );
      expect(
        () => DashcnLock.fromJson(const <String, dynamic>{}),
        throwsA(isA<LockFileException>()),
      );
    });

    test('rejects a non sha256 digest', () {
      expect(
        () => DashcnLock.fromJson({
          'lockfileVersion': 2,
          'layers': {
            'foundation': {
              'files': {'lib/ui/dashcn/foundation/data.dart': 'not-a-digest'},
            },
          },
        }),
        throwsA(
          isA<LockFileException>().having(
            (error) => error.message,
            'message',
            contains('data.dart'),
          ),
        ),
      );
    });

    test('normalises windows separators and ./ prefixes in paths', () {
      final lock = DashcnLock.fromJson({
        'lockfileVersion': 2,
        'components': [
          {
            'id': 'button',
            'files': {
              '.\\lib\\ui\\dashcn\\components\\button\\button.dart': sha('x')
            },
          },
        ],
      });

      expect(
        lock.componentFor('button')!.paths,
        ['lib/ui/dashcn/components/button/button.dart'],
      );
    });

    test('ignores unknown layer keys', () {
      final lock = DashcnLock.fromJson({
        'lockfileVersion': 2,
        'layers': {
          'foundation': {
            'units': ['data'],
            'files': {'lib/ui/dashcn/foundation/data.dart': sha('x')},
          },
          'widgets': {
            'units': ['nope']
          },
        },
      });

      expect(lock.layers.keys, [LockLayer.foundation]);
    });
  });

  group('user-owned files', () {
    test('are never updatable and stay out of registryOwnedPaths', () {
      final lock = sampleLock();
      final themeFile = 'lib/ui/dashcn/components/button/button_theme.dart';

      expect(lock.isUserOwned(themeFile), isTrue);
      expect(lock.userOwnedPaths, {themeFile});
      expect(lock.registryOwnedPaths.contains(themeFile), isFalse);
      expect(lock.updatablePaths.contains(themeFile), isFalse);
      expect(lock.updatablePaths,
          contains('lib/ui/dashcn/components/button/button.dart'));
      expect(
        lock.componentFor('button')!.updatableFiles.keys,
        isNot(contains(themeFile)),
      );
      expect(lock.ownerOf(themeFile), 'button');
    });

    test('a path in both files and userOwned is a corrupt lock', () {
      const path = 'lib/ui/dashcn/components/button/button_theme.dart';
      expect(
        () => LockComponent(
          id: 'button',
          files: {path: sha('x')},
          userOwned: {path: sha('x')},
        ),
        throwsA(
          isA<LockFileException>().having(
            (error) => error.message,
            'message',
            contains('never be registry-owned'),
          ),
        ),
      );
    });

    test('withUserOwnedFile moves a path out of the updatable set', () {
      const path = 'lib/ui/dashcn/components/button/button_theme.dart';
      final component = LockComponent(id: 'button', files: {path: sha('x')});

      final owned = component.withUserOwnedFile(path, sha('x'));

      expect(owned.files, isEmpty);
      expect(owned.isUserOwned(path), isTrue);
      expect(owned.updatableFiles, isEmpty);
    });

    test('remove drops the component and exposes its user files for purge', () {
      final lock = sampleLock();

      final removed = lock.removeComponent('button');
      expect(removed.components, isEmpty);
      expect(
        removed.updatablePaths,
        isNot(contains('lib/ui/dashcn/components/button/button.dart')),
      );
      // `remove` leaves the user file on disk unless --purge-user-themes is
      // given; the dropped record is what tells it which files that is.
      expect(lock.componentFor('button')!.userOwnedPaths, [
        'lib/ui/dashcn/components/button/button_theme.dart',
      ]);
    });
  });

  group('merge', () {
    test('unions layer units and files, keeping the newest hashes', () {
      final current = DashcnLock(
        layers: {
          LockLayer.foundation: LockLayerState(
            units: ['data'],
            files: {'lib/ui/dashcn/foundation/data.dart': sha('old')},
          ),
        },
      );
      final incoming = DashcnLock(
        registry: const LockRegistry(name: 'dashcn'),
        installRoot: 'lib/ui/dashcn',
        layers: {
          LockLayer.foundation: LockLayerState(
            units: ['gap'],
            files: {'lib/ui/dashcn/foundation/gap.dart': sha('gap')},
          ),
        },
      );

      final merged = current.mergeWith(incoming);

      expect(merged.layerState(LockLayer.foundation).units, ['data', 'gap']);
      expect(merged.layerState(LockLayer.foundation).files.keys, [
        'lib/ui/dashcn/foundation/data.dart',
        'lib/ui/dashcn/foundation/gap.dart',
      ]);
      expect(
        merged
            .layerState(LockLayer.foundation)
            .files['lib/ui/dashcn/foundation/data.dart'],
        sha('old'),
      );
      expect(merged.registry.name, 'dashcn');
      expect(merged.installRoot, 'lib/ui/dashcn');
    });

    test('upserts components by id and keeps the list sorted', () {
      final lock = DashcnLock(components: [buttonComponent()])
          .upsertComponent(LockComponent(id: 'alert'))
          .upsertComponent(
            LockComponent(
              id: 'button',
              files: {
                'lib/ui/dashcn/components/button/button.dart': sha('new')
              },
            ),
          );

      expect(lock.componentIds, ['alert', 'button']);
      expect(
        lock.componentFor('button')!.files.values.single,
        sha('new'),
      );
    });

    test('mergeWith lets the incoming component replace an installed one', () {
      final installed = DashcnLock(components: [buttonComponent()]);
      final incoming = DashcnLock(
        components: [
          LockComponent(
            id: 'button',
            files: {'lib/ui/dashcn/components/button/button.dart': sha('new')},
          ),
        ],
      );

      expect(installed.mergeWith(incoming).componentFor('button')!.paths, [
        'lib/ui/dashcn/components/button/button.dart',
      ]);
    });
  });

  group('api', () {
    test('ignores owner -> symbol maps (not owned symbols)', () {
      final api = LockComponentApi.fromJson({
        'classes': ['Button'],
        'enums': ['ButtonVariant'],
        // Manifest maps such as providedByPrimitives name the owning unit,
        // not symbols this component defines, so they are ignored.
        'providedByPrimitives': {
          'file_value': ['FileValue'],
        },
        'reExportedFromComponents': {
          'menu': ['MenuPopup'],
        },
        'ignored': 42,
      });

      expect(api.symbolsFor('classes'), ['Button']);
      expect(api.symbols, {'Button', 'ButtonVariant'});
      expect(api.declares('Button'), isTrue);
      expect(api.declares('FileValue'), isFalse);
      expect(api.declares('MenuPopup'), isFalse);
      expect(api.declares('ButtonGroup'), isFalse);
      expect(api.toJson(), {
        'classes': ['Button'],
        'enums': ['ButtonVariant'],
      });
    });

    test('mergeWith unions symbols per kind', () {
      const left = LockComponentApi(
        byKind: {
          'classes': ['Button'],
        },
      );
      const right = LockComponentApi(
        byKind: {
          'classes': ['ButtonGroup'],
          'enums': ['ButtonSize'],
        },
      );

      final merged = left.mergeWith(right);

      expect(merged.symbolsFor('classes'), ['Button', 'ButtonGroup']);
      expect(merged.symbolsFor('enums'), ['ButtonSize']);
    });

    test('a component without api declares nothing', () {
      final component = LockComponent(id: 'button');

      expect(component.api.symbols, isEmpty);
      expect(component.api.toJson(), isEmpty);
      expect(component.copyWith(api: buttonComponent().api).api.symbols, {
        'Button',
        'ButtonGroup',
        'ButtonVariant',
      });
    });
  });

  group('queries', () {
    test('ownerOf resolves component, layer and theme paths', () {
      final lock = sampleLock();

      expect(lock.ownerOf('lib/ui/dashcn/components/button/button.dart'),
          'button');
      expect(lock.ownerOf('lib/ui/dashcn/primitives/clickable.dart'),
          'primitives');
      expect(lock.ownerOf('lib/ui/dashcn/theme/app_theme.dart'), 'theme');
      expect(lock.ownerOf('lib/ui/dashcn/other.dart'), isNull);
    });

    test('dependentsOf counts user-owned files too', () {
      final lock = sampleLock();

      expect(
        lock.dependentsOf(
            {'lib/ui/dashcn/components/button/button_theme.dart'}),
        {'button'},
      );
      expect(lock.dependentsOf({'lib/ui/dashcn/nothing.dart'}), isEmpty);
    });

    test('registry.hasMoved compares manifest digests', () {
      final registry = LockRegistry(manifestSha256: sha('a'));

      expect(registry.hasMoved(sha('a')), isFalse);
      expect(registry.hasMoved(sha('b')), isTrue);
      expect(registry.hasMoved(''), isFalse);
      expect(
        const LockRegistry().hasMoved(sha('a')),
        isFalse,
      );
    });

    test('deps resolve per layer and merge as a union', () {
      const deps = LockComponentDeps(
        foundation: ['data'],
        primitives: ['clickable'],
      );

      expect(deps.forLayer(LockLayer.foundation), ['data']);
      expect(deps.references(LockLayer.primitives, 'clickable'), isTrue);
      expect(deps.references(LockLayer.theme, 'theme'), isFalse);
      expect(deps.layerUnits, {'data', 'clickable'});
      expect(
        deps
            .mergeWith(const LockComponentDeps(primitives: ['overlay']))
            .primitives,
        ['clickable', 'overlay'],
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/eject/eject_service.dart';
import 'package:dashcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/package_mode/package_add_service.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_pub_runner.dart';
import 'support/v2_registry_fixture.dart';

void main() {
  group('eject', () {
    late V2RegistryFixture fixture;
    late RegistryManifest manifest;
    late Directory project;
    late FakePubCommandRunner runner;

    setUp(() {
      fixture = V2RegistryFixture.create();
      manifest = RegistryManifest.fromJson(
        jsonDecode(
          File(p.join(fixture.root, 'manifests', 'registry.json'))
              .readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      project = Directory.systemTemp.createTempSync('eject_app_');
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
        'name: eject_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
      runner = FakePubCommandRunner();
    });

    tearDown(() {
      fixture.dispose();
      project.deleteSync(recursive: true);
    });

    EjectService buildService() => EjectService(
          manifest: manifest,
          projectRoot: project.path,
          reader: DirectoryRegistryFileReader(fixture.root),
          installRoot: 'lib/ui/dashcn',
          manifestSha256: 'a' * 64,
          lockRepo: LockRepository(project.path),
          pubRunner: runner,
        );

    Future<void> addPackage(String id) => PackageAddService(
          manifest: manifest,
          projectRoot: project.path,
          installRoot: 'lib/ui/dashcn',
          lockRepo: LockRepository(project.path),
          pubRunner: runner,
        ).add([id]);

    String owned(String rel) =>
        File(p.join(project.path, p.normalize(rel))).readAsStringSync();

    bool exists(String rel) =>
        File(p.join(project.path, p.normalize(rel))).existsSync();

    void writeApp(String rel, String content) {
      final file = File(p.join(project.path, p.normalize(rel)));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('copies sources, flips the lock, retargets a direct import', () async {
      await addPackage('button');
      writeApp(
        'lib/main.dart',
        "import 'package:dashcn/components/button.dart';\n"
            '\n'
            'void main() => Button();\n',
      );

      final report = await buildService().eject('button');

      expect(report.applied, isTrue);
      expect(
        exists('lib/ui/dashcn/components/button/button.dart'),
        isTrue,
      );
      final lock = await LockRepository(project.path).load();
      expect(lock.componentFor('button')!.mode, LockComponentMode.copy);
      expect(
        owned('lib/main.dart'),
        contains('ui/dashcn/components/button/button.dart'),
      );
      expect(owned('lib/main.dart'), isNot(contains('package:dashcn')));
    });

    test('barrel use gains an owned import plus a hide', () async {
      await addPackage('button');
      writeApp(
        'lib/screen.dart',
        "import 'package:dashcn/dashcn.dart';\n"
            '\n'
            'void build() => Button();\n',
      );

      final report = await buildService().eject('button');

      expect(report.rewrites.keys, contains('lib/screen.dart'));
      final content = owned('lib/screen.dart');
      expect(
        content,
        contains("import 'package:dashcn/dashcn.dart' hide Button;"),
      );
      expect(
        content,
        contains("import 'ui/dashcn/components/button/button.dart';"),
      );
    });

    test('prefixed barrel use is unprefixed with a hide', () async {
      await addPackage('button');
      writeApp(
        'lib/screen.dart',
        "import 'package:dashcn/dashcn.dart' as ui;\n"
            '\n'
            'void build() => ui.Button();\n',
      );

      await buildService().eject('button');

      final content = owned('lib/screen.dart');
      expect(content, contains('hide Button'));
      expect(content, contains('() => Button();'));
      expect(content, isNot(contains('ui.Button')));
    });

    test('barrel show is narrowed to the remaining symbols', () async {
      await addPackage('button');
      writeApp(
        'lib/screen.dart',
        "import 'package:dashcn/dashcn.dart' show Button, Input;\n"
            '\n'
            'void build() => Button();\n',
      );

      await buildService().eject('button');

      final content = owned('lib/screen.dart');
      expect(content, contains('show Input'));
      expect(content, isNot(contains('show Button')));
      expect(content, contains("import 'ui/dashcn/"));
    });

    test('dry run prints the plan and writes nothing', () async {
      await addPackage('button');
      writeApp(
        'lib/main.dart',
        "import 'package:dashcn/components/button.dart';\n",
      );

      final report = await buildService().eject('button', dryRun: true);

      expect(report.applied, isFalse);
      expect(
        exists('lib/ui/dashcn/components/button/button.dart'),
        isFalse,
      );
      expect(owned('lib/main.dart'), contains('package:dashcn'));
      final lock = await LockRepository(project.path).load();
      expect(lock.componentFor('button')!.mode, LockComponentMode.package);
      expect(report.rewrites.keys, contains('lib/main.dart'));
    });

    test('refuses unknown and already-owned components', () async {
      await expectLater(
        buildService().eject('nope'),
        throwsA(isA<EjectException>()),
      );
      await addPackage('button');
      await buildService().eject('button');
      await expectLater(
        buildService().eject('button'),
        throwsA(isA<EjectException>()),
      );
    });

    test('refuses dirty conflicts unless forced', () async {
      await addPackage('button');
      final first = await buildService().eject('button', dryRun: true);
      expect(first.files, isNotEmpty);

      // Locally modify one file the eject would write.
      final target = File(
        p.join(
          project.path,
          'lib/ui/dashcn/components/button/button.dart',
        ),
      );
      target.parent.createSync(recursive: true);
      target.writeAsStringSync('// locally modified\n');

      // Reset the lock to package mode to eject again.
      var lock = await LockRepository(project.path).load();
      await LockRepository(project.path).save(
        lock.upsertComponent(
          lock.componentFor('button')!.copyWith(
            files: {},
            mode: LockComponentMode.package,
          ),
        ),
      );

      await expectLater(
        buildService().eject('button'),
        throwsA(isA<EjectConflictException>()),
      );
      final forced = await buildService().eject('button', force: true);
      expect(forced.applied, isTrue);
      expect(
        owned('lib/ui/dashcn/components/button/button.dart'),
        contains('class Button'),
      );
      lock = await LockRepository(project.path).load();
      expect(lock.componentFor('button')!.mode, LockComponentMode.copy);
    });

    test('with-deps ejects transitive components too', () async {
      await addPackage('input');
      await addPackage('button');

      await buildService().eject('input', withDeps: true);

      expect(exists('lib/ui/dashcn/components/input/input.dart'), isTrue);
      expect(exists('lib/ui/dashcn/components/button/button.dart'), isTrue);
      final lock = await LockRepository(project.path).load();
      expect(lock.componentFor('input')!.mode, LockComponentMode.copy);
      expect(lock.componentFor('button')!.mode, LockComponentMode.copy);
    });
  });
}

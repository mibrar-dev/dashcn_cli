import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/package_mode/package_add_service.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_pub_runner.dart';

void main() {
  final fixtureRoot = p.absolute('test/fixtures/registry_v2');
  late RegistryManifest manifest;
  late Directory project;
  late FakePubCommandRunner runner;

  setUpAll(() {
    manifest = RegistryManifest.fromJson(
      jsonDecode(File(p.join(fixtureRoot, 'registry.json')).readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  setUp(() {
    project = Directory.systemTemp.createTempSync('package_add_');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
      'name: package_add_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
    );
    runner = FakePubCommandRunner();
  });

  tearDown(() => project.deleteSync(recursive: true));

  PackageAddService buildService() => PackageAddService(
        manifest: manifest,
        projectRoot: project.path,
        installRoot: 'lib/ui/dashcn',
        lockRepo: LockRepository(project.path),
        pubRunner: runner,
      );

  bool exists(String rel) =>
      File(p.join(project.path, p.normalize(rel))).existsSync();

  group('add --package', () {
    test('runs pub add, writes no sources, records mode package', () async {
      final report = await buildService().add(['button']);

      expect(runner.pubAdds, [
        ['dashcn:^0.1.0'],
      ]);
      expect(exists('lib/ui/dashcn/components/button/button.dart'), isFalse);
      expect(exists('dashcn.lock'), isTrue);
      final lock = await LockRepository(project.path).load();
      final entry = lock.componentFor('button')!;
      expect(entry.mode, LockComponentMode.package);
      expect(entry.files, isEmpty);
      expect(entry.api.symbols, contains('Button'));
      expect(report.imports['button'], 'package:dashcn/components/button.dart');
      expect(report.applied, isTrue);
    });

    test('path mode runs pub add --path', () async {
      final report = await buildService().add(
        ['button'],
        path: '/kit/dashcn',
      );

      expect(runner.pubAdds, isEmpty);
      expect(runner.pubPathAdds, [
        (package: 'dashcn', path: '/kit/dashcn'),
      ]);
      expect(report.pubArgs, ['pub', 'add', 'dashcn', '--path', '/kit/dashcn']);
      final lock = await LockRepository(project.path).load();
      expect(lock.componentFor('button')!.mode, LockComponentMode.package);
    });

    test('dry run plans without writing', () async {
      final report = await buildService().add(['button'], dryRun: true);

      expect(report.applied, isFalse);
      expect(runner.pubAdds, isEmpty);
      expect(exists('dashcn.lock'), isFalse);
      expect(report.imports['button'], 'package:dashcn/components/button.dart');
    });

    test('refuses blocks and unknown ids', () async {
      await expectLater(
        buildService().add(['login-01']),
        throwsA(isA<PackageAddException>()),
      );
      expect(exists('dashcn.lock'), isFalse);
    });
  });
}

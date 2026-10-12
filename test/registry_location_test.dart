import 'dart:io';

import 'package:dashcn_cli/src/registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('RegistryLocation local path fallback', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('registry_location_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'reads components.json when relative path is registry/components.json and root already ends with registry',
      () async {
        final registryRoot = Directory(p.join(tempDir.path, 'registry'))
          ..createSync(recursive: true);
        final components = File(p.join(registryRoot.path, 'components.json'));
        components.writeAsStringSync('{"components": []}');

        final location = RegistryLocation.local(registryRoot.path);
        final content = await location.readString('registry/components.json');

        expect(content, '{"components": []}');
      },
    );

    test('still supports normal registry/components.json when root is parent',
        () async {
      final registryDir = Directory(p.join(tempDir.path, 'registry'))
        ..createSync(recursive: true);
      final components = File(p.join(registryDir.path, 'components.json'));
      components.writeAsStringSync(
          '{"components": [{"id":"button","name":"Button"}]}');

      final location = RegistryLocation.local(tempDir.path);
      final content = await location.readString('registry/components.json');

      expect(content, contains('"button"'));
    });
  });
}

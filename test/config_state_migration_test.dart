import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('config and state normalization', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dashcn_normalize_test_');
      Directory(p.join(tempDir.path, '.dashcn')).createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('normalizes older-shaped config to registries map', () async {
      final oldConfig = jsonEncode({
        'registryMode': 'remote',
        'registryUrl': 'https://example.com/registry',
        'installPath': 'lib/ui/dashcn',
        'sharedPath': 'lib/ui/dashcn/shared',
        'includeReadme': false,
        'includeMeta': true,
        'includePreview': false,
        'includeFiles': ['meta'],
        'excludeFiles': ['preview'],
        'checkUpdates': true,
      });
      final configFile = File(p.join(tempDir.path, '.dashcn', 'config.json'));
      configFile.writeAsStringSync(oldConfig);

      final config = await DashcnConfig.load(tempDir.path);
      expect(config.effectiveDefaultNamespace, 'dashcn');
      expect(config.registries, isNotNull);
      expect(config.registries!.containsKey('dashcn'), isTrue);
      expect(config.registryUrl, 'https://example.com/registry');
      expect(config.installPath, 'lib/ui/dashcn');
      expect(config.sharedPath, 'lib/ui/dashcn/shared');
      expect(config.includeFiles, ['meta']);
      expect(config.excludeFiles, ['preview']);

      final normalizedJson =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      expect(normalizedJson['registries'], isA<Map>());
      expect(normalizedJson['defaultNamespace'], 'dashcn');
      final dashcn = (normalizedJson['registries'] as Map)['dashcn'] as Map;
      expect(dashcn['registryUrl'], 'https://example.com/registry');
      expect(dashcn['includeFiles'], ['meta']);
      expect(dashcn['excludeFiles'], ['preview']);
    });

    test('loads new config format fixture', () async {
      final newConfig =
          File('test/fixtures/new_config.json').readAsStringSync();
      final configFile = File(p.join(tempDir.path, '.dashcn', 'config.json'));
      configFile.writeAsStringSync(newConfig);

      final config = await DashcnConfig.load(tempDir.path);
      expect(config.registries, isNotNull);
      expect(config.registries!['dashcn']?.enabled, isTrue);
      expect(config.installPath, 'lib/ui/dashcn');
      expect(config.sharedPath, 'lib/ui/dashcn/shared');
      expect(config.includeFiles, ['meta']);
      expect(config.excludeFiles, ['preview']);
    });

    test('normalizes older-shaped state to registries map', () async {
      final oldState = jsonEncode({
        'installPath': 'lib/ui/dashcn',
        'sharedPath': 'lib/ui/dashcn/shared',
        'themeId': 'modern-minimal',
        'managedDependencies': ['gap', 'data_widget'],
      });
      final stateFile = File(p.join(tempDir.path, '.dashcn', 'state.json'));
      stateFile.writeAsStringSync(oldState);

      final state = await DashcnState.load(tempDir.path);
      expect(state.registries, isNotNull);
      expect(state.registries!['dashcn'], isNotNull);
      expect(state.installPath, 'lib/ui/dashcn');
      expect(state.sharedPath, 'lib/ui/dashcn/shared');
      expect(state.managedDependencies, containsAll(['gap', 'data_widget']));

      final normalizedJson =
          jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
      expect(normalizedJson['registries'], isA<Map>());
      expect(
        ((normalizedJson['registries'] as Map)['dashcn'] as Map)['installPath'],
        'lib/ui/dashcn',
      );
      expect(
        normalizedJson['managedDependencies'],
        containsAll(['gap', 'data_widget']),
      );
    });

    test('loads new state format fixture', () async {
      final newState = File('test/fixtures/new_state.json').readAsStringSync();
      final stateFile = File(p.join(tempDir.path, '.dashcn', 'state.json'));
      stateFile.writeAsStringSync(newState);

      final state = await DashcnState.load(tempDir.path);
      expect(state.registries, isNotNull);
      expect(state.registries!['dashcn']?.themeId, 'modern-minimal');
      expect(state.managedDependencies, containsAll(['gap', 'data_widget']));
    });

    test('missing config and state files load empty defaults', () async {
      final configPath = p.join(tempDir.path, '.dashcn', 'config.json');
      if (File(configPath).existsSync()) {
        File(configPath).deleteSync();
      }
      final statePath = p.join(tempDir.path, '.dashcn', 'state.json');
      if (File(statePath).existsSync()) {
        File(statePath).deleteSync();
      }

      final config = await DashcnConfig.load(tempDir.path);
      final state = await DashcnState.load(tempDir.path);

      expect(config.registries, isNull);
      expect(state.registries, isNull);
    });

    test('invalid config json throws typed load error', () async {
      final configFile = File(p.join(tempDir.path, '.dashcn', 'config.json'));
      configFile.writeAsStringSync('{not-json');

      await expectLater(
        () => DashcnConfig.load(tempDir.path),
        throwsA(isA<DashcnConfigLoadException>()),
      );
    });

    test('invalid state json throws typed load error', () async {
      final stateFile = File(p.join(tempDir.path, '.dashcn', 'state.json'));
      stateFile.writeAsStringSync('{not-json');

      await expectLater(
        () => DashcnState.load(tempDir.path),
        throwsA(isA<DashcnStateLoadException>()),
      );
    });
  });
}

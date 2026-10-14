import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/reset/project_refresh_service.dart';
import 'package:dashcn_cli/src/init_action_engine.dart';
import 'package:dashcn_cli/src/registry_directory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProjectRefreshService', () {
    late Directory tempRoot;
    late Directory projectRoot;
    late Directory registryRoot;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('project_refresh_');
      projectRoot = Directory(p.join(tempRoot.path, 'app'))..createSync();
      registryRoot = Directory(p.join(tempRoot.path, 'registry'))
        ..createSync(recursive: true);

      await File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsString(
        [
          'name: refresh_test',
          'description: refresh test',
          'dependencies:',
          '  flutter:',
          '    sdk: flutter',
        ].join('\n'),
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test(
        'repairs only missing scaffold files without overwriting existing files or component installs',
        () async {
      await _writeLegacyProjectConfig(
        projectRoot: projectRoot.path,
        registryBaseUrl: registryRoot.path,
      );
      await _writeInlineJournal(
        projectRoot: projectRoot.path,
        namespace: 'dashcn',
        filesWritten: [
          'lib/ui/dashcn/shared/theme/theme.dart',
          'lib/ui/dashcn/shared/util/util.dart',
          'lib/ui/dashcn/components/button.dart',
        ],
      );

      await File(p.join(
              registryRoot.path, 'registry', 'shared', 'theme', 'theme.dart'))
          .create(recursive: true);
      await File(p.join(
              registryRoot.path, 'registry', 'shared', 'theme', 'theme.dart'))
          .writeAsString('registry theme');
      await File(
        p.join(registryRoot.path, 'registry', 'shared', 'util', 'util.dart'),
      ).create(recursive: true);
      await File(
        p.join(registryRoot.path, 'registry', 'shared', 'util', 'util.dart'),
      ).writeAsString('registry util');
      await File(
        p.join(registryRoot.path, 'registry', 'components', 'button.dart'),
      ).create(recursive: true);
      await File(
        p.join(registryRoot.path, 'registry', 'components', 'button.dart'),
      ).writeAsString('registry button');

      final themeFile = File(
        p.join(projectRoot.path, 'lib', 'ui', 'dashcn', 'shared', 'theme',
            'theme.dart'),
      )..createSync(recursive: true);
      await themeFile.writeAsString('custom theme');

      final engine = InitActionEngine();
      final service = ProjectRefreshService(
        projectRoot: projectRoot.path,
        executeActions: engine.executeActions,
      );

      final result = await service.refresh(
        registry: _entry(
          baseUrl: registryRoot.path,
          actions: _baseActions(),
        ),
      );

      expect(result.executionResult.filesWritten, 1);
      expect(
        result.missingFiles,
        ['lib/ui/dashcn/shared/util/util.dart'],
      );
      expect(themeFile.readAsStringSync(), 'custom theme');
      expect(
        File(
          p.join(projectRoot.path, 'lib', 'ui', 'dashcn', 'shared', 'util',
              'util.dart'),
        ).readAsStringSync(),
        'registry util',
      );
      expect(
        File(
          p.join(projectRoot.path, 'lib', 'ui', 'dashcn', 'components',
              'button.dart'),
        ).existsSync(),
        isFalse,
      );
    });

    test(
        're-offers optional init actions only while their scaffold outputs are absent',
        () async {
      await _writeLegacyProjectConfig(
        projectRoot: projectRoot.path,
        registryBaseUrl: registryRoot.path,
      );
      await _writeInlineJournal(
        projectRoot: projectRoot.path,
        namespace: 'dashcn',
        filesWritten: ['lib/ui/dashcn/shared/theme/theme.dart'],
      );
      await File(p.join(registryRoot.path, 'registry', 'assets', 'logo.svg'))
          .create(recursive: true);
      await File(p.join(registryRoot.path, 'registry', 'assets', 'logo.svg'))
          .writeAsString('<svg>logo</svg>');

      var promptCount = 0;
      final engine = InitActionEngine();
      final service = ProjectRefreshService(
        projectRoot: projectRoot.path,
        executeActions: engine.executeActions,
      );

      final skipped = await service.refresh(
        registry: _entry(
          baseUrl: registryRoot.path,
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': '.',
              'files': ['registry/assets/logo.svg'],
              'optional': true,
              'promptLabel': 'Install optional logo?',
            },
          ],
        ),
        optionalActionDecider: (action) async {
          promptCount += 1;
          return false;
        },
      );

      expect(skipped.executionResult.filesWritten, 0);
      expect(promptCount, 1);
      expect(File(p.join(projectRoot.path, 'assets', 'logo.svg')).existsSync(),
          isFalse);

      promptCount = 0;
      final approved = await service.refresh(
        registry: _entry(
          baseUrl: registryRoot.path,
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': '.',
              'files': ['registry/assets/logo.svg'],
              'optional': true,
              'promptLabel': 'Install optional logo?',
            },
          ],
        ),
        optionalActionDecider: (action) async {
          promptCount += 1;
          return true;
        },
      );

      expect(approved.executionResult.filesWritten, 1);
      expect(approved.missingFiles, ['assets/logo.svg']);
      expect(promptCount, 1);
      expect(
        File(p.join(projectRoot.path, 'assets', 'logo.svg')).readAsStringSync(),
        '<svg>logo</svg>',
      );

      promptCount = 0;
      final alreadyComplete = await service.refresh(
        registry: _entry(
          baseUrl: registryRoot.path,
          actions: [
            {
              'type': 'copyFiles',
              'base': 'registry',
              'destBase': '.',
              'files': ['registry/assets/logo.svg'],
              'optional': true,
              'promptLabel': 'Install optional logo?',
            },
          ],
        ),
        optionalActionDecider: (action) async {
          promptCount += 1;
          return true;
        },
      );

      expect(alreadyComplete.executionResult.filesWritten, 0);
      expect(promptCount, 0);
    });

    test('repairs grouped directory-mapped files without path escape',
        () async {
      await _writeLegacyProjectConfig(
        projectRoot: projectRoot.path,
        registryBaseUrl: registryRoot.path,
      );
      await _writeInlineJournal(
        projectRoot: projectRoot.path,
        namespace: 'dashcn',
        filesWritten: [
          'lib/ui/dashcn/shared/localization/app_localizations.dart',
        ],
      );
      await File(
        p.join(
          registryRoot.path,
          'registry',
          'shared',
          'localization',
          'app_localizations.dart',
        ),
      ).create(recursive: true);
      await File(
        p.join(
          registryRoot.path,
          'registry',
          'shared',
          'localization',
          'app_localizations.dart',
        ),
      ).writeAsString('registry localization');

      final engine = InitActionEngine();
      final service = ProjectRefreshService(
        projectRoot: projectRoot.path,
        executeActions: engine.executeActions,
      );

      final result = await service.refresh(
        registry: _entry(
          baseUrl: registryRoot.path,
          actions: [
            {
              'type': 'copyFiles',
              'from': 'registry/shared',
              'to': 'lib/ui/dashcn/shared',
              'groups': [
                {
                  'id': 'localization',
                  'files': ['localization/app_localizations.dart'],
                },
              ],
            },
          ],
        ),
      );

      expect(result.executionResult.filesWritten, 1);
      expect(
        result.missingFiles,
        ['lib/ui/dashcn/shared/localization/app_localizations.dart'],
      );
      expect(
        File(
          p.join(
            projectRoot.path,
            'lib',
            'ui',
            'dashcn',
            'shared',
            'localization',
            'app_localizations.dart',
          ),
        ).readAsStringSync(),
        'registry localization',
      );
    });
  });
}

Future<void> _writeLegacyProjectConfig({
  required String projectRoot,
  required String registryBaseUrl,
}) async {
  final dashcnDir = Directory(p.join(projectRoot, '.dashcn'))
    ..createSync(recursive: true);
  await File(p.join(dashcnDir.path, 'config.json')).writeAsString(
    jsonEncode({
      'defaultNamespace': 'dashcn',
      'registryUrl': registryBaseUrl,
      'installPath': 'lib/ui/dashcn',
      'sharedPath': 'lib/ui/dashcn/shared',
    }),
  );
  await File(p.join(dashcnDir.path, 'state.json')).writeAsString(
    jsonEncode({
      'installPath': 'lib/ui/dashcn',
      'sharedPath': 'lib/ui/dashcn/shared',
      'managedDependencies': ['gap'],
    }),
  );
}

Future<void> _writeInlineJournal({
  required String projectRoot,
  required String namespace,
  required List<String> filesWritten,
}) async {
  await File(p.join(projectRoot, '.dashcn', 'inline_actions.json'))
      .writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'registries': {
        namespace: [
          {
            'category': 'init',
            'createdAt': DateTime.utc(2026, 5, 3, 12).toIso8601String(),
            'record': {
              'dirsCreated': ['lib/ui/dashcn/shared'],
              'filesWritten': filesWritten,
              'pubspecDelta': {
                'dependencies': {},
                'devDependencies': {},
                'flutterAssets': [],
                'flutterFonts': [],
              },
            },
          }
        ],
      },
    }),
  );
}

RegistryDirectoryEntry _entry({
  required String baseUrl,
  required List<Map<String, dynamic>> actions,
}) {
  return RegistryDirectoryEntry.fromJson({
    'id': 'dashcn_entry',
    'displayName': 'Dashcn',
    'minCliVersion': '0.1.0',
    'baseUrl': baseUrl,
    'install': {
      'namespace': 'dashcn',
      'root': 'lib/ui/dashcn',
    },
    'paths': {
      'componentsJson': 'components.json',
      'componentsSchemaJson': 'components.schema.json',
    },
    'capabilities': {
      'sharedGroups': true,
    },
    'trust': {'mode': 'none'},
    'init': {
      'version': 1,
      'actions': actions,
    },
  });
}

List<Map<String, dynamic>> _baseActions() {
  return [
    {
      'type': 'copyFiles',
      'base': 'registry',
      'destBase': 'lib/ui/dashcn',
      'files': ['registry/shared/theme/theme.dart'],
    },
    {
      'type': 'copyFiles',
      'base': 'registry',
      'destBase': 'lib/ui/dashcn',
      'files': ['registry/shared/util/util.dart'],
    },
    {
      'type': 'copyFiles',
      'base': 'registry',
      'destBase': 'lib/ui/dashcn',
      'files': ['registry/components/button.dart'],
    },
  ];
}

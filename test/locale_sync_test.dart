import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/installer/installer.dart';
import 'package:dashcn_cli/src/application/services/installer/installer_file_install_part.dart';
import 'package:dashcn_cli/src/application/services/locale/locale_sync_service.dart';
import 'package:dashcn_cli/src/application/services/locale/locale_tables.dart';
import 'package:dashcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:dashcn_cli/src/application/services/lockfile/lock_repository.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_component_checks.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_pub_runner.dart';
import 'support/locale_registry_fixture.dart';

void main() {
  late LocaleRegistryFixture fixture;
  late RegistryManifest manifest;
  late String manifestSha;
  late Directory project;
  late FakePubCommandRunner runner;

  setUpAll(() {
    fixture = LocaleRegistryFixture.create();
    final registryFile =
        File(p.join(fixture.root, 'manifests', 'registry.json'));
    manifest = RegistryManifest.fromJson(
      jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>,
    );
    manifestSha = FileHashing.ofBytes(registryFile.readAsBytesSync());
  });

  tearDownAll(() {
    Directory(fixture.root).deleteSync(recursive: true);
  });

  setUp(() {
    project = Directory.systemTemp.createTempSync('dashcn_locale_test_');
    runner = FakePubCommandRunner();
  });

  tearDown(() => project.delete(recursive: true));

  Installer buildInstaller() => Installer(
        manifest: manifest,
        projectRoot: project.path,
        reader: DirectoryRegistryFileReader(fixture.root),
        pubRunner: runner,
        manifestSha256: manifestSha,
      );

  LocaleSyncService buildService() => LocaleSyncService(
        source: fixture.source,
        manifest: manifest,
        projectRoot: project.path,
        installRoot: 'lib/ui/dashcn',
      );

  String readProject(String target) =>
      File(p.join(project.path, target)).readAsStringSync();

  bool existsProject(String target) =>
      File(p.join(project.path, target)).existsSync();

  group('registry schema', () {
    Map<String, dynamic> fixtureManifest() => jsonDecode(
          File(p.join(fixture.root, 'manifests', 'registry.json'))
              .readAsStringSync(),
        ) as Map<String, dynamic>;

    test('accepts sorted localizationKeys', () {
      final result = ManifestSchemaValidator.validate(fixtureManifest());
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    });

    test('older registries without localizationKeys stay valid', () {
      final data = fixtureManifest();
      for (final component in (data['components'] as Map).values) {
        (component as Map).remove('localizationKeys');
      }
      final parsed = RegistryManifest.fromJson(data);
      expect(parsed.hasLocalizationKeys, isFalse);
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    });

    test('rejects unsorted localizationKeys', () {
      final errors = <String>[];
      ManifestComponentChecks.checkLocalizationKeys(
        ['b', 'a'],
        'components.button.localizationKeys',
        errors,
      );
      expect(errors, contains(contains('must be sorted')));
    });

    test('rejects duplicate localizationKeys', () {
      final errors = <String>[];
      ManifestComponentChecks.checkLocalizationKeys(
        ['a', 'a'],
        'components.button.localizationKeys',
        errors,
      );
      expect(errors, contains(contains('duplicate')));
    });

    test('rejects non-string localizationKeys entries', () {
      final errors = <String>[];
      ManifestComponentChecks.checkLocalizationKeys(
        ['a', 1],
        'components.button.localizationKeys',
        errors,
      );
      expect(errors, contains(contains('non-empty strings')));
    });

    test('model parses keys and reports locale support', () {
      expect(manifest.hasLocalizationKeys, isTrue);
      expect(
        manifest.components['button']!.localizationKeys,
        ['announcementFailure', 'announcementLoading'],
      );
      expect(
        manifest.components['dialog']!.localizationKeys,
        ['announcementLoading', 'dialogDismiss'],
      );
    });
  });

  group('slim file filter', () {
    test('skips locale tables and the kit delegate only', () {
      expect(
        isSlimmedLocaleFile(
          'primitives/localizations/localizations_ar.dart',
        ),
        isTrue,
      );
      expect(
        isSlimmedLocaleFile(
          'primitives/localizations/localizations_delegate.dart',
        ),
        isTrue,
      );
      expect(
        isSlimmedLocaleFile(
          'primitives/localizations/localizations.dart',
        ),
        isFalse,
      );
      expect(
        isSlimmedLocaleFile(
          'primitives/localizations/localizations_misc.dart',
        ),
        isFalse,
      );
      expect(isSlimmedLocaleFile('components/button/button.dart'), isFalse);
      expect(isSlimmedLocaleFile('foundation/data.dart'), isFalse);
    });

    test('closure of a locale-aware registry excludes tables', () {
      final closure = ManifestClosureResolver(manifest).resolve(['button']);
      expect(
        closure.files,
        contains('primitives/localizations/localizations.dart'),
      );
      expect(
        closure.files.any((file) => isSlimmedLocaleFile(file)),
        isFalse,
      );
    });
  });

  group('refreshAfterInstall', () {
    test('writes en, barrel, state and the slim delegate', () async {
      final report = await buildService().refreshAfterInstall();
      expect(report, isNotNull);
      expect(
        report!.written,
        containsAll([
          'dashcn_locales/dashcn_locale_en.dart',
          'dashcn_locales/dashcn_locales.dart',
          'dashcn_locales/state.json',
          p
              .join(
                'lib/ui/dashcn/primitives/localizations'
                    .replaceAll('/', p.separator),
                'localizations_delegate.dart',
              )
              .replaceAll('\\', '/'),
        ]),
      );
      expect(report.locales, ['en']);
      expect(report.keys, isEmpty);
      final delegate = readProject(
        'lib/ui/dashcn/primitives/localizations/localizations_delegate.dart',
      );
      expect(delegate, contains('ComponentLocalizationsDelegate'));
      expect(delegate, contains('ComponentLocalizations.english'));
      expect(delegate, contains('GENERATED by `dashcn`'));
    });

    test('is idempotent: a rerun writes nothing', () async {
      final service = buildService();
      await service.refreshAfterInstall();
      final again = await service.refreshAfterInstall();
      expect(again, isNotNull);
      expect(again!.written, isEmpty);
    });

    test('contains only the installed components keys', () async {
      await buildInstaller().add(['button']);
      final report = await buildService().refreshAfterInstall(
        components: {'button'},
      );
      expect(report, isNotNull);
      expect(
        report!.keys,
        ['announcementFailure', 'announcementLoading'],
      );
      final en = readProject('dashcn_locales/dashcn_locale_en.dart');
      expect(en, contains('announcementFailure'));
      expect(en, contains('announcementLoading'));
      expect(en, isNot(contains('dialogDismiss')));
      // Without a pubspec the installed copy is imported relatively, never
      // package:dashcn.
      expect(
        en,
        contains(
          "../lib/ui/dashcn/primitives/localizations/localizations.dart'",
        ),
      );
      expect(en, isNot(contains('package:dashcn')));
    });

    test('uses a package: import when the app has a pubspec', () async {
      File(
        p.join(project.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: demo_app\n');
      await buildInstaller().add(['button']);
      final report = await buildService().refreshAfterInstall(
        components: {'button'},
      );
      expect(report, isNotNull);
      final en = readProject('dashcn_locales/dashcn_locale_en.dart');
      expect(
        en,
        contains(
          "'package:demo_app/ui/dashcn/primitives/localizations/localizations.dart'",
        ),
      );
    });
  });

  group('add-then-locale and locale-then-add', () {
    Future<Map<String, String>> addThenLocale() async {
      await buildInstaller().add(['button']);
      final service = buildService();
      await service.refreshAfterInstall(components: {'button'});
      await service.addLocale('ar');
      await buildInstaller().add(['dialog']);
      await service.refreshAfterInstall(components: {'dialog'});
      return _snapshot(project);
    }

    Future<Map<String, String>> localeThenAdd() async {
      final service = buildService();
      await service.addLocale('ar');
      await buildInstaller().add(['button']);
      await service.refreshAfterInstall(components: {'button'});
      await buildInstaller().add(['dialog']);
      await service.refreshAfterInstall(components: {'dialog'});
      return _snapshot(project);
    }

    test('converge to the same files', () async {
      final first = await addThenLocale();
      final firstPaths = first.keys.toList()..sort();
      project.deleteSync(recursive: true);
      project = Directory.systemTemp.createTempSync('dashcn_locale_test_');
      final second = await localeThenAdd();
      final secondPaths = second.keys.toList()..sort();
      expect(secondPaths, firstPaths);
      for (final path in firstPaths) {
        expect(second[path], first[path], reason: path);
      }
      final ar = first['dashcn_locales/dashcn_locale_ar.dart']!;
      expect(ar, contains('announcementFailure'));
      expect(ar, contains('dialogDismiss'));
      // German was never added: no file for it.
      expect(
        firstPaths.any((path) => path.contains('dashcn_locale_de.dart')),
        isFalse,
      );
    });

    test('addLocale is idempotent', () async {
      await buildInstaller().add(['button']);
      final service = buildService();
      await service.refreshAfterInstall(components: {'button'});
      final first = await service.addLocale('ar');
      expect(first.written, isNotEmpty);
      final second = await service.addLocale('ar');
      expect(second.written, isEmpty);
    });

    test('unknown locale fails', () async {
      expect(
        () => buildService().addLocale('xx'),
        throwsA(isA<UnknownLocaleException>()),
      );
    });
  });

  group('locale remove', () {
    test('deletes the file and refreshes the barrel', () async {
      await buildInstaller().add(['button']);
      final service = buildService();
      await service.refreshAfterInstall(components: {'button'});
      await service.addLocale('ar');
      expect(existsProject('dashcn_locales/dashcn_locale_ar.dart'), isTrue);

      final report = await service.removeLocale('ar');
      expect(
        report.removed,
        contains('dashcn_locales/dashcn_locale_ar.dart'),
      );
      expect(existsProject('dashcn_locales/dashcn_locale_ar.dart'), isFalse);
      final barrel = readProject('dashcn_locales/dashcn_locales.dart');
      expect(barrel, isNot(contains('DashcnLocaleAr')));

      final again = await service.removeLocale('ar');
      expect(again.written, isEmpty);
      expect(again.removed, isEmpty);
    });

    test('refuses to remove the English base', () async {
      await buildInstaller().add(['button']);
      final service = buildService();
      await service.refreshAfterInstall(components: {'button'});
      expect(
        () => service.removeLocale('en'),
        throwsA(isA<LocaleNotSupportedException>()),
      );
    });
  });

  group('locale list', () {
    test('flags installed locales', () async {
      final service = buildService();
      await service.refreshAfterInstall();
      await service.addLocale('ar');
      final entries = await service.listLocales();
      final byCode = {for (final entry in entries) entry.code: entry};
      expect(byCode['en']!.installed, isTrue);
      expect(byCode['ar']!.installed, isTrue);
      expect(byCode['ar']!.direction, 'rtl');
      expect(byCode['de']!.installed, isFalse);
    });
  });

  group('registries without locale support', () {
    RegistryManifest legacyManifest() {
      final data = LocaleRegistryFixture.buildManifest(fileHashes: {});
      for (final component in (data['components'] as Map).values) {
        (component as Map).remove('localizationKeys');
      }
      return RegistryManifest.fromJson(data);
    }

    LocaleSyncService legacyService() => LocaleSyncService(
          source: fixture.source,
          manifest: legacyManifest(),
          projectRoot: project.path,
          installRoot: 'lib/ui/dashcn',
        );

    test('refresh returns null and writes nothing', () async {
      final report = await legacyService().refreshAfterInstall();
      expect(report, isNull);
      expect(
        Directory(p.join(project.path, 'dashcn_locales')).existsSync(),
        isFalse,
      );
    });

    test('locale commands fail with a clear error', () async {
      final service = legacyService();
      expect(() => service.addLocale('ar'),
          throwsA(isA<LocaleNotSupportedException>()));
      expect(() => service.listLocales(),
          throwsA(isA<LocaleNotSupportedException>()));
    });
  });
}

/// Project-relative path -> content for every file under [project].
Map<String, String> _snapshot(Directory project) {
  final entries = project.listSync(recursive: true);
  final result = <String, String>{};
  for (final entry in entries) {
    if (entry is! File) {
      continue;
    }
    final relative =
        p.relative(entry.path, from: project.path).replaceAll('\\', '/');
    if (relative == 'dashcn.lock' || relative == 'pubspec.lock') {
      continue;
    }
    result[relative] = entry.readAsStringSync();
  }
  return result;
}

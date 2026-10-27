import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/fonts/font_sync_service.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/add_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/fonts_command.dart';
import 'package:dashcn_cli/src/registry/manifest/manifest_schema_validator.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:dashcn_cli/src/theme_interop/google_fonts_catalogue.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fonts_registry_fixture.dart';

void main() {
  late FontsRegistryFixture fixture;
  late RegistryManifest manifest;
  late Directory project;

  setUpAll(() {
    fixture = FontsRegistryFixture.create();
    final registryFile =
        File(p.join(fixture.root, 'manifests', 'registry.json'));
    manifest = RegistryManifest.fromJson(
      jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>,
    );
  });

  tearDownAll(() => fixture.dispose());

  setUp(() {
    project = Directory.systemTemp.createTempSync('dashcn_fonts_test_');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
      'name: fonts_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
    );
  });

  tearDown(() => project.delete(recursive: true));

  FontSyncService buildService({RegistryManifest? override}) => FontSyncService(
        source: fixture.source,
        manifest: override ?? manifest,
        projectRoot: project.path,
      );

  Map<String, dynamic> fixtureManifest() => jsonDecode(
        File(p.join(fixture.root, 'manifests', 'registry.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;

  bool existsProject(String target) =>
      File(p.join(project.path, target)).existsSync();

  String readProject(String target) =>
      File(p.join(project.path, target)).readAsStringSync();

  ({ArgResults root, ArgResults command}) parse(List<String> args) {
    final results = buildCliParser()
        .parse(normalizeCliArgs(['--registry', fixture.root, ...args]));
    return (root: results, command: results.command!);
  }

  Future<({int code, String out})> capture(Future<int> Function() run) async {
    final buffer = StringBuffer();
    final code = await runZoned(
      run,
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => buffer.writeln(line),
      ),
    );
    return (code: code, out: buffer.toString());
  }

  group('registry schema', () {
    test('accepts the contract fonts map', () {
      final result = ManifestSchemaValidator.validate(
        fixtureManifest(),
        registryRoot: fixture.root,
      );
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    });

    test('older registries without a fonts map stay valid', () {
      final data = fixtureManifest();
      data.remove('fonts');
      final parsed = RegistryManifest.fromJson(data);
      expect(parsed.fonts, isEmpty);
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    });

    test('rejects unknown top-level keys', () {
      final data = fixtureManifest();
      data['fonst'] = <String, dynamic>{};
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('unknown top-level key')));
    });

    test('rejects font files outside assets/fonts', () {
      final data = fixtureManifest();
      final fonts = data['fonts'] as Map;
      final sans = fonts['geist-sans'] as Map;
      final families = sans['families'] as List;
      final family = families.first as Map;
      (family['files'] as List).first['path'] = 'lib/evil.otf';
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('assets/fonts')));
    });

    test('rejects bad weights and styles', () {
      final data = fixtureManifest();
      final fonts = data['fonts'] as Map;
      final sans = fonts['geist-sans'] as Map;
      final files = ((sans['families'] as List).first as Map)['files'] as List;
      (files.first as Map)['weight'] = 50;
      (files[1] as Map)['style'] = 'oblique';
      final result = ManifestSchemaValidator.validate(data);
      expect(result.errors, contains(contains('weight')));
      expect(result.errors, contains(contains('style')));
    });

    test('model parses packs, families and files', () {
      expect(manifest.fonts.keys.toSet(),
          {'geist-sans', 'geist-mono', 'noto-symbols'});
      final sans = manifest.fonts['geist-sans']!;
      expect(sans.familyNames, ['GeistSans']);
      expect(sans.families.single.files.map((f) => f.weight), [400, 700, 400]);
      expect(sans.families.single.files.last.style, 'italic');
      expect(manifest.fonts['noto-symbols']!.familyNames, ['NotoSansSymbols2']);
    });

    test('font files are not copyable component files', () {
      expect(
        manifest.declaredFiles.any((path) => path.startsWith('assets/')),
        isFalse,
      );
    });
  });

  group('fonts list', () {
    test('lists every pack with its families, none installed', () async {
      final entries = await buildService().listFonts();
      expect(entries.map((e) => e.id),
          ['geist-mono', 'geist-sans', 'noto-symbols']);
      final byId = {for (final e in entries) e.id: e};
      expect(byId['geist-sans']!.families, ['GeistSans']);
      expect(byId['noto-symbols']!.families, ['NotoSansSymbols2']);
      expect(entries.every((e) => !e.installed), isTrue);
    });

    test('flags installed packs', () async {
      final service = buildService();
      await service.addFont('geist-sans');
      final byId = {for (final e in await service.listFonts()) e.id: e};
      expect(byId['geist-sans']!.installed, isTrue);
      expect(byId['geist-mono']!.installed, isFalse);
    });
  });

  group('fonts add', () {
    test('copies files binary-safe and merges the pubspec block', () async {
      final report = await buildService().addFont('geist-sans');
      expect(report.google, isFalse);
      expect(report.families, ['GeistSans']);
      expect(
        report.written,
        containsAll([
          'assets/fonts/Geist-Regular.otf',
          'assets/fonts/Geist-Bold.otf',
          'assets/fonts/Geist-Italic.otf',
          'pubspec.yaml',
          'assets/fonts/state.json',
        ]),
      );
      for (final entry in FontsRegistryFixture.fontFiles.entries) {
        if (!entry.key.contains('GeistMono') &&
            !entry.key.contains('NotoSans')) {
          final copied =
              File(p.join(project.path, entry.key)).readAsBytesSync();
          expect(copied, FontsRegistryFixture.fontBytes(entry.value),
              reason: entry.key);
        }
      }
      final pubspec = readProject('pubspec.yaml');
      expect(pubspec, contains('- family: GeistSans'));
      expect(pubspec, contains('- asset: assets/fonts/Geist-Regular.otf'));
      expect(pubspec, contains('weight: 700'));
      expect(pubspec, contains('style: italic'));
      final state = jsonDecode(readProject('assets/fonts/state.json'))
          as Map<String, dynamic>;
      expect(state, {
        'fonts': ['geist-sans']
      });
    });

    test('is idempotent: a rerun writes nothing', () async {
      final service = buildService();
      final first = await service.addFont('noto-symbols');
      expect(first.written, isNotEmpty);
      final pubspec = readProject('pubspec.yaml');
      final second = await service.addFont('noto-symbols');
      expect(second.written, isEmpty);
      expect(readProject('pubspec.yaml'), pubspec);
    });

    test('unknown id fails', () async {
      expect(
        () => buildService().addFont('comic-sans'),
        throwsA(isA<UnknownFontException>()),
      );
    });

    test('missing pubspec fails clearly', () async {
      File(p.join(project.path, 'pubspec.yaml')).deleteSync();
      expect(
        () => buildService().addFont('geist-sans'),
        throwsA(isA<FontPubspecMissingException>()),
      );
    });

    test('registries without a fonts map fail with a clear error', () async {
      final data = FontsRegistryFixture.buildManifest(fileHashes: {});
      data.remove('fonts');
      final legacy = RegistryManifest.fromJson(data);
      final service = buildService(override: legacy);
      expect(() => service.addFont('geist-sans'),
          throwsA(isA<FontNotSupportedException>()));
      expect(
          () => service.listFonts(), throwsA(isA<FontNotSupportedException>()));
    });
  });

  group('fonts add --google', () {
    test('adds the dependency only and prints the usage', () async {
      final service = buildService();
      final report = await service.addFont('geist-mono', google: true);
      expect(report.google, isTrue);
      expect(report.families, ['GeistMono']);
      final pubspec = readProject('pubspec.yaml');
      expect(
        pubspec,
        contains('$kGoogleFontsPackageName: $kGoogleFontsVersionPin'),
      );
      expect(pubspec, isNot(contains('flutter:\n  fonts:')));
      expect(pubspec, isNot(contains('- family: GeistMono')));
      expect(existsProject('assets/fonts/GeistMono-Regular.otf'), isFalse);
      expect(
        googleFontsGetFontExpression('GeistMono'),
        "GoogleFonts.getFont('GeistMono')",
      );
      final state = jsonDecode(readProject('assets/fonts/state.json'))
          as Map<String, dynamic>;
      expect(state, {
        'fonts': ['geist-mono']
      });
    });

    test('is idempotent: a rerun writes nothing', () async {
      final service = buildService();
      await service.addFont('geist-mono', google: true);
      final again = await service.addFont('geist-mono', google: true);
      expect(again.written, isEmpty);
    });
  });

  group('fonts command', () {
    test('list exits 0', () async {
      final args = parse(['fonts', 'list']);
      final result = await capture(() => runFontsCommand(
            fontsCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
    });

    test('add installs the pack and exits 0', () async {
      final args = parse(['fonts', 'add', 'geist-sans', '--json']);
      final result = await capture(() => runFontsCommand(
            fontsCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(existsProject('assets/fonts/Geist-Regular.otf'), isTrue);
      final json = jsonDecode(result.out) as Map<String, dynamic>;
      expect((json['data'] as Map)['id'], 'geist-sans');
    });

    test('add --google exits 0 and copies no files', () async {
      final args = parse(['fonts', 'add', 'geist-mono', '--google']);
      final result = await capture(() => runFontsCommand(
            fontsCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(existsProject('assets/fonts/GeistMono-Regular.otf'), isFalse);
      expect(readProject('pubspec.yaml'), contains('google_fonts'));
    });

    test('add of an unknown font exits 2', () async {
      final args = parse(['fonts', 'add', 'nope']);
      final result = await capture(() => runFontsCommand(
            fontsCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.usage);
    });
  });

  group('dashcn add installs no font', () {
    test('add copies no font file and writes no fonts block', () async {
      final args = parse(['add', 'button', '--json']);
      final result = await capture(() => runAddCommand(
            addCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(
          existsProject('lib/ui/dashcn/components/button/button.dart'), isTrue);
      final entities = Directory(p.join(project.path, 'assets')).existsSync()
          ? Directory(p.join(project.path, 'assets'))
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => p.relative(f.path, from: project.path))
              .toList()
          : <String>[];
      expect(
        entities.any((path) => path.endsWith('.otf') || path.endsWith('.ttf')),
        isFalse,
      );
      expect(readProject('pubspec.yaml'), isNot(contains('- family:')));
    });
  });
}

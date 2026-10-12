@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/kit_registry.dart';

/// End-to-end web-theme bridge gate (P9-4b §3).
///
/// Temp app → `theme import` of a real tweakcn-style CSS → `theme export`
/// DTCG → re-import of the stored preset → the same tokens. Registry-free by
/// design: no registry flag is passed.
///
/// Tagged `e2e` and skipped by default (it needs the kit checkout for the
/// tweakcn fixture). Run it with:
///
/// ```bash
/// dart test -t e2e --run-skipped
/// ```
void main() {
  group('e2e theme interop', () {
    late Directory app;
    late String cliEntrypoint;
    String? unavailable;
    String? tweakCss;

    setUpAll(() async {
      final kit = findKitPackageRoot();
      if (kit == null) {
        unavailable = 'dashcn not found (set DASHCN_KIT_ROOT)';
        return;
      }
      final fixture = File(
        p.join(
          kit,
          'test',
          'registry',
          'theme',
          'interop',
          'fixtures',
          'tweakcn_style.css',
        ),
      );
      if (!fixture.existsSync()) {
        unavailable = 'tweakcn fixture missing at ${fixture.path}';
        return;
      }
      tweakCss = fixture.readAsStringSync();
      cliEntrypoint = p.join(await _packageRoot(), 'bin', 'dashcn.dart');
      app = Directory.systemTemp.createTempSync('dashcn_theme_e2e_');
    });

    tearDownAll(() {
      if (unavailable == null && app.existsSync()) {
        app.deleteSync(recursive: true);
      }
    });

    Future<ProcessResult> runCli(List<String> args) {
      return Process.run(
        Platform.resolvedExecutable,
        [cliEntrypoint, ...args],
        workingDirectory: app.path,
        environment: {...Platform.environment, 'CI': 'true'},
      );
    }

    void expectSuccess(ProcessResult result, String label) {
      expect(
        result.exitCode,
        0,
        reason: '$label failed (exit ${result.exitCode})\n'
            'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    }

    File file(String rel) => File(p.join(app.path, p.normalize(rel)));

    test('import CSS -> export DTCG -> re-import -> same tokens', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      file('theme.css').writeAsStringSync(tweakCss!);

      // ── import ────────────────────────────────────────────────────
      final importResult = await runCli(
        ['theme', 'import', 'theme.css', '--name', 'tweak'],
      );
      expectSuccess(importResult, 'theme import theme.css');
      expect(importResult.stdout as String, contains('Imported CSS'));
      expect(importResult.stdout as String, contains('mapped '));
      final stored = file('lib/ui/dashcn/theme/tweak.json');
      expect(stored.existsSync(), isTrue);
      final Map<String, dynamic> preset =
          jsonDecode(stored.readAsStringSync()) as Map<String, dynamic>;
      expect(preset['id'], 'tweak');
      expect(preset['schemaVersion'], 2);

      // ── export DTCG ───────────────────────────────────────────────
      final exportFirst = await runCli(
        ['theme', 'export', '--format', 'dtcg', '--out', 'a.tokens.json'],
      );
      expectSuccess(exportFirst, 'theme export --format dtcg');
      final Map<String, dynamic> first = jsonDecode(
        file('a.tokens.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(first.keys, containsAll(<String>['light', 'dark']));

      // ── re-import the stored preset, export again, compare ─────────
      final reimport = await runCli(
        [
          'theme',
          'import',
          p.join('lib', 'ui', 'dashcn', 'theme', 'tweak.json'),
          '--name',
          'again',
        ],
      );
      expectSuccess(reimport, 'theme import tweak.json');
      final exportSecond = await runCli(
        ['theme', 'export', '--format', 'dtcg', '--out', 'b.tokens.json'],
      );
      expectSuccess(exportSecond, 'theme export --format dtcg (again)');
      expect(
        file('b.tokens.json').readAsStringSync(),
        file('a.tokens.json').readAsStringSync(),
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<String> _packageRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:dashcn_cli/dashcn_cli.dart'),
  );
  if (packageUri == null) {
    throw StateError('Could not resolve the dashcn_cli package root');
  }
  return p.dirname(p.dirname(File.fromUri(packageUri).path));
}

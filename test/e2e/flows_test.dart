@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/kit_registry.dart';

/// End-to-end flows gate (P9-3b).
///
/// Creates a real Flutter app, installs the kit registry through the CLI from
/// source, and asserts: `add flow:auth-01` installs the flow with its
/// components/blocks closure under `lib/ui/dashcn/flows/auth-01/`, records it
/// in `dashcn.lock`, `flutter analyze` is clean, `list --flows` / `info` show
/// it with type `flow`, and `remove` drops only the flow.
///
/// Tagged `e2e` and skipped by default (it needs the Flutter SDK, the kit
/// checkout and a warm pub cache). Run it with:
///
/// ```bash
/// DASHCN_KIT_ROOT=$KIT dart test -t e2e --run-skipped
/// ```
void main() {
  group('e2e flows', () {
    late Directory app;
    late String cliEntrypoint;
    late String registryRoot;
    String? unavailable;

    setUpAll(() async {
      final kit = findKitPackageRoot();
      if (kit == null) {
        unavailable = 'dashcn not found (set DASHCN_KIT_ROOT)';
        return;
      }
      registryRoot = p.join(kit, 'lib', 'src');
      if (!Directory(registryRoot).existsSync()) {
        unavailable = 'kit registry missing at $registryRoot';
        return;
      }
      if (!await _hasFlutter()) {
        unavailable = 'the flutter executable is not on PATH';
        return;
      }
      cliEntrypoint = p.join(await _packageRoot(), 'bin', 'dashcn.dart');
      app = Directory.systemTemp.createTempSync('dashcn_e2e_flows_');
      final create = await Process.run(
        'flutter',
        ['create', '--empty', '--project-name', 'dashcn_e2e_flows', app.path],
        workingDirectory: app.path,
      );
      if (create.exitCode != 0) {
        throw StateError(
          'flutter create failed (exit ${create.exitCode})\n'
          'stdout:\n${create.stdout}\nstderr:\n${create.stderr}',
        );
      }
    });

    tearDownAll(() {
      if (unavailable == null && app.existsSync()) {
        app.deleteSync(recursive: true);
      }
    });

    Future<ProcessResult> runCli(List<String> args) {
      return Process.run(
        Platform.resolvedExecutable,
        [cliEntrypoint, '--registry', registryRoot, ...args],
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

    Map<String, dynamic> lock() =>
        jsonDecode(file('dashcn.lock').readAsStringSync())
            as Map<String, dynamic>;

    test('add flow:auth-01 installs, analyzes and removes', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }

      expectSuccess(await runCli(['init', '--yes']), 'init --yes');

      // ── copy mode: the flow lands with its closure ────────────────────
      expectSuccess(await runCli(['add', 'flow:auth-01']), 'add flow:auth-01');
      expect(
        file('lib/ui/dashcn/flows/auth-01/flow.dart').existsSync(),
        isTrue,
        reason: 'flow.dart missing after add flow:auth-01',
      );
      for (final dep in const ['button', 'card', 'form', 'input']) {
        expect(
          file('lib/ui/dashcn/components/$dep/$dep.dart').existsSync(),
          isTrue,
          reason: 'flow dependency $dep.dart missing after add flow:auth-01',
        );
      }
      final flowIds = [
        for (final entry in lock()['flows'] as List)
          (entry as Map)['id'] as String,
      ];
      expect(flowIds, contains('auth-01'));

      // ── the flow must not break the app it was copied into ────────────
      final analyze = await Process.run(
        'flutter',
        ['analyze'],
        workingDirectory: app.path,
      );
      expectSuccess(analyze, 'flutter analyze after add flow:auth-01');
      expect(analyze.stdout.toString(), contains('No issues found!'));

      // ── the flow shows up in the read-only commands ───────────────────
      final listFlows = await runCli(['list', '--flows', '--json']);
      expectSuccess(listFlows, 'list --flows --json');
      final listed = jsonDecode(listFlows.stdout.toString()) as Map;
      expect(
        (listed['data'] as Map)['flows'],
        isA<List>().having((list) => list.length, 'length', greaterThan(0)),
      );
      final infoFlow = await runCli(['info', 'flow:auth-01', '--json']);
      expectSuccess(infoFlow, 'info flow:auth-01');
      final infoData =
          ((jsonDecode(infoFlow.stdout.toString()) as Map)['data'] as Map);
      expect(infoData['kind'], 'flow');
      expect(infoData['id'], 'auth-01');
      final searchFlow = await runCli(['search', 'auth', '--json']);
      expectSuccess(searchFlow, 'search auth');
      final searchData =
          ((jsonDecode(searchFlow.stdout.toString()) as Map)['data'] as Map);
      expect(searchData['flows'], isNotEmpty);

      // ── remove drops only the flow ────────────────────────────────────
      expectSuccess(
        await runCli(['remove', 'flow:auth-01']),
        'remove flow:auth-01',
      );
      expect(
        file('lib/ui/dashcn/flows/auth-01/flow.dart').existsSync(),
        isFalse,
      );
      expect(
        file('lib/ui/dashcn/components/button/button.dart').existsSync(),
        isTrue,
        reason: 'a flow must not delete the components it assembled',
      );
      expect(lock()['flows'], isEmpty);
    }, timeout: const Timeout(Duration(minutes: 30)));
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Future<bool> _hasFlutter() async {
  try {
    final result = await Process.run('flutter', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
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

@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end starter gate (P9-6).
///
/// Per starter by mode in a temp dir with `DASHCN_KIT_ROOT=$KIT`:
/// create, then `flutter analyze` with zero issues, then `flutter test`
/// (the generated smoke test walks the main routes: sign in, home, each
/// tab or page).
///
/// Tagged `e2e` and skipped by default (needs the Flutter SDK, the kit
/// checkout and a warm pub cache). Run it with:
///
/// ```bash
/// dart test -t e2e --run-skipped test/e2e/create_test.dart
/// ```
void main() {
  group('e2e create', () {
    late String cliEntrypoint;
    late String registryRoot;
    late String kitEnv;
    String? unavailable;

    setUpAll(() async {
      final kit = _findKitRoot();
      if (kit == null) {
        unavailable = 'dashcn kit not found (set DASHCN_KIT_ROOT)';
        return;
      }
      final packageDir = _kitPackageDir(kit);
      if (packageDir == null) {
        unavailable = 'kit package missing under $kit';
        return;
      }
      registryRoot = p.join(packageDir, 'lib', 'src');
      if (!Directory(registryRoot).existsSync()) {
        unavailable = 'kit registry missing at $registryRoot';
        return;
      }
      if (!File(p.join(registryRoot, 'starters', 'saas', 'starter.json'))
          .existsSync()) {
        unavailable = 'kit starters missing (need P9-6 kit)';
        return;
      }
      kitEnv = kit;
      if (!await _hasFlutter()) {
        unavailable = 'the flutter executable is not on PATH';
        return;
      }
      cliEntrypoint = p.join(await _packageRoot(), 'bin', 'dashcn.dart');
    });

    Future<ProcessResult> runCli(Directory work, List<String> args) {
      return Process.run(
        Platform.resolvedExecutable,
        [cliEntrypoint, '--registry', registryRoot, ...args],
        workingDirectory: work.path,
        environment: {
          ...Platform.environment,
          'CI': 'true',
          'DASHCN_KIT_ROOT': kitEnv,
        },
      );
    }

    Future<ProcessResult> runFlutter(Directory app, List<String> args) {
      return Process.run(
        'flutter',
        args,
        workingDirectory: app.path,
        environment: {
          ...Platform.environment,
          'CI': 'true',
          'DASHCN_KIT_ROOT': kitEnv,
        },
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

    Future<void> runStarter(String starter, String mode) async {
      final work = Directory.systemTemp.createTempSync('dashcn_create_e2e_');
      try {
        final name = '${starter}_${mode}_app';
        final create = await runCli(work, [
          'create',
          starter,
          name,
          '--mode',
          mode,
        ]);
        expectSuccess(create, 'create $starter $mode');
        final app = Directory(p.join(work.path, name));
        expect(app.existsSync(), isTrue, reason: 'app dir missing');

        if (mode == 'copy') {
          final lockFile = File(p.join(app.path, 'dashcn.lock'));
          expect(
            lockFile.existsSync(),
            isTrue,
            reason: 'dashcn.lock missing ($starter $mode)',
          );
          final lock =
              jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
          final flows = (lock['flows'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => e['id'].toString())
              .toList()
            ..sort();
          expect(
            flows,
            _expectedFlows(starter),
            reason: 'lock flows for $starter $mode',
          );
        }

        final analyze = await runFlutter(app, ['analyze']);
        expectSuccess(analyze, 'flutter analyze ($starter $mode)');
        expect(
          analyze.stdout.toString(),
          contains('No issues found!'),
          reason: 'analyze reported issues:\n${analyze.stdout}\n'
              '${analyze.stderr}',
        );

        final test = await runFlutter(app, ['test']);
        expectSuccess(test, 'flutter test ($starter $mode)');
      } finally {
        if (work.existsSync()) {
          work.deleteSync(recursive: true);
        }
      }
    }

    for (final starter in const ['saas', 'chat', 'shop']) {
      for (final mode in const ['package', 'copy']) {
        test(
          '$starter $mode: create, analyze, test',
          () async {
            if (unavailable != null) {
              markTestSkipped(unavailable!);
              return;
            }
            await runStarter(starter, mode);
          },
          timeout: const Timeout(Duration(minutes: 15)),
        );
      }
    }
  });
}

List<String> _expectedFlows(String starter) {
  switch (starter) {
    case 'saas':
      return <String>['auth-01', 'onboarding-01', 'settings-01'];
    case 'chat':
      return <String>['auth-01', 'chat-01', 'settings-01'];
    case 'shop':
      return <String>['auth-01', 'checkout-01', 'settings-01'];
    default:
      return const <String>[];
  }
}

String? _findKitRoot() {
  final override = Platform.environment['DASHCN_KIT_ROOT']?.trim();
  if (override != null && override.isNotEmpty) {
    if (Directory(override).existsSync()) {
      return p.normalize(override);
    }
  }
  for (final candidate in <String>[
    p.normalize(p.join(Directory.current.path, '..', 'dashcn-kit', 'dashcn')),
    p.normalize(
      p.join(Directory.current.path, '..', '..', 'dashcn-kit', 'dashcn'),
    ),
  ]) {
    if (Directory(candidate).existsSync()) {
      return p.normalize(candidate);
    }
  }
  return null;
}

String? _kitPackageDir(String kit) {
  if (File(p.join(kit, 'pubspec.yaml')).existsSync() &&
      Directory(p.join(kit, 'lib', 'src')).existsSync()) {
    return p.normalize(kit);
  }
  final nested = p.join(kit, 'dashcn');
  if (File(p.join(nested, 'pubspec.yaml')).existsSync()) {
    return p.normalize(nested);
  }
  return null;
}

Future<bool> _hasFlutter() async {
  try {
    final result = await Process.run('flutter', ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<String> _packageRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:dashcn_cli/dashcn_cli.dart'),
  );
  if (uri == null) {
    return Directory.current.path;
  }
  return File.fromUri(uri).parent.parent.path;
}

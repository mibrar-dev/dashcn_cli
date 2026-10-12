@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/kit_registry.dart';

/// End-to-end package-mode gate (P8-3).
///
/// Fresh `flutter create` apps exercise both install modes against the real
/// kit registry: copy mode (`init --mode copy` + `add button`), package mode
/// (`init --mode package` + `add button --package --path <kit>`), and
/// `eject button` back to owned sources. Every stage ends with a clean
/// `flutter analyze`.
///
/// Tagged `e2e` and skipped by default (needs the Flutter SDK, the kit
/// checkout and a warm pub cache). Run it with:
///
/// ```bash
/// dart test -t e2e --run-skipped test/e2e/package_mode_test.dart
/// ```
void main() {
  group('e2e package mode', () {
    late Directory copyApp;
    late Directory packageApp;
    late String cliEntrypoint;
    late String registryRoot;
    late String kitRoot;
    String? unavailable;

    setUpAll(() async {
      final kit = findKitPackageRoot();
      if (kit == null) {
        unavailable = 'dashcn kit not found (set DASHCN_KIT_ROOT)';
        return;
      }
      kitRoot = kit;
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
      copyApp = await _createApp('dashcn_copy_e2e_app');
      packageApp = await _createApp('dashcn_package_e2e_app');
    });

    tearDownAll(() {
      if (unavailable == null) {
        if (copyApp.existsSync()) copyApp.deleteSync(recursive: true);
        if (packageApp.existsSync()) packageApp.deleteSync(recursive: true);
      }
    });

    Future<ProcessResult> runCli(
      Directory app,
      List<String> args,
    ) {
      return Process.run(
        Platform.resolvedExecutable,
        [cliEntrypoint, '--registry', registryRoot, ...args],
        workingDirectory: app.path,
        environment: {...Platform.environment, 'CI': 'true'},
      );
    }

    Future<ProcessResult> runFlutter(Directory app, List<String> args) {
      return Process.run(
        'flutter',
        args,
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

    Future<void> expectAnalyzeClean(Directory app, String label) async {
      final result = await runFlutter(app, ['analyze']);
      expectSuccess(result, label);
      expect(
        result.stdout.toString(),
        contains('No issues found!'),
        reason: '$label reported issues:\n${result.stdout}\n${result.stderr}',
      );
    }

    void writeMain(Directory app, String importUri) {
      File(p.join(app.path, 'lib', 'main.dart')).writeAsStringSync(
        "import '$importUri';\n"
        "import 'package:flutter/widgets.dart';\n"
        '\n'
        'void main() {\n'
        '  runApp(\n'
        '    Directionality(\n'
        '      textDirection: TextDirection.ltr,\n'
        '      child: Button(onPressed: _noop, child: Text(\'Hello\')),\n'
        '    ),\n'
        '  );\n'
        '}\n'
        '\n'
        'void _noop() {}\n',
      );
    }

    test('copy flow: init copy, add button, analyze', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      expectSuccess(
        await runCli(copyApp, ['init', '--mode', 'copy', '--yes']),
        'init --mode copy --yes',
      );
      expectSuccess(await runCli(copyApp, ['add', 'button']), 'add button');
      writeMain(copyApp, 'ui/dashcn/components/button/button.dart');
      await expectAnalyzeClean(copyApp, 'flutter analyze (copy)');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('package flow: init package, add --package, eject, analyze', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      expectSuccess(
        await runCli(packageApp, ['init', '--mode', 'package', '--yes']),
        'init --mode package --yes',
      );
      expect(
        File(p.join(
          packageApp.path,
          'lib/ui/dashcn/components/button/button.dart',
        )).existsSync(),
        isFalse,
        reason: 'package init must copy no sources',
      );
      expectSuccess(
        await runCli(packageApp, [
          'add',
          'button',
          '--package',
          '--path',
          kitRoot,
        ]),
        'add button --package --path',
      );
      writeMain(packageApp, 'package:dashcn/components/button.dart');
      await expectAnalyzeClean(packageApp, 'flutter analyze (package)');

      expectSuccess(
        await runCli(packageApp, ['eject', 'button']),
        'eject button',
      );
      expect(
        File(p.join(
          packageApp.path,
          'lib/ui/dashcn/components/button/button.dart',
        )).existsSync(),
        isTrue,
        reason: 'eject must materialise the owned sources',
      );
      final main =
          File(p.join(packageApp.path, 'lib', 'main.dart')).readAsStringSync();
      expect(
        main,
        isNot(contains('package:dashcn/components/button.dart')),
        reason: 'no package import may remain after eject',
      );
      await expectAnalyzeClean(packageApp, 'flutter analyze (ejected)');
    }, timeout: const Timeout(Duration(minutes: 15)));
  });
}

Future<bool> _hasFlutter() async {
  try {
    final result = await Process.run('flutter', ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<Directory> _createApp(String name) async {
  final dir = Directory.systemTemp.createTempSync('dashcn_e2e_');
  final create = await Process.run(
    'flutter',
    ['create', '--empty', '--project-name', name, dir.path],
    workingDirectory: dir.path,
    environment: {...Platform.environment, 'CI': 'true'},
  );
  if (create.exitCode != 0) {
    throw StateError(
      'flutter create failed (exit ${create.exitCode})\n'
      'stdout:\n${create.stdout}\nstderr:\n${create.stderr}',
    );
  }
  return dir;
}

Future<String> _packageRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:dashcn_cli/dashcn_cli.dart'),
  );
  if (uri == null) {
    throw StateError('cannot resolve dashcn_cli package root');
  }
  return File.fromUri(uri).parent.parent.path;
}

import 'dart:io';

import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/create_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/kit_registry.dart';

void main() {
  group('create validation', () {
    late String registryRoot;
    late Directory work;
    String? unavailable;

    setUpAll(() {
      final kit = findKitPackageRoot();
      if (kit == null) {
        unavailable = 'dashcn kit not found (set DASHCN_KIT_ROOT)';
        return;
      }
      registryRoot = p.join(kit, 'lib', 'src');
      if (!Directory(registryRoot).existsSync()) {
        unavailable = 'kit registry missing at $registryRoot';
        return;
      }
      if (!File(p.join(registryRoot, 'starters', 'saas', 'starter.json'))
          .existsSync()) {
        unavailable = 'kit starters missing (need P9-6 kit)';
        return;
      }
      work = Directory.systemTemp.createTempSync('dashcn_create_unit_');
    });

    tearDownAll(() {
      if (unavailable == null && work.existsSync()) {
        work.deleteSync(recursive: true);
      }
    });

    Future<int> runCreate(List<String> args) async {
      final parser = buildCliParser();
      final results = parser.parse(
        normalizeCliArgs(['--registry', registryRoot, ...args]),
      );
      return runCreateCommand(
        createCommand: results.command!,
        rootArgs: results,
        projectRoot: work.path,
        registryOverride: registryRoot,
      );
    }

    test('unknown starter is usage', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      final code = await runCreate(['create', 'nosuch', 'my_app', '--dry-run']);
      expect(code, ExitCodes.usage);
    });

    test('unknown preset is usage', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      final code = await runCreate(
        ['create', 'saas', 'my_app', '--theme', 'nosuch', '--dry-run'],
      );
      expect(code, ExitCodes.usage);
    });

    test('bad mode is usage', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      final code = await runCreate(
        ['create', 'saas', 'my_app', '--mode', 'weird', '--dry-run'],
      );
      expect(code, ExitCodes.usage);
    });

    test('bad platforms is usage', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      final code = await runCreate(
        ['create', 'saas', 'my_app', '--platforms', 'ios,atari', '--dry-run'],
      );
      expect(code, ExitCodes.usage);
    });

    test('dry-run prints the plan', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      final code = await runCreate(
        ['create', 'chat', 'my_app', '--dry-run'],
      );
      expect(code, ExitCodes.success);
    });

    test('refuses a non-empty dir without --force', () async {
      if (unavailable != null) {
        markTestSkipped(unavailable!);
        return;
      }
      final target = Directory(p.join(work.path, 'taken_app'))
        ..createSync(recursive: true);
      File(p.join(target.path, 'x.txt')).writeAsStringSync('taken');
      final code = await runCreate(['create', 'shop', 'taken_app']);
      expect(code, ExitCodes.usage);
    });
  });
}

// Starter create validation: arg guards plus dry-run against the real kit.

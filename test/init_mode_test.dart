import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/init_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/v2_registry_fixture.dart';

void main() {
  group('init --mode', () {
    late V2RegistryFixture fixture;
    late Directory project;

    setUp(() {
      fixture = V2RegistryFixture.create();
      project = Directory.systemTemp.createTempSync('init_mode_app_');
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
        'name: init_mode_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
    });

    tearDown(() {
      fixture.dispose();
      project.deleteSync(recursive: true);
    });

    ({ArgResults root, ArgResults command}) parse(List<String> args) {
      final results = buildCliParser()
          .parse(normalizeCliArgs(['--registry', fixture.root, ...args]));
      return (root: results, command: results.command!);
    }

    Future<int> run(List<String> args) {
      final parsed = parse(args);
      return runZoned(
        () => runInitCommand(
          initCommand: parsed.command,
          rootArgs: parsed.root,
          projectRoot: project.path,
          registryOverride: fixture.root,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) {},
        ),
      );
    }

    bool exists(String rel) =>
        File(p.join(project.path, p.normalize(rel))).existsSync();

    test('package mode writes config only', () async {
      final code = await run(['init', '--mode', 'package', '--json']);

      expect(code, ExitCodes.success);
      final config = await DashcnConfig.load(project.path);
      expect(config.effectiveInstallMode, DashcnConfig.installModePackage);
      expect(exists('dashcn.lock'), isTrue);
      expect(exists('lib/ui/dashcn/foundation/data.dart'), isFalse);
      expect(exists('lib/ui/dashcn/theme/app_theme.dart'), isFalse);
    });

    test('copy mode installs the core and theme', () async {
      final code = await run(
        ['init', '--mode', 'copy', '--theme', 'vercel', '--yes'],
      );

      expect(code, ExitCodes.success);
      final config = await DashcnConfig.load(project.path);
      expect(config.effectiveInstallMode, DashcnConfig.installModeCopy);
      expect(exists('lib/ui/dashcn/foundation/data.dart'), isTrue);
      expect(exists('lib/ui/dashcn/theme/app_theme.dart'), isTrue);
    });

    test('an invalid mode is a usage error', () async {
      final code = await run(['init', '--mode', 'own']);

      expect(code, ExitCodes.usage);
    });
  });
}

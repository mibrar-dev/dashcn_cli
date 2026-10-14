import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/application/services/eject/eject_service.dart';
import 'package:dashcn_cli/src/application/services/manifest_closure.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/add_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/dry_run_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/eject_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/info_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/list_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/remove_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/search_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/update_command.dart';
import 'package:dashcn_cli/src/presentation/cli/commands_doctor.dart';
import 'package:dashcn_cli/src/registry/manifest/registry_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/v2_registry_fixture.dart';

/// The user-facing side of the flows layer (P9-3b): `add flow:<id>`,
/// `list --flows`, `search`, `info flow:<id>`, `remove`, `update` and
/// `doctor`. Package mode resolves the per-flow library import.
void main() {
  group('flows commands', () {
    late V2RegistryFixture fixture;
    late Directory project;

    setUp(() {
      fixture = V2RegistryFixture.create();
      project = Directory.systemTemp.createTempSync('flows_commands_app_');
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(
        'name: flows_app\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
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

    Future<({int code, String out})> capture(
      Future<int> Function() run,
    ) async {
      final buffer = StringBuffer();
      final out = _RecordingSink((line) => buffer.writeln(line));
      final err = _RecordingSink((line) => buffer.writeln(line));
      final code = await runZoned(
        () => IOOverrides.runZoned(run, stdout: () => out, stderr: () => err),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => buffer.writeln(line),
        ),
      );
      return (code: code, out: buffer.toString());
    }

    Future<({int code, String out})> add(List<String> args) => capture(
          () => runAddCommand(
            addCommand: parse(['add', ...args]).command,
            rootArgs: parse(['add', ...args]).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ),
        );

    Future<({int code, String out})> runList(List<String> args) => capture(
          () => runListCommand(
            listCommand: parse(['list', ...args]).command,
            rootArgs: parse(['list', ...args]).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ),
        );

    String file(String rel) => p.join(project.path, rel);
    bool exists(String rel) => File(file(rel)).existsSync();

    Map<String, dynamic> jsonOf(String out) =>
        jsonDecode(out) as Map<String, dynamic>;

    Map<String, dynamic> lock() =>
        jsonDecode(File(file('dashcn.lock')).readAsStringSync())
            as Map<String, dynamic>;

    test('flow: prefix helpers strip and detect', () {
      expect(isFlowAddress('flow:auth-01'), isTrue);
      expect(isFlowAddress('auth-01'), isFalse);
      expect(stripFlowPrefix('flow:auth-01'), 'auth-01');
      expect(stripFlowPrefix('button'), 'button');
    });

    test('closure resolves a flow: address and a bare flow id', () {
      final manifest = RegistryManifest.fromJson(
        jsonDecode(
          File(p.join(fixture.root, 'manifests', 'registry.json'))
              .readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final prefixed =
          ManifestClosureResolver(manifest).resolve(['flow:auth-01']);
      expect(prefixed.flows, ['auth-01']);
      expect(prefixed.components, ['button']);
      expect(
        prefixed.files,
        contains('flows/auth-01/flow.dart'),
      );
      final bare = ManifestClosureResolver(manifest).resolve(['auth-01']);
      expect(bare.flows, ['auth-01']);
    });

    test('add installs a flow with its components', () async {
      final result = await add(['flow:auth-01']);
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/dashcn/flows/auth-01/flow.dart'), isTrue);
      expect(exists('lib/ui/dashcn/components/button/button.dart'), isTrue);
      final flows = lock()['flows'] as List;
      expect(flows, hasLength(1));
      final flow = flows.single as Map<String, dynamic>;
      expect(flow['id'], 'auth-01');
      expect(
        (flow['files'] as Map).keys.single,
        'lib/ui/dashcn/flows/auth-01/flow.dart',
      );
      expect((flow['deps'] as Map)['components'], ['button']);
      expect(lock()['lockfileVersion'], 2);
      expect(
        [
          for (final entry in lock()['components'] as List)
            (entry as Map)['id'],
        ],
        ['button'],
      );
    });

    test('add accepts the bare flow id too', () async {
      final result = await add(['auth-01']);
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/dashcn/flows/auth-01/flow.dart'), isTrue);
      expect((lock()['flows'] as List), hasLength(1));
    });

    test('add installs a flow together with its block closure', () async {
      final newContent = "import '../../blocks/login-01/login_01.dart';\n\n"
          'class Auth01Flow {}\n';
      final newSha = fixture.writeRegistryFile(
        'flows/auth-01/flow.dart',
        newContent,
      );
      final manifest = jsonDecode(
        File(p.join(fixture.root, 'manifests', 'registry.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final flows = manifest['flows'] as Map<String, dynamic>;
      final auth = flows['auth-01'] as Map<String, dynamic>;
      final deps = auth['deps'] as Map<String, dynamic>;
      deps['blocks'] = ['login-01'];
      (manifest['fileHashes']
          as Map<String, dynamic>)['flows/auth-01/flow.dart'] = newSha;
      fixture.writeManifest(manifest);

      final result = await add(['flow:auth-01']);
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/dashcn/flows/auth-01/flow.dart'), isTrue);
      expect(exists('lib/ui/dashcn/blocks/login-01/login_01.dart'), isTrue);
      expect(
        [for (final entry in lock()['flows'] as List) (entry as Map)['id']],
        ['auth-01'],
      );
      expect(
        [for (final entry in lock()['blocks'] as List) (entry as Map)['id']],
        ['login-01'],
      );
    });

    test('add --dry-run plans the flow without writing', () async {
      final result = await add(['flow:auth-01', '--dry-run', '--json']);
      expect(result.code, ExitCodes.success);
      final plan = (jsonOf(result.out)['data'] as Map)['plan'] as Map;
      expect(plan['flows'], ['auth-01']);
      expect(plan['components'], ['button']);
      expect(exists('lib/ui/dashcn/flows/auth-01/flow.dart'), isFalse);
    });

    test('dry-run command resolves a flow too', () async {
      final args = parse(['dry-run', 'flow:auth-01', '--json']);
      final result = await capture(() => runDryRunCommand(
            dryRunCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect((jsonOf(result.out)['data'] as Map)['flows'], ['auth-01']);
    });

    test('add --package prints the per-flow import without copying', () async {
      final result =
          await add(['flow:auth-01', '--package', '--dry-run', '--json']);
      expect(result.code, ExitCodes.success);
      final data = jsonOf(result.out)['data'] as Map;
      expect(
        (data['imports'] as Map)['flow:auth-01'],
        'package:dashcn/flows/auth_01.dart',
      );
      expect(exists('lib/ui/dashcn/flows/auth-01/flow.dart'), isFalse);
    });

    test('an unknown flow id still exits 30', () async {
      final result = await add(['flow:nope-01']);
      expect(result.code, ExitCodes.componentMissing);
      expect(result.out, contains('Unknown flow id "nope-01"'));
    });

    test('list --flows shows the flow with kind flow', () async {
      final flows = await runList(['--flows', '--json']);
      expect(flows.code, ExitCodes.success);
      final data = (jsonOf(flows.out)['data'] as Map);
      expect(data['kind'], 'flow');
      expect(data['count'], 1);
      final flow = (data['flows'] as List).single as Map;
      expect(flow['id'], 'auth-01');
      expect(flow['kind'], 'flow');
      expect(flow['viewport'], 'mobile');
      expect(data['components'], isEmpty);
      expect(data['blocks'], isEmpty);
    });

    test('list --blocks and --flows cannot combine', () async {
      final result = await runList(['--blocks', '--flows']);
      expect(result.code, ExitCodes.usage);
    });

    test('search finds a flow and reports its kind', () async {
      final args = parse(['search', 'auth', '--json']);
      final result = await capture(() => runSearchCommand(
            searchCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final data = (jsonOf(result.out)['data'] as Map);
      final flows = data['flows'] as List;
      expect(flows, hasLength(1));
      expect((flows.single as Map)['kind'], 'flow');
    });

    test('info resolves a flow: address', () async {
      final args = parse(['info', 'flow:auth-01', '--json']);
      final result = await capture(() => runInfoCommand(
            infoCommand: args.command,
            rootArgs: args.root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      final data = jsonOf(result.out)['data'] as Map;
      expect(data['kind'], 'flow');
      expect(data['viewport'], 'mobile');
      expect(data['screens'], ['Sign in']);
      expect(data['install'], 'dashcn add flow:auth-01');
      expect(
        data['import'],
        'package:<your_app>/lib/ui/dashcn/flows/auth-01/flow.dart',
      );
      expect((data['closure'] as Map)['components'], ['button']);
    });

    test('update refreshes an installed flow', () async {
      await add(['flow:auth-01']);
      fixture.writeRegistryFile(
        'flows/auth-01/flow.dart',
        'class Auth01Flow { final v = 2; }\n',
      );
      final report = await capture(() => runUpdateCommand(
            updateCommand: parse(['update', '--json']).command,
            rootArgs: parse(['update', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      final data = (jsonOf(report.out)['data'] as Map);
      expect(
        data['updated'],
        contains('lib/ui/dashcn/flows/auth-01/flow.dart'),
      );
    });

    test('doctor is clean with a flow installed', () async {
      await add(['flow:auth-01']);
      final result = await capture(() => runDoctorCommand(
            doctorCommand: parse(['doctor', '--json']).command,
            rootArgs: parse(['doctor', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, DoctorExit.clean);
      expect((jsonOf(result.out)['data'] as Map)['errors'], isEmpty);
    });

    test('remove deletes the flow files and keeps its components', () async {
      await add(['flow:auth-01']);
      final result = await capture(() => runRemoveCommand(
            removeCommand: parse(['remove', 'flow:auth-01', '--json']).command,
            rootArgs: parse(['remove', 'flow:auth-01', '--json']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.success);
      expect(exists('lib/ui/dashcn/flows/auth-01/flow.dart'), isFalse);
      expect(exists('lib/ui/dashcn/components/button/button.dart'), isTrue);
      expect(lock()['flows'], isEmpty);
    });

    test('eject refuses a flow with a clear message', () async {
      await add(['flow:auth-01']);
      final result = await capture(() => runEjectCommand(
            ejectCommand: parse(['eject', 'flow:auth-01']).command,
            rootArgs: parse(['eject', 'flow:auth-01']).root,
            projectRoot: project.path,
            registryOverride: fixture.root,
          ));
      expect(result.code, ExitCodes.componentMissing);
      expect(result.out, contains('cannot be ejected'));
      expect(
        EjectException('x').toString(),
        isA<String>(),
      );
    });
  });
}

class _RecordingSink implements Stdout {
  _RecordingSink(this.onLine);

  final void Function(String line) onLine;

  @override
  Encoding encoding = utf8;

  void _record(Object? object) {
    if (object == null) return;
    final text = '$object';
    if (text.isEmpty) return;
    onLine(text.endsWith('\n') ? text.substring(0, text.length - 1) : text);
  }

  @override
  Future<void> get done => Future<void>.value();

  @override
  bool get hasTerminal => false;

  @override
  IOSink get nonBlocking => this;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  String get lineTerminator => '\n';

  @override
  set lineTerminator(String value) {
    if (value != '\n') throw ArgumentError.value(value, 'lineTerminator');
  }

  @override
  void add(List<int> data) => _record(encoding.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) => _record(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    objects.forEach(_record);
  }

  @override
  void writeCharCode(int charCode) => _record(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => _record('$object\n');
}

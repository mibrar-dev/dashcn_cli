import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/presentation/cli/commands/theme_interop_command.dart';
import 'package:dashcn_cli/src/theme_interop/interop.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A tweakcn-shaped theme: oklch tokens, radius, fonts and one unknown
/// variable (which must be ignored with a reason, never silently).
const String _kTweakCss = '''
:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.141 0.005 285.823);
  --primary: oklch(0.21 0.006 285.885);
  --primary-foreground: oklch(0.985 0 0);
  --radius: 0.625rem;
  --font-sans: Inter, sans-serif;
  --tweakcn-mystery: 42;
}
.dark {
  --background: oklch(0.141 0.005 285.823);
  --foreground: oklch(0.985 0 0);
  --primary: oklch(0.92 0.004 286.32);
  --primary-foreground: oklch(0.21 0.006 285.885);
}
''';

/// Runs [body] with `stdout`/`stderr` captured.
Future<T> _capture<T>(
  Future<T> Function() body,
  List<String> out,
  List<String> err,
) {
  return IOOverrides.runZoned(
    body,
    stdout: () => _Sink(out),
    stderr: () => _Sink(err),
  );
}

void main() {
  late Directory temp;
  late List<String> out;
  late List<String> err;
  late CliLogger logger;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('theme_interop_');
    out = <String>[];
    err = <String>[];
    logger = CliLogger(useColor: false);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  File cssFile() =>
      File(p.join(temp.path, 'theme.css'))..writeAsStringSync(_kTweakCss);

  File presetFile(String id) => File(
        p.join(temp.path, 'lib', 'ui', 'dashcn', 'theme', '$id.json'),
      );

  Future<int> importTheme(
    String source, {
    String? name,
    bool apply = false,
  }) {
    return _capture(
      () => runThemeImport(
        source: source,
        name: name,
        apply: apply,
        projectRoot: temp.path,
        installRootOverride: null,
        logger: logger,
      ),
      out,
      err,
    );
  }

  Future<int> exportTheme({String? format, String? outPath}) {
    return _capture(
      () => runThemeExport(
        formatName: format,
        out: outPath,
        projectRoot: temp.path,
        installRootOverride: null,
        logger: logger,
      ),
      out,
      err,
    );
  }

  group('theme import', () {
    test('stores a preset JSON and prints the report', () async {
      final int code = await importTheme(cssFile().path, name: 'tweak');
      expect(code, ExitCodes.success);
      expect(out.join('\n'), contains('Imported CSS as "tweak"'));
      expect(out.join('\n'), contains('mapped '));
      expect(out.join('\n'), contains('ignored'));
      final File stored = presetFile('tweak');
      expect(stored.existsSync(), isTrue);
      final Map<String, dynamic> decoded =
          jsonDecode(stored.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['id'], 'tweak');
      expect(decoded['schemaVersion'], 2);
      expect((decoded['light'] as Map)['background'], isNotNull);
    });

    test('derives the id from the file name when --name is absent', () async {
      expect(await importTheme(cssFile().path), ExitCodes.success);
      expect(presetFile('theme').existsSync(), isTrue);
    });

    test('records the exact on-disk bytes so doctor stays clean', () async {
      // P8-6: the import once hashed the JSON before the trailing newline
      // `_writeProjectFile` appends, so `doctor` always flagged the stored
      // preset as modified. The lock must describe the bytes on disk.
      expect(
          await importTheme(cssFile().path, name: 'tweak'), ExitCodes.success);
      final File stored = presetFile('tweak');
      final Map<String, dynamic> lock = jsonDecode(
        File(p.join(temp.path, 'dashcn.lock')).readAsStringSync(),
      ) as Map<String, dynamic>;
      final Map<String, dynamic> theme = lock['theme'] as Map<String, dynamic>;
      expect(theme['id'], 'tweak');
      expect(theme['path'], 'lib/ui/dashcn/theme/tweak.json');
      expect(theme['sha256'], await FileHashing.ofFile(stored));
    });

    test('missing source is a usage error', () async {
      final int code = await _capture(
        () => runThemeImport(
          source: '   ',
          name: 'x',
          apply: false,
          projectRoot: temp.path,
          installRootOverride: null,
          logger: logger,
        ),
        out,
        err,
      );
      expect(code, ExitCodes.usage);
      expect(err.join('\n'), contains('missing <file|url>'));
    });

    test('a missing file is an IO error', () async {
      final int code = await importTheme(
        p.join(temp.path, 'nope.css'),
        name: 'x',
      );
      expect(code, ExitCodes.ioError);
      expect(err.join('\n'), contains('File not found'));
    });

    test('--apply renders app_theme.dart without a registry', () async {
      final int code = await importTheme(
        cssFile().path,
        name: 'tweak',
        apply: true,
      );
      expect(code, ExitCodes.success);
      final File appTheme = File(
        p.join(temp.path, 'lib', 'ui', 'dashcn', 'theme', 'app_theme.dart'),
      );
      expect(appTheme.existsSync(), isTrue);
      expect(appTheme.readAsStringSync(), contains('buildTweakTheme'));
      final Map<String, dynamic> lock =
          jsonDecode(File(p.join(temp.path, 'dashcn.lock')).readAsStringSync())
              as Map<String, dynamic>;
      expect((lock['theme'] as Map)['id'], 'tweak');
    });

    test('preset JSON imports losslessly', () async {
      await importTheme(cssFile().path, name: 'tweak');
      final int code = await importTheme(presetFile('tweak').path, name: 'two');
      expect(code, ExitCodes.success);
      expect(
        jsonDecode(presetFile('two').readAsStringSync())['light'],
        jsonDecode(presetFile('tweak').readAsStringSync())['light'],
      );
    });
  });

  group('theme export', () {
    test('without an applied theme it explains what to do', () async {
      final int code = await exportTheme(format: 'css');
      expect(code, ExitCodes.validationFailed);
      expect(err.join('\n'), contains('no theme applied yet'));
    });

    test('an unknown format is a usage error', () async {
      await importTheme(cssFile().path, name: 'tweak', apply: true);
      final int code = await exportTheme(format: 'xml');
      expect(code, ExitCodes.usage);
      expect(err.join('\n'), contains('unknown --format'));
    });

    test('every format equals its writer output', () async {
      await importTheme(cssFile().path, name: 'tweak', apply: true);
      final Map<String, dynamic> preset = jsonDecode(
        presetFile('tweak').readAsStringSync(),
      ) as Map<String, dynamic>;
      final WebTheme theme = webThemeFromPresetJson(
        preset.map(
          (String key, dynamic value) =>
              MapEntry<String, Object?>(key, value as Object?),
        ),
      );
      final Map<String, String> expected = <String, String>{
        'css': writeWebCss(theme),
        'tailwind': writeTailwindV4Theme(theme),
        'dtcg': writeDtcgTokens(theme),
      };
      for (final MapEntry<String, String> entry in expected.entries) {
        out.clear();
        final int code = await exportTheme(format: entry.key);
        expect(code, ExitCodes.success);
        expect(out.join('\n').trim(), entry.value.trim());
      }
    });

    test('--out writes a file', () async {
      await importTheme(cssFile().path, name: 'tweak', apply: true);
      final String target = p.join(temp.path, 'theme.tokens.json');
      final int code = await exportTheme(format: 'dtcg', outPath: target);
      expect(code, ExitCodes.success);
      expect(File(target).existsSync(), isTrue);
      final Object? decoded = jsonDecode(File(target).readAsStringSync());
      expect((decoded as Map).keys, containsAll(<String>['light', 'dark']));
    });

    test('export DTCG, re-import the preset, same tokens', () async {
      await importTheme(cssFile().path, name: 'tweak');
      final String first = p.join(temp.path, 'a.tokens.json');
      expect(
          await exportTheme(format: 'dtcg', outPath: first), ExitCodes.success);
      // A plain import becomes the current theme, so export follows it.
      expect(
        await importTheme(presetFile('tweak').path, name: 'again'),
        ExitCodes.success,
      );
      final String second = p.join(temp.path, 'b.tokens.json');
      expect(await exportTheme(format: 'dtcg', outPath: second),
          ExitCodes.success);
      expect(
        File(second).readAsStringSync(),
        File(first).readAsStringSync(),
      );
    });
  });
}

/// Minimal [Stdout] stand-in recording written lines.
class _Sink implements Stdout {
  _Sink(this.lines);

  final List<String> lines;

  @override
  Encoding encoding = utf8;

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
  set lineTerminator(String value) {}

  @override
  void add(List<int> data) => lines.add(encoding.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) => lines.add('$object');

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      lines.add(objects.join(separator));

  @override
  void writeCharCode(int charCode) => lines.add(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => lines.add('$object');
}

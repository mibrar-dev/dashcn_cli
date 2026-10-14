import 'package:dashcn_cli/src/application/services/starter/starter_template.dart';
import 'package:dashcn_cli/src/presentation/cli/cli_parser.dart';
import 'package:test/test.dart';

void main() {
  group('starter template rendering', () {
    test('replaces all five vars', () {
      const template = '{{appName}} {{packageName}} {{imports}} '
          '{{themePreset}} {{themeBuild}}';
      final out = renderStarterTemplate(template, {
        'appName': 'My App',
        'packageName': 'my_app',
        'imports': "import 'x';",
        'themePreset': 'neutral',
        'themeBuild': 'buildNeutralTheme',
      });
      expect(
        out,
        "My App my_app import 'x'; neutral buildNeutralTheme",
      );
    });

    test('leaves unknown placeholders alone', () {
      const template = '{{unknown}} {{appName}}';
      final out = renderStarterTemplate(template, {'appName': 'My App'});
      expect(out, '{{unknown}} My App');
    });

    test('theme build matches kit camel case', () {
      expect(starterThemeBuild('neutral'), 'buildNeutralTheme');
      expect(starterThemeBuild('amber-minimal'), 'buildAmberMinimalTheme');
      expect(starterThemeBuild('modern-minimal'), 'buildModernMinimalTheme');
    });

    test('app name title cases the package', () {
      expect(starterAppName('my_app'), 'My App');
      expect(starterAppName('shop'), 'Shop');
    });

    test('package names validate and sanitize', () {
      expect(isValidPackageName('my_app'), isTrue);
      expect(isValidPackageName('My-App'), isFalse);
      expect(sanitizePackageName('My-App'), 'my_app');
    });

    test('imports differ per mode and target', () {
      final pkg = starterImports(
        starterId: 'saas',
        target: 'lib/app.dart',
        mode: 'package',
      );
      final copy = starterImports(
        starterId: 'saas',
        target: 'lib/app.dart',
        mode: 'copy',
      );
      expect(pkg, contains('package:dashcn/dashcn.dart'));
      expect(pkg, contains('package:dashcn/flows/auth_01.dart'));
      expect(copy, contains('ui/dashcn/components/app/app.dart'));
      expect(copy, contains('ui/dashcn/flows/auth-01/flow.dart'));
      expect(pkg, isNot(contains('ui/dashcn/components')));
      expect(copy, isNot(contains('package:dashcn')));
    });

    test('shell imports cover blocks and flows', () {
      final pkg = starterImports(
        starterId: 'saas',
        target: 'lib/shell.dart',
        mode: 'package',
      );
      expect(pkg, contains('package:dashcn/blocks/dashboard_01.dart'));
      expect(pkg, contains('package:dashcn/flows/settings_01.dart'));
      final copy = starterImports(
        starterId: 'shop',
        target: 'lib/shop/product_grid.dart',
        mode: 'copy',
      );
      expect(copy, contains('ui/dashcn/components/card/card.dart'));
      expect(copy, contains('ui/dashcn/components/image/image.dart'));
    });
  });

  group('create parser', () {
    test('parses starter, name and flags', () {
      final parser = buildCliParser();
      final results = parser.parse([
        'create',
        'saas',
        'my_app',
        '--mode',
        'package',
        '--theme',
        'vercel',
        '--platforms',
        'ios,android',
        '--org',
        'com.example',
        '--force',
        '--dry-run',
      ]);
      final command = results.command!;
      expect(command.name, 'create');
      expect(command.rest, ['saas', 'my_app']);
      expect(command['mode'], 'package');
      expect(command['theme'], 'vercel');
      expect(command['platforms'], 'ios,android');
      expect(command['org'], 'com.example');
      expect(command['force'], isTrue);
      expect(command['dry-run'], isTrue);
    });

    test('parses --list', () {
      final parser = buildCliParser();
      final results = parser.parse(['create', '--list']);
      expect(results.command!['list'], isTrue);
    });
  });
}

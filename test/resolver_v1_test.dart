import 'dart:io';

import 'package:dashcn_cli/src/resolver_v1.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ResolverV1', () {
    test('normalizes base URL with exactly one trailing slash', () {
      expect(
        ResolverV1.normalizeBaseUrl('https://example.com/root/path'),
        'https://example.com/root/path/',
      );
      expect(
        ResolverV1.normalizeBaseUrl('https://example.com/root/path///'),
        'https://example.com/root/path/',
      );
    });

    test('resolves by concatenation without discarding base path', () {
      final resolved = ResolverV1.resolveUrl(
        'https://example.com/base/path',
        '/registry/components.json',
      );
      expect(
        resolved.toString(),
        'https://example.com/base/path/registry/components.json',
      );
    });

    test('normalizes github tree base URL to raw base URL', () {
      final normalized = ResolverV1.normalizeBaseUrl(
        'https://github.com/mibrar-dev/shadcn_flutter_kit/tree/main/dashcn/lib/src',
      );
      expect(
        normalized,
        'https://raw.githubusercontent.com/mibrar-dev/shadcn_flutter_kit/main/dashcn/lib/src/',
      );
    });

    test('builds github contents API URL for file lookup', () {
      final apiUrl = ResolverV1.githubApiContentsUrl(
        'https://github.com/mibrar-dev/shadcn_flutter_kit/tree/main/dashcn/lib/src',
        'manifests/components.json',
      );
      expect(
        apiUrl,
        'https://api.github.com/repos/mibrar-dev/shadcn_flutter_kit/contents/dashcn/lib/src/manifests/components.json?ref=main',
      );
    });

    test('rejects invalid relative paths', () {
      const badPaths = [
        '../escape.json',
        r'registry\index.json',
        'registry/file.json?x=1',
        'registry/file.json#frag',
        'registry//file.json',
      ];
      for (final bad in badPaths) {
        expect(
          () => ResolverV1.normalizeRelativePath(bad),
          throwsA(isA<ResolverV1Exception>()),
        );
      }
    });
  });

  group('ProjectPathGuard', () {
    test('allows project-root relative writes', () {
      final root = Directory.systemTemp.createTempSync('path_guard_');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      final safe = ProjectPathGuard.resolveSafeWritePath(
        projectRoot: root.path,
        destinationRelativePath: 'lib/ui/dashcn/button.dart',
      );
      expect(safe, p.join(root.path, 'lib/ui/dashcn/button.dart'));
    });

    test('rejects traversal outside project root', () {
      expect(
        () => ProjectPathGuard.resolveSafeWritePath(
          projectRoot: '/tmp/my_app',
          destinationRelativePath: '../evil.dart',
        ),
        throwsA(isA<ResolverV1Exception>()),
      );
    });
  });

  group('InitPathMapper', () {
    test('maps copyFiles with base/destBase', () {
      final mapped = InitPathMapper.mapCopyFileDestination(
        filePath: 'registry/shared/theme/color_scheme.dart',
        base: 'registry',
        destBase: 'lib/ui/dashcn',
      );
      expect(mapped, 'lib/ui/dashcn/shared/theme/color_scheme.dart');
    });

    test('maps copyFiles with relative file path under base', () {
      final mapped = InitPathMapper.mapCopyFileDestination(
        filePath: 'theme/theme.dart',
        base: 'registry/shared',
        destBase: 'lib/ui/dashcn/shared',
      );
      expect(mapped, 'lib/ui/dashcn/shared/theme/theme.dart');
    });

    test('maps copyFiles source path relative to base without rejecting prefix',
        () {
      final destination = InitPathMapper.mapCopyFileDestination(
        filePath: 'theme/theme.dart',
        base: 'registry/shared',
        destBase: 'lib/ui/dashcn/shared',
      );
      final source = InitPathMapper.mapSourcePath(
        filePath: 'theme/theme.dart',
        base: 'registry/shared',
      );

      expect(destination, 'lib/ui/dashcn/shared/theme/theme.dart');
      expect(source, 'registry/shared/theme/theme.dart');
    });

    test('maps copyFiles source path by prepending base when needed', () {
      final sourceRel = InitPathMapper.mapSourcePath(
        filePath: 'theme/theme.dart',
        base: 'registry/shared',
      );
      expect(sourceRel, 'registry/shared/theme/theme.dart');
    });

    test('maps copyDir destination with base/destBase', () {
      final mapped = InitPathMapper.mapCopyDirDestination(
        filePath: 'registry/components/button/button.dart',
        from: 'components',
        to: 'components',
        base: 'registry',
        destBase: 'lib/ui/dashcn',
      );
      expect(mapped, 'lib/ui/dashcn/components/button/button.dart');
    });

    test('maps copyDir destination when file path is relative to base', () {
      final mapped = InitPathMapper.mapCopyDirDestination(
        filePath: 'shared/fonts/bootstrap.otf',
        from: 'shared/fonts',
        to: 'assets/fonts',
        base: 'registry',
        destBase: '.',
      );
      expect(mapped, 'assets/fonts/bootstrap.otf');
    });

    test('rejects copyDir source outside base/from prefix', () {
      expect(
        () => InitPathMapper.mapCopyDirDestination(
          filePath: 'registry/shared/button.dart',
          from: 'components',
          to: 'components',
          base: 'registry',
          destBase: 'lib/ui/dashcn',
        ),
        throwsA(isA<ResolverV1Exception>()),
      );
    });

    test('rejects base-relative copyDir source outside from prefix', () {
      expect(
        () => InitPathMapper.mapCopyDirDestination(
          filePath: 'shared/button.dart',
          from: 'components',
          to: 'components',
          base: 'registry',
          destBase: 'lib/ui/dashcn',
        ),
        throwsA(isA<ResolverV1Exception>()),
      );
    });
  });
}

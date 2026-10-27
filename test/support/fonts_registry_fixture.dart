import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:path/path.dart' as p;

/// A minimal fonts-aware registry: two components plus the contract `fonts`
/// map (`geist-sans`, `geist-mono`, `noto-symbols`) with real binary font
/// files under `assets/fonts/`.
///
/// `dashcn add` must never install a font, so the fixture also proves the
/// component closure carries no font path. Until the kit's registry ships the
/// `fonts` map, tests run against this fixture instead of the real registry.
class FontsRegistryFixture {
  FontsRegistryFixture._(this.root);

  /// Absolute registry root (holds `manifests/`, `assets/fonts/`, ...).
  final String root;

  static const String buttonDart = "import '../../foundation/data.dart';\n\n"
      'class Button {}\n';
  static const String inputDart = "import '../../foundation/data.dart';\n"
      "import '../button/button.dart';\n\n"
      'class Input {}\n';

  /// Deliberately non-UTF8 bytes: copies must be binary-safe.
  static List<int> fontBytes(int seed) =>
      [seed, 0, 1, 2, 255, 254, 253, seed, 13, 10, 0];

  static const Map<String, int> fontFiles = {
    'assets/fonts/Geist-Regular.otf': 11,
    'assets/fonts/Geist-Bold.otf': 22,
    'assets/fonts/Geist-Italic.otf': 33,
    'assets/fonts/GeistMono-Regular.otf': 44,
    'assets/fonts/GeistMono-Bold.otf': 55,
    'assets/fonts/NotoSansSymbols2-Regular.ttf': 66,
  };

  static FontsRegistryFixture create({String? parent}) {
    final dir = Directory(
      p.join(parent ?? Directory.systemTemp.path,
          'dashcn_fonts_fixture_${DateTime.now().microsecondsSinceEpoch}'),
    )..createSync(recursive: true);
    final root = dir.path;

    final files = <String, String>{
      'foundation/data.dart': 'class Data {}\n',
      'theme/color_tokens.dart': 'class ColorTokens {}\n',
      'primitives/clickable.dart': 'class Clickable {}\n',
      'components/button/button.dart': buttonDart,
      'components/input/input.dart': inputDart,
    };
    files.forEach((rel, content) {
      final file = File(p.join(root, p.normalize(rel)));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    fontFiles.forEach((rel, seed) {
      final file = File(p.join(root, p.normalize(rel)));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(fontBytes(seed));
    });

    final manifest = buildManifest(fileHashes: {
      for (final entry in files.entries)
        entry.key: FileHashing.ofText(entry.value),
    });
    File(p.join(root, 'manifests', 'registry.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(manifest));

    return FontsRegistryFixture._(root);
  }

  static Map<String, dynamic> buildManifest({
    Map<String, String>? fileHashes,
  }) {
    return <String, dynamic>{
      'schemaVersion': 2,
      'registry': {
        'name': 'fonts-fixture',
        'version': '1.0.0',
        'ref': 'test',
      },
      'install': {
        'root': 'lib/ui/dashcn',
        'componentsDir': 'components',
        'blocksDir': 'blocks',
        'layerDirs': {
          'foundation': 'foundation',
          'theme': 'theme',
          'primitives': 'primitives',
        },
        'userOwnedSuffix': '_theme.dart',
      },
      'foundation': {
        'data': {
          'files': ['foundation/data.dart'],
        },
      },
      'theme': {
        'color_tokens': {
          'files': ['theme/color_tokens.dart'],
        },
      },
      'primitives': {
        'clickable': {
          'files': ['primitives/clickable.dart'],
          'deps': {'primitives': <String>[]},
        },
      },
      'components': {
        'button': {
          'name': 'Button',
          'category': 'core',
          'description': 'A button.',
          'entry': 'components/button/button.dart',
          'files': ['components/button/button.dart'],
          'userOwned': <String>[],
          'deps': {
            'foundation': ['data'],
            'theme': ['color_tokens'],
            'primitives': ['clickable'],
            'components': <String>[],
          },
          'tags': ['core'],
          'api': {
            'classes': ['Button'],
          },
        },
        'input': {
          'name': 'Input',
          'category': 'core',
          'description': 'An input.',
          'entry': 'components/input/input.dart',
          'files': ['components/input/input.dart'],
          'userOwned': <String>[],
          'deps': {
            'foundation': ['data'],
            'theme': <String>[],
            'primitives': ['clickable'],
            'components': ['button'],
          },
          'tags': ['form'],
          'api': {
            'classes': ['Input'],
          },
        },
      },
      'themes': <String, dynamic>{},
      'blocks': <String, dynamic>{},
      'fonts': buildFontsMap(),
      'fileHashes': fileHashes ?? <String, String>{},
    };
  }

  /// The shared contract: ids and family names exactly as specified.
  static Map<String, dynamic> buildFontsMap() {
    return <String, dynamic>{
      'geist-sans': {
        'families': [
          {
            'family': 'GeistSans',
            'files': [
              {
                'path': 'assets/fonts/Geist-Regular.otf',
                'weight': 400,
              },
              {
                'path': 'assets/fonts/Geist-Bold.otf',
                'weight': 700,
              },
              {
                'path': 'assets/fonts/Geist-Italic.otf',
                'weight': 400,
                'style': 'italic',
              },
            ],
          },
        ],
      },
      'geist-mono': {
        'families': [
          {
            'family': 'GeistMono',
            'files': [
              {
                'path': 'assets/fonts/GeistMono-Regular.otf',
                'weight': 400,
              },
              {
                'path': 'assets/fonts/GeistMono-Bold.otf',
                'weight': 700,
              },
            ],
          },
        ],
      },
      'noto-symbols': {
        'families': [
          {
            'family': 'NotoSansSymbols2',
            'files': [
              {
                'path': 'assets/fonts/NotoSansSymbols2-Regular.ttf',
                'weight': 400,
              },
            ],
          },
        ],
      },
    };
  }

  void writeManifest(Map<String, dynamic> manifest) {
    File(p.join(root, 'manifests', 'registry.json'))
        .writeAsStringSync(jsonEncode(manifest));
  }

  void dispose() {
    final dir = Directory(root);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  /// A [RegistrySource] over this fixture's registry root.
  RegistrySource get source => LocalRegistrySource(root);
}

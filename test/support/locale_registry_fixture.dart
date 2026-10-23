import 'dart:convert';
import 'dart:io';

import 'package:dashcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:path/path.dart' as p;

/// A minimal locale-aware registry: two components with distinct
/// `localizationKeys`, the neutral `localizations` primitive files and a tiny
/// `manifests/locale_tables.json` (English base plus `ar` and `de`).
///
/// `button` needs `announcementFailure` and `announcementLoading`; `dialog`
/// needs `announcementLoading` and `dialogDismiss`. The overlap exercises key
/// unioning; the distinct keys exercise subsetting.
class LocaleRegistryFixture {
  LocaleRegistryFixture._(this.root);

  /// Absolute registry root (holds `manifests/`, `foundation/`, ...).
  final String root;

  static const String buttonDart = "import '../../foundation/data.dart';\n\n"
      'class Button {}\n';
  static const String dialogDart = "import '../../foundation/data.dart';\n\n"
      'class Dialog {}\n';

  /// Neutral primitive files: the class the generated locales extend.
  static const String localizationsDart =
      "import 'package:flutter/widgets.dart';\n\n"
      'class ComponentLocalizations {\n'
      '  const ComponentLocalizations(this.locale);\n'
      '  final Locale locale;\n'
      '  static const ComponentLocalizations english =\n'
      "      ComponentLocalizations(Locale('en'));\n"
      '  String get announcementFailure => \'Failed\';\n'
      '  String get announcementLoading => \'Loading\';\n'
      "  String dialogDismiss(Object? value) => 'Dismiss \$value';\n"
      '}\n';

  static LocaleRegistryFixture create({String? parent}) {
    final dir = Directory(
      p.join(parent ?? Directory.systemTemp.path,
          'dashcn_locale_fixture_${DateTime.now().microsecondsSinceEpoch}'),
    )..createSync(recursive: true);
    final root = dir.path;

    final files = <String, String>{
      'foundation/data.dart': 'class Data {}\n',
      'theme/color_tokens.dart': 'class ColorTokens {}\n',
      'primitives/clickable.dart': 'class Clickable {}\n',
      'primitives/localizations/localizations.dart': localizationsDart,
      'primitives/localizations/localizations_misc.dart': 'class Misc {}\n',
      'components/button/button.dart': buttonDart,
      'components/dialog/dialog.dart': dialogDart,
    };
    files.forEach((rel, content) {
      final file = File(p.join(root, p.normalize(rel)));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });

    File(p.join(root, 'manifests', 'locale_tables.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(buildLocaleTables()));

    final manifest = buildManifest(fileHashes: {
      for (final entry in files.entries)
        entry.key: FileHashing.ofText(entry.value),
    });
    File(
      p.join(root, 'manifests', 'registry.json'),
    ).writeAsStringSync(jsonEncode(manifest));

    return LocaleRegistryFixture._(root);
  }

  static Map<String, dynamic> buildLocaleTables() {
    return <String, dynamic>{
      'keyCount': 3,
      'keys': {
        'announcementFailure': {
          'signature': '',
          'en': "'Failed'",
        },
        'announcementLoading': {
          'signature': '',
          'en': "'Loading'",
        },
        'dialogDismiss': {
          'signature': '(Object? value)',
          'en': "'Dismiss \$value'",
        },
      },
      'locales': {
        'ar': {
          'direction': 'rtl',
          'overrides': {
            'announcementFailure': "'فشل'",
            'announcementLoading': "'جارٍ التحميل'",
            'dialogDismiss': "'تجاهل \$value'",
          },
        },
        'de': {
          'direction': 'ltr',
          'overrides': {
            'announcementFailure': "'Fehlgeschlagen'",
          },
        },
      },
    };
  }

  static Map<String, dynamic> buildManifest({
    Map<String, String>? fileHashes,
  }) {
    return <String, dynamic>{
      'schemaVersion': 2,
      'registry': {
        'name': 'locale-fixture',
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
        'localizations': {
          'files': [
            'primitives/localizations/localizations.dart',
            'primitives/localizations/localizations_misc.dart',
          ],
          'deps': {'primitives': <String>[]},
          'packages': [
            {'name': 'intl', 'constraint': '^0.20.2'},
          ],
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
            'primitives': ['clickable', 'localizations'],
            'components': <String>[],
          },
          'tags': ['core'],
          'api': {
            'classes': ['Button'],
          },
          'localizationKeys': [
            'announcementFailure',
            'announcementLoading',
          ],
        },
        'dialog': {
          'name': 'Dialog',
          'category': 'core',
          'description': 'A dialog.',
          'entry': 'components/dialog/dialog.dart',
          'files': ['components/dialog/dialog.dart'],
          'userOwned': <String>[],
          'deps': {
            'foundation': ['data'],
            'theme': <String>[],
            'primitives': ['clickable', 'localizations'],
            'components': <String>[],
          },
          'tags': ['overlay'],
          'api': {
            'classes': ['Dialog'],
          },
          'localizationKeys': [
            'announcementLoading',
            'dialogDismiss',
          ],
        },
      },
      'themes': <String, dynamic>{},
      'blocks': <String, dynamic>{},
      'fileHashes': fileHashes ?? <String, String>{},
    };
  }

  /// A [RegistrySource] over this fixture's registry root.
  RegistrySource get source => LocalRegistrySource(root);
}

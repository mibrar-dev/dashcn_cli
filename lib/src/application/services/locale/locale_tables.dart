import 'dart:convert';

import 'package:dashcn_cli/src/application/services/registry_source.dart';

/// Registry-relative path of the vendored locale tables.
///
/// The kit publishes `locale_tables.json` next to `registry.json`; the CLI
/// reads it through the same [RegistrySource] it already uses, so locale
/// installs work offline for local checkouts and cached remote registries.
const String kLocaleTablesPath = 'manifests/locale_tables.json';

/// The English base locale: always installed, and the fallback every other
/// locale resolves against.
const String kLocaleBase = 'en';

/// Project-relative directory carrying the generated per-project locale files.
const String kLocalesDirName = 'dashcn_locales';

/// Project state file recording the components and locales the locale sync
/// installed. Same shape as the kit's `tool/locale.dart` state file so the
/// two tools interoperate on one project.
const String kLocaleStateFileName = 'state.json';

/// The registry has no locale support: none of its components record
/// `localizationKeys` (a registry that predates the locale installer).
class LocaleNotSupportedException implements Exception {
  const LocaleNotSupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The registry declares locale keys but ships no `locale_tables.json`.
class LocaleTablesMissingException implements Exception {
  const LocaleTablesMissingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A locale code the registry does not ship.
class UnknownLocaleException implements Exception {
  const UnknownLocaleException(this.code, this.known);

  final String code;
  final List<String> known;

  @override
  String toString() => 'Unknown locale "$code"; known: ${known.join(', ')}.';
}

/// A component id the registry manifest does not contain.
class UnknownLocaleComponentException implements Exception {
  const UnknownLocaleComponentException(this.id, this.known);

  final String id;
  final List<String> known;

  @override
  String toString() => 'Unknown component "$id"; known: ${known.join(', ')}.';
}

/// The vendored locale tables (`manifests/locale_tables.json`).
///
/// `keys` maps a locale key to its Dart signature and English expression;
/// `locales` maps a code to its text direction, optional parent (`inherits`)
/// and the override expressions it translates.
class LocaleTables {
  const LocaleTables({
    required this.keys,
    required this.locales,
    required this.keyCount,
  });

  /// key -> {'signature': ..., 'en': ...}.
  final Map<String, Map<String, String>> keys;

  /// code -> {'direction': ..., 'inherits': ...?, 'overrides': {...}}.
  final Map<String, Map<String, dynamic>> locales;

  final int keyCount;

  factory LocaleTables.fromJson(Map<String, dynamic> json) {
    final keys = <String, Map<String, String>>{};
    final rawKeys = (json['keys'] as Map?) ?? const {};
    rawKeys.forEach((key, value) {
      final entry = (value as Map?) ?? const {};
      keys[key.toString()] = {
        'signature': entry['signature']?.toString() ?? '',
        'en': entry['en']?.toString() ?? "''",
      };
    });
    final locales = <String, Map<String, dynamic>>{};
    final rawLocales = (json['locales'] as Map?) ?? const {};
    rawLocales.forEach((code, value) {
      final entry = (value as Map?) ?? const {};
      locales[code.toString()] = {
        'direction': entry['direction']?.toString() ?? 'ltr',
        if (entry['inherits'] != null) 'inherits': entry['inherits'].toString(),
        'overrides': ((entry['overrides'] as Map?) ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? "''"),
        ),
      };
    });
    final keyCount =
        json['keyCount'] is int ? json['keyCount'] as int : keys.length;
    return LocaleTables(keys: keys, locales: locales, keyCount: keyCount);
  }

  /// Every locale code the registry ships, sorted, without the English base.
  List<String> get supportedCodes => locales.keys.toList()..sort();

  /// Whether [code] is the base or a shipped locale.
  bool knows(String code) => code == kLocaleBase || locales.containsKey(code);

  void checkCode(String code) {
    if (!knows(code)) {
      throw UnknownLocaleException(code, supportedCodes);
    }
  }

  /// The full key -> expression table for [code]: English defaults with the
  /// locale's inherited tables applied on top. The base is the English table
  /// itself.
  Map<String, String> resolveTable(String code) {
    checkCode(code);
    final table = <String, String>{
      for (final entry in keys.entries) entry.key: entry.value['en']!,
    };
    if (code == kLocaleBase) {
      return table;
    }
    void apply(String current) {
      final locale = locales[current]!;
      final parent = locale['inherits'] as String?;
      if (parent != null) {
        if (!locales.containsKey(parent)) {
          throw StateError(
            'locale_tables.json: "$current" inherits unknown "$parent".',
          );
        }
        apply(parent);
      }
      final overrides = locale['overrides'] as Map<String, String>;
      for (final entry in overrides.entries) {
        table[entry.key] = entry.value;
      }
    }

    apply(code);
    return table;
  }
}

/// Loads the locale tables through [source].
///
/// Throws [LocaleTablesMissingException] when the registry has no tables file
/// (a registry whose manifest predates the locale installer, or a partial
/// mirror).
Future<LocaleTables> loadLocaleTables(RegistrySource source) async {
  final text = await source.readString(kLocaleTablesPath);
  if (text == null) {
    throw LocaleTablesMissingException(
      'Registry has no $kLocaleTablesPath: '
      '${source.describe(kLocaleTablesPath)}.',
    );
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw LocaleTablesMissingException(
      '${source.describe(kLocaleTablesPath)} must contain a JSON object.',
    );
  }
  return LocaleTables.fromJson(decoded);
}

/// `ComponentLocalizations` subclass per locale, mirroring the kit's
/// `tool/locale.dart` naming so generated projects match the kit layout.
const Map<String, String> kLocaleClassNames = <String, String>{
  'en': 'DashcnLocaleEn',
  'ar': 'DashcnLocaleAr',
  'he': 'DashcnLocaleHe',
  'fa': 'DashcnLocaleFa',
  'ur': 'DashcnLocaleUr',
  'de': 'DashcnLocaleDe',
  'fr': 'DashcnLocaleFr',
  'es': 'DashcnLocaleEs',
  'it': 'DashcnLocaleIt',
  'pt': 'DashcnLocalePt',
  'pt-BR': 'DashcnLocalePtBr',
  'nl': 'DashcnLocaleNl',
  'ru': 'DashcnLocaleRu',
  'tr': 'DashcnLocaleTr',
  'ja': 'DashcnLocaleJa',
  'ko': 'DashcnLocaleKo',
  'zh': 'DashcnLocaleZh',
  'zh-Hans': 'DashcnLocaleZhHans',
  'hi': 'DashcnLocaleHi',
};

/// File suffix for [code]: `pt-BR` -> `pt_br`.
String localeFileSuffix(String code) => code.replaceAll('-', '_').toLowerCase();

/// Generated file name for [code] inside [kLocalesDirName].
String localeFileName(String code) =>
    'dashcn_locale_${localeFileSuffix(code)}.dart';

/// `Locale(...)` constructor expression for [code].
String localeConstructor(String code) {
  final parts = code.split('-');
  if (parts.length == 2 &&
      parts[1].length == 2 &&
      parts[1] == parts[1].toUpperCase()) {
    return "const Locale('${parts[0]}', '${parts[1]}')";
  }
  if (code == 'zh-Hans') {
    return "const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')";
  }
  return "const Locale('$code')";
}

import 'dart:convert';

import 'package:dashcn_cli/src/theme_interop/interop.dart';

/// The detected shape of an imported web-theme source.
enum WebImportFormat {
  /// `:root` + `.dark` CSS (v3 triplets, v4/modern, Tailwind v4 `@theme`).
  css('CSS'),

  /// A Tailwind v3 config (`theme.extend.colors` object literal).
  tailwindV3('Tailwind v3 config'),

  /// A schema-v2 preset document.
  presetJson('preset JSON');

  const WebImportFormat(this.label);

  /// Human readable format name for the import report.
  final String label;
}

/// One parsed import: the theme to store/apply plus its report.
final class WebImportResult {
  /// Creates the result.
  const WebImportResult({
    required this.theme,
    required this.report,
    required this.format,
  });

  /// The imported theme (fallbacks already filled).
  final WebTheme theme;

  /// What the import mapped, defaulted and ignored — never silent.
  final ImportReport report;

  /// The detected source shape.
  final WebImportFormat format;
}

/// Parses a pasted or downloaded web-theme [source].
///
/// Throws [FormatException] on empty input; CSS-shaped garbage degrades into
/// report entries instead of throwing.
WebImportResult parseWebThemeSource(String source) {
  final String trimmed = source.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('No theme source to import');
  }
  if (_isPresetJson(trimmed)) {
    final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
    final WebTheme theme = webThemeFromPresetJson(
      decoded.map(
        (String key, dynamic value) =>
            MapEntry<String, Object?>(key, value as Object?),
      ),
    );
    return WebImportResult(
      theme: theme,
      report: _presetReport(theme),
      format: WebImportFormat.presetJson,
    );
  }
  if (_looksLikeTailwindV3(trimmed)) {
    final TailwindV3Result parsed = parseTailwindV3Theme(source);
    return WebImportResult(
      theme: parsed.theme,
      report: parsed.report,
      format: WebImportFormat.tailwindV3,
    );
  }
  final CssThemeResult parsed = parseCssTheme(source);
  return WebImportResult(
    theme: parsed.theme,
    report: parsed.report,
    format: WebImportFormat.css,
  );
}

/// Whether [trimmed] is a schema-v2 preset document.
bool _isPresetJson(String trimmed) {
  if (!trimmed.startsWith('{')) {
    return false;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return false;
  }
  return decoded is Map &&
      decoded['schemaVersion'] == 2 &&
      decoded['light'] is Map &&
      decoded['dark'] is Map;
}

/// Whether [source] reads as a Tailwind v3 config rather than CSS.
bool _looksLikeTailwindV3(String source) =>
    source.contains('module.exports') ||
    source.contains('tailwind.config') ||
    (source.contains('extend') && source.contains('colors')) ||
    (source.contains('colors') && source.contains('DEFAULT')) ||
    (source.contains('colors:') && source.contains('{'));

/// Printable lines for [report]: counts first, then fills and skips.
List<String> formatImportReport(ImportReport report) {
  final List<String> lines = <String>[
    'mapped ${report.mapped.length} · '
        'defaulted ${report.defaulted.length} · '
        'ignored ${report.ignored.length}',
  ];
  for (final DefaultedEntry entry in report.defaulted) {
    lines.add('  defaulted ${entry.token} (${entry.reason})');
  }
  for (final IgnoredEntry entry in report.ignored) {
    lines.add('  ignored ${entry.variable} (${entry.reason})');
  }
  return lines;
}

/// The export formats of `dashcn theme export --format`.
enum WebExportFormat {
  /// `:root` + `.dark` CSS.
  css('css'),

  /// Tailwind v4 CSS with an `@theme inline` alias block.
  tailwind('tailwind'),

  /// W3C DTCG `.tokens.json` (one token set per mode).
  dtcg('dtcg'),

  /// The canonical schema-v2 preset document.
  json('json'),

  /// The generated `app_theme.dart`.
  dart('dart');

  const WebExportFormat(this.name);

  /// The `--format` flag value.
  final String name;

  /// Parses a `--format` value, or null when unknown.
  static WebExportFormat? parse(String value) {
    for (final WebExportFormat format in WebExportFormat.values) {
      if (format.name == value.trim().toLowerCase()) {
        return format;
      }
    }
    return null;
  }
}

/// A report for a preset-JSON import: every token came from the source.
ImportReport _presetReport(WebTheme theme) {
  final ImportReport report = ImportReport();
  for (final String token in theme.light.keys) {
    report.mapped.add(MappedEntry('preset.light.$token', 'light.$token'));
  }
  for (final String token in theme.dark.keys) {
    report.mapped.add(MappedEntry('preset.dark.$token', 'dark.$token'));
  }
  return report;
}

/// Sanitizes a `--name` value into a preset id (`lowercase-with-dashes`).
String sanitizePresetId(String name) {
  final String slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) {
    throw const FormatException(
      'Could not derive a preset id from --name; use --name <id>',
    );
  }
  return slug;
}

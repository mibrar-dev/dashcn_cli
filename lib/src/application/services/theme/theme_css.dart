import 'dart:io';

import 'package:dashcn_cli/src/infrastructure/registry/theme_index_loader.dart';
import 'package:dashcn_cli/src/infrastructure/registry/theme_preset_loader.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/registry/shared/theme/preset_theme_data.dart';

Future<List<RegistryThemePresetData>> loadThemePresets({
  ThemeIndexLoader? themeIndexLoader,
  ThemePresetLoader? themePresetLoader,
  CliLogger? logger,
}) async {
  if (themeIndexLoader != null && themePresetLoader != null) {
    try {
      final rawIndex = await themeIndexLoader.load();
      final entries = themeIndexLoader.entriesFrom(rawIndex);
      if (entries.isNotEmpty) {
        final presets = <RegistryThemePresetData>[];
        for (final entry in entries) {
          try {
            final preset = await themePresetLoader.loadPreset(entry);
            presets.add(preset);
          } catch (e) {
            logger?.warn(
              'Skipping theme "${entry.id}" due to load error: $e',
            );
          }
        }
        if (presets.isNotEmpty) {
          return presets;
        }
      }
    } catch (e) {
      logger?.warn('Falling back to embedded theme presets: $e');
    }
  }
  return registryThemePresetsData;
}

Future<void> applyPresetToColorScheme({
  required String filePath,
  required RegistryThemePresetData preset,
}) async {
  final file = File(filePath);
  final content = await file.readAsString();
  final lightBlock = _findBlock(content, 'lightDefaultColor');
  final darkBlock = _findBlock(content, 'darkDefaultColor');

  final updatedLight = _updateBlock(lightBlock.block, preset.light);
  final updatedDark = _updateBlock(darkBlock.block, preset.dark);

  var updated = content;
  if (lightBlock.start < darkBlock.start) {
    updated = updated.replaceRange(
      darkBlock.start,
      darkBlock.end,
      updatedDark,
    );
    updated = updated.replaceRange(
      lightBlock.start,
      lightBlock.end,
      updatedLight,
    );
  } else {
    updated = updated.replaceRange(
      lightBlock.start,
      lightBlock.end,
      updatedLight,
    );
    updated = updated.replaceRange(
      darkBlock.start,
      darkBlock.end,
      updatedDark,
    );
  }
  await file.writeAsString(updated);
}

String _updateBlock(String block, Map<String, String> values) {
  var updated = block;
  for (final entry in values.entries) {
    final key = entry.key;
    final normalized = _normalizeHex(entry.value);
    final pattern = RegExp(
      '(\\b$key:\\s*Color\\()(?:0x)?([0-9A-Fa-f]{8})(\\))',
    );
    updated = updated.replaceAllMapped(pattern, (match) {
      return '${match.group(1)}0x$normalized${match.group(3)}';
    });
  }
  return updated;
}

String _normalizeHex(String value) {
  var hex = value.replaceAll('#', '');
  if (hex.length == 6) {
    hex = 'FF$hex';
  }
  return hex.toUpperCase();
}

_SchemeBlock _findBlock(String content, String name) {
  final token = 'static const ColorScheme $name = ColorScheme(';
  final start = content.indexOf(token);
  if (start == -1) {
    throw FormatException('Missing ColorScheme $name in theme file.');
  }
  final openIndex = content.indexOf('(', start);
  var depth = 0;
  int? closeIndex;
  for (var i = openIndex; i < content.length; i++) {
    final char = content[i];
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) {
        closeIndex = i;
        break;
      }
    }
  }
  if (closeIndex == null) {
    throw FormatException('Malformed ColorScheme $name block.');
  }
  final semicolonIndex = content.indexOf(';', closeIndex);
  if (semicolonIndex == -1) {
    throw FormatException('Missing semicolon in ColorScheme $name block.');
  }

  final block = content.substring(start, semicolonIndex + 1);
  return _SchemeBlock(start, semicolonIndex + 1, block);
}

class _SchemeBlock {
  final int start;
  final int end;
  final String block;

  const _SchemeBlock(this.start, this.end, this.block);
}

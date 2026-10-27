/// Font packs declared by the registry manifest's top-level `fonts` map.
///
/// The kit generator writes one entry per installable font pack
/// (`geist-sans`, `geist-mono`, `noto-symbols`); each entry lists the font
/// families it provides and, per family, the font files with their weight and
/// optional style. Paths are registry-relative (e.g.
/// `assets/fonts/Geist-Regular.otf`), so `dashcn fonts add` reads them through
/// the shared [RegistrySource] bytes path. Absent in a manifest written before
/// the fonts map existed; the CLI treats that as "no fonts".
class RegistryFontFile {
  final String path;
  final int weight;
  final String? style;

  const RegistryFontFile({
    required this.path,
    required this.weight,
    this.style,
  });

  factory RegistryFontFile.fromJson(Map<String, dynamic> json) {
    return RegistryFontFile(
      path: json['path'] as String? ?? '',
      weight: json['weight'] is int ? json['weight'] as int : 0,
      style: json['style'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'weight': weight,
        if (style != null && style!.isNotEmpty) 'style': style,
      };
}

/// One font family inside a pack (e.g. `GeistSans`).
class RegistryFontFamily {
  final String family;
  final List<RegistryFontFile> files;

  const RegistryFontFamily({
    required this.family,
    required this.files,
  });

  factory RegistryFontFamily.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return RegistryFontFamily(
      family: json['family'] as String? ?? '',
      files: rawFiles is List
          ? [
              for (final entry in rawFiles)
                if (entry is Map)
                  RegistryFontFile.fromJson(
                    entry.map((key, value) => MapEntry(key.toString(), value)),
                  ),
            ]
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'family': family,
        'files': [for (final file in files) file.toJson()],
      };
}

/// One entry of the manifest's `fonts` map: the installable pack.
class RegistryFontPack {
  final List<RegistryFontFamily> families;

  const RegistryFontPack({required this.families});

  factory RegistryFontPack.fromJson(Map<String, dynamic> json) {
    final raw = json['families'];
    return RegistryFontPack(
      families: raw is List
          ? [
              for (final entry in raw)
                if (entry is Map)
                  RegistryFontFamily.fromJson(
                    entry.map((key, value) => MapEntry(key.toString(), value)),
                  ),
            ]
          : const [],
    );
  }

  /// Every family name the pack provides, sorted.
  List<String> get familyNames =>
      [for (final family in families) family.family]..sort();

  Map<String, dynamic> toJson() => {
        'families': [for (final family in families) family.toJson()],
      };
}

import 'package:dashcn_cli/src/infrastructure/registry_directory/registry_directory_entry.dart';

class RegistryDirectory {
  final int schemaVersion;
  final List<RegistryDirectoryEntry> registries;
  final Map<String, dynamic> raw;

  const RegistryDirectory({
    required this.schemaVersion,
    required this.registries,
    required this.raw,
  });

  factory RegistryDirectory.fromJson(Map<String, dynamic> json) {
    final items = (json['registries'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (entry) => RegistryDirectoryEntry.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
    return RegistryDirectory(
      schemaVersion: json['schemaVersion'] as int? ?? 0,
      registries: items,
      raw: json,
    );
  }
}

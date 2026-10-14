import 'dart:convert';

/// One `routes` entry of a starter definition.
class StarterRoute {
  const StarterRoute({
    required this.path,
    required this.title,
    required this.kind,
    required this.ref,
  });

  factory StarterRoute.fromJson(Map<String, dynamic> json) {
    return StarterRoute(
      path: json['path'] as String? ?? '',
      title: json['title'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      ref: json['ref'] as String? ?? '',
    );
  }

  final String path;
  final String title;
  final String kind;
  final String ref;
}

/// One `files` entry: registry template plus app target.
class StarterFile {
  const StarterFile({required this.template, required this.target});

  factory StarterFile.fromJson(Map<String, dynamic> json) {
    return StarterFile(
      template: json['template'] as String? ?? '',
      target: json['target'] as String? ?? '',
    );
  }

  final String template;
  final String target;
}

/// A starter definition from `starters/<id>/starter.json` (P9-6).
///
/// Starters are data, not Dart API: the kit never exports them, and the CLI
/// reads them through the registry source (local path or remote) plus the
/// `starters` map in `manifests/registry.json`.
class StarterDefinition {
  const StarterDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.themePreset,
    required this.platforms,
    required this.flows,
    required this.blocks,
    required this.components,
    required this.routes,
    required this.files,
    required this.tags,
    required this.install,
  });

  factory StarterDefinition.fromJson(String id, Map<String, dynamic> json) {
    return StarterDefinition(
      id: id,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      themePreset: json['themePreset'] as String? ?? '',
      platforms: (json['platforms'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      flows: (json['flows'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      blocks: (json['blocks'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      components: (json['components'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      routes: (json['routes'] as List?)
              ?.whereType<Map>()
              .map(
                (entry) => StarterRoute.fromJson(
                  entry.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList() ??
          const <StarterRoute>[],
      files: (json['files'] as List?)
              ?.whereType<Map>()
              .map(
                (entry) => StarterFile.fromJson(
                  entry.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList() ??
          const <StarterFile>[],
      tags: (json['tags'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      install: json['install'] as String? ?? '',
    );
  }

  /// Parses `starter.json` text; throws [FormatException] on bad JSON.
  factory StarterDefinition.parse(String id, String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('starter.json must contain an object');
    }
    return StarterDefinition.fromJson(
      id,
      decoded.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  final String id;
  final String name;
  final String description;
  final String themePreset;
  final List<String> platforms;
  final List<String> flows;
  final List<String> blocks;
  final List<String> components;
  final List<StarterRoute> routes;
  final List<StarterFile> files;
  final List<String> tags;
  final String install;
}

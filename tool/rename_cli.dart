/// P8-3 analyzer-based codemod: renames every `shadcn` identifier, string,
/// comment and file name in dashcn-cli per [tool/rename_map_cli.yaml].
///
/// Dart files are rewritten through the analyzer AST ([parseString],
/// unresolved): declarations and references via [SimpleIdentifier] nodes,
/// generated-code prose via [SimpleStringLiteral]/[InterpolationString]
/// nodes, and prose via comment tokens. Nothing is matched with a regex
/// over file text. Non-Dart text files use the ordered `strings` table.
///
/// Usage: `dart run tool/rename_cli.dart [--check]`
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _mapPath = 'tool/rename_map_cli.yaml';

/// Substrings that must never be rewritten (real repos, rename pending).
const _protected = [
  'mibrar-dev/shadcn_flutter_kit',
  'mibrar-dev/flutter_shadcn_cli',
  "repoName = 'shadcn_flutter_kit'",
  // README: the third-party theme formats `dashcn theme import` accepts.
  'shadcn/tweakcn CSS',
];

/// Files the codemod never touches.
const _skippedPaths = {
  'pubspec.yaml',
  'pubspec.lock',
  'tool/rename_cli.dart',
  'tool/rename_map_cli.yaml',
  'test/fixtures/old_config.json',
  'test/fixtures/old_state.json',
};

const _skippedDirs = {
  '.git',
  '.dart_tool',
  'build',
  '.pub-cache',
  'qa_reports',
};

const _textExtensions = {
  '.dart',
  '.md',
  '.json',
  '.yaml',
  '.yml',
  '.sh',
  '.txt',
  '.gitignore',
  '.pubignore',
};

class _Edit {
  const _Edit(this.offset, this.length, this.replacement);
  final int offset;
  final int length;
  final String replacement;
}

String _renameIdentifier(String name, Map<String, String> exact) {
  final hit = exact[name];
  if (hit != null) return hit;
  if (!name.contains('Shadcn') &&
      !name.contains('SHADCN') &&
      !name.contains('shadcn')) {
    return name;
  }
  return name
      .replaceAll('Shadcn', 'Dashcn')
      .replaceAll('SHADCN', 'DASHCN')
      .replaceAll('shadcn', 'dashcn');
}

List<(int, int)> _protectedSpans(String content) {
  final spans = <(int, int)>[];
  for (final needle in _protected) {
    var from = 0;
    while (true) {
      final at = content.indexOf(needle, from);
      if (at < 0) break;
      spans.add((at, at + needle.length));
      from = at + needle.length;
    }
  }
  return spans;
}

bool _intersects(List<(int, int)> spans, int start, int end) =>
    spans.any((s) => start < s.$2 && end > s.$1);

/// Single left-to-right pass over [start]..[end]: at each position the first
/// matching rule (YAML order, longest `from` first) wins; matches touching a
/// protected span are left alone. Returns null when nothing changes.
String? _rewriteSlice(
  String content,
  int start,
  int end,
  List<(String, String)> rules,
  List<(int, int)> protected,
) {
  final buf = StringBuffer();
  var changed = false;
  var i = start;
  while (i < end) {
    (String, String)? hit;
    if (!_intersects(protected, i, i + 1)) {
      for (final rule in rules) {
        if (rule.$1.isNotEmpty && content.startsWith(rule.$1, i)) {
          hit = rule;
          break;
        }
      }
    }
    if (hit == null) {
      buf.write(content[i]);
      i++;
      continue;
    }
    if (_intersects(protected, i, i + hit.$1.length)) {
      buf.write(content[i]);
      i++;
      continue;
    }
    buf.write(hit.$2);
    i += hit.$1.length;
    changed = true;
  }
  return changed ? buf.toString() : null;
}

class _RenameVisitor extends GeneralizingAstVisitor<void> {
  _RenameVisitor({
    required this.content,
    required this.exact,
    required this.rules,
    required this.protected,
    required this.edits,
  });

  final String content;
  final Map<String, String> exact;
  final List<(String, String)> rules;
  final List<(int, int)> protected;
  final List<_Edit> edits;

  /// Analyzer 14 ships the fragments AST: declarations and type references
  /// carry their names as plain IDENTIFIER tokens (there is no stable
  /// SimpleIdentifier node to override), so every node's direct child
  /// tokens are scanned. String content lives in STRING tokens and is
  /// handled by the literal passes below, never here.
  @override
  void visitNode(AstNode node) {
    for (final entity in node.childEntities) {
      if (entity is! Token) continue;
      if (entity.type != TokenType.IDENTIFIER) continue;
      final next = _renameIdentifier(entity.lexeme, exact);
      if (next != entity.lexeme) {
        edits.add(_Edit(entity.offset, entity.length, next));
      }
    }
    super.visitNode(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final lexeme = node.literal.lexeme;
    var rest = lexeme;
    var prefix = 0;
    if (rest.startsWith('r') || rest.startsWith('R')) {
      prefix = 1;
      rest = rest.substring(1);
    }
    final quote = rest.startsWith("'''") || rest.startsWith('"""') ? 3 : 1;
    final innerStart = node.offset + prefix + quote;
    final innerEnd = node.offset + node.length - quote;
    final inner = innerEnd <= innerStart
        ? null
        : _rewriteSlice(content, innerStart, innerEnd, rules, protected);
    if (inner != null) {
      edits.add(_Edit(innerStart, innerEnd - innerStart, inner));
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitInterpolationString(InterpolationString node) {
    final next = _rewriteSlice(
      content,
      node.offset,
      node.offset + node.length,
      rules,
      protected,
    );
    if (next != null) {
      edits.add(_Edit(node.offset, node.length, next));
    }
    super.visitInterpolationString(node);
  }
}

String _applyEdits(String content, List<_Edit> edits) {
  final seen = <String>{};
  final unique = <_Edit>[];
  for (final edit in edits) {
    final key = '${edit.offset}:${edit.length}';
    if (seen.add(key)) unique.add(edit);
  }
  final sorted = [...unique]..sort((a, b) => b.offset.compareTo(a.offset));
  var result = content;
  for (final edit in sorted) {
    result = result.replaceRange(
      edit.offset,
      edit.offset + edit.length,
      edit.replacement,
    );
  }
  return result;
}

String _rewriteDart(
  String content,
  Map<String, String> exact,
  List<(String, String)> rules,
) {
  final parsed = parseString(content: content, throwIfDiagnostics: false);
  final protected = _protectedSpans(content);
  final edits = <_Edit>[];
  parsed.unit.accept(_RenameVisitor(
    content: content,
    exact: exact,
    rules: rules,
    protected: protected,
    edits: edits,
  ));
  dynamic token = parsed.unit.beginToken;
  while (!(token.isEof as bool)) {
    dynamic comment = token.precedingComments;
    while (comment != null) {
      final start = comment.offset as int;
      final end = start + (comment.length as int);
      final next = _rewriteSlice(content, start, end, rules, protected);
      if (next != null) {
        edits.add(_Edit(start, end - start, next));
      }
      comment = comment.next;
    }
    token = token.next;
  }
  return _applyEdits(content, edits);
}

String _rewriteText(String content, List<(String, String)> rules) {
  final protected = _protectedSpans(content);
  final next = _rewriteSlice(content, 0, content.length, rules, protected);
  return next ?? content;
}

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final root = Directory.current.path;
  final mapFile = File(p.join(root, _mapPath));
  final map = loadYaml(mapFile.readAsStringSync()) as YamlMap;

  final exact = <String, String>{
    for (final entry in (map['identifiers'] as YamlList))
      (entry as YamlMap)['from'].toString(): entry['to'].toString(),
  };
  final rules = <(String, String)>[
    for (final entry in (map['strings'] as YamlList))
      ((entry as YamlMap)['from'].toString(), entry['to'].toString()),
  ];
  final paths = <(String, String)>[
    for (final entry in (map['paths'] as YamlList))
      ((entry as YamlMap)['from'].toString(), entry['to'].toString()),
  ];
  final checkExceptions = <String>{
    for (final entry in ((map['check_exceptions'] as YamlList?) ?? YamlList()))
      entry.toString(),
  };

  var changed = 0;
  final dartFiles = <String>[];
  final textFiles = <String>[];
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: root);
    final segments = p.split(rel);
    if (segments.any(_skippedDirs.contains)) continue;
    if (_skippedPaths.contains(rel)) continue;
    if (segments.last.startsWith('.') && p.extension(rel).isEmpty) {
      continue;
    }
    final ext = p.extension(rel);
    if (ext == '.dart') {
      dartFiles.add(entity.path);
    } else if (_textExtensions.contains(ext)) {
      textFiles.add(entity.path);
    }
  }

  for (final path in [...dartFiles, ...textFiles]) {
    final file = File(path);
    final rel = p.relative(path, from: root);
    final before = file.readAsStringSync();
    final after = path.endsWith('.dart')
        ? _rewriteDart(before, exact, rules)
        : _rewriteText(before, rules);
    if (after != before) {
      if (check && checkExceptions.contains(rel)) continue;
      changed++;
      if (check) {
        stdout.writeln('stale: $rel');
      } else {
        file.writeAsStringSync(after);
      }
    }
  }

  if (!check) {
    for (final move in paths) {
      final from = File(p.join(root, move.$1));
      final to = File(p.join(root, move.$2));
      if (await to.exists()) continue;
      if (await from.exists()) {
        await from.rename(to.path);
        stdout.writeln('moved: ${move.$1} -> ${move.$2}');
      }
    }
  }

  stdout.writeln(check
      ? (changed == 0 ? 'rename map is clean.' : '$changed stale file(s).')
      : 'rewrote $changed file(s).');
  if (check && changed != 0) exitCode = 1;
}

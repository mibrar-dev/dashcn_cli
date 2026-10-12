/// Rewrites an ejected component's package imports to owned relative imports.
///
/// After `dashcn eject <id>` copies sources into the install dir, app files
/// still import `package:dashcn/components/<id>.dart`. This rewriter retargets
/// those imports at the owned file, and handles the barrel case: a file that
/// used the component through `package:dashcn/dashcn.dart` keeps the barrel
/// import (with a `hide` for the now-owned symbols) and gains an explicit
/// owned import. Everything is located through the analyzer AST
/// ([parseString], unresolved): import directives as nodes, symbol references
/// as identifier tokens, never regex over file text.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// The published barrel library.
const String kDashcnBarrelUri = 'package:dashcn/dashcn.dart';

/// Package import prefix for one component's public library.
String packageImportPrefix(String id) => 'package:dashcn/components/$id';

class _DirectiveInfo {
  _DirectiveInfo({
    required this.node,
    required this.uri,
    required this.uriInnerStart,
    required this.uriInnerEnd,
  });

  final ImportDirective node;
  final String uri;
  final int uriInnerStart;
  final int uriInnerEnd;
}

class _ImportCollector extends GeneralizingAstVisitor<void> {
  _ImportCollector(this.content);

  final String content;
  final List<_DirectiveInfo> directives = [];

  @override
  void visitNode(AstNode node) {
    if (node is ImportDirective) {
      final uri = node.uri.stringValue;
      if (uri != null) {
        final inner = _innerSpan(content, node.uri.offset, node.uri.length);
        directives.add(_DirectiveInfo(
          node: node,
          uri: uri,
          uriInnerStart: inner.$1,
          uriInnerEnd: inner.$2,
        ));
      }
    }
    super.visitNode(node);
  }
}

/// Inner span (exclusive of quotes/raw prefix) of a string literal.
(int, int) _innerSpan(String content, int offset, int length) {
  var start = offset;
  if (content.startsWith('r', start) || content.startsWith('R', start)) {
    start++;
  }
  var quote = 1;
  if (content.startsWith("'''", start) || content.startsWith('"""', start)) {
    quote = 3;
  }
  return (start + quote, offset + length - quote);
}

class _Edit {
  const _Edit(this.offset, this.length, this.replacement);
  final int offset;
  final int length;
  final String replacement;
}

/// Rewrites package imports of component [id] across the app's Dart files.
///
/// [ownedEntry] is the project-relative owned entry file, e.g.
/// `lib/ui/dashcn/components/button/button.dart`. Returns per-file change
/// descriptions; files are written unless [dryRun] is true.
class ImportRewriter {
  const ImportRewriter._();

  static const _scanRoots = ['lib', 'bin', 'test'];

  static Future<Map<String, List<String>>> rewrite({
    required String projectRoot,
    required String id,
    required Set<String> apiSymbols,
    required String ownedEntry,
    bool dryRun = false,
  }) async {
    final changes = <String, List<String>>{};
    if (apiSymbols.isEmpty) {
      return changes;
    }
    for (final root in _scanRoots) {
      final dir = Directory(p.join(projectRoot, root));
      if (!dir.existsSync()) continue;
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !_isSkipped(file.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final notes = _rewriteFile(
          file: file,
          projectRoot: projectRoot,
          id: id,
          apiSymbols: apiSymbols,
          ownedEntry: ownedEntry,
          dryRun: dryRun,
        );
        if (notes.isNotEmpty) {
          changes[p.relative(file.path, from: projectRoot)] = notes;
        }
      }
    }
    return changes;
  }

  static bool _isSkipped(String path) {
    return p
        .split(p.normalize(path))
        .any((segment) => segment.startsWith('.') || segment == 'build');
  }

  static List<String> _rewriteFile({
    required File file,
    required String projectRoot,
    required String id,
    required Set<String> apiSymbols,
    required String ownedEntry,
    required bool dryRun,
  }) {
    final content = file.readAsStringSync();
    final parsed = parseString(content: content, throwIfDiagnostics: false);
    final collector = _ImportCollector(content);
    parsed.unit.accept(collector);
    if (collector.directives.isEmpty) {
      return const [];
    }
    final firstToken = parsed.unit.beginToken;
    final ownedRelative = _relativeImport(
      fromDir: p.dirname(file.path),
      projectRoot: projectRoot,
      ownedEntry: ownedEntry,
    );
    final spans = [
      for (final directive in collector.directives)
        (directive.node.offset, directive.node.end),
    ];
    var ownedImportPresent = collector.directives.any(
      (directive) => directive.uri == ownedRelative,
    );
    final notes = <String>[];
    final edits = <_Edit>[];
    final prefix = packageImportPrefix(id);

    for (final directive in collector.directives) {
      final uri = directive.uri;
      if (uri == '$prefix.dart' || uri.startsWith('$prefix/')) {
        final target = uri == '$prefix.dart'
            ? ownedRelative
            : _relativeImport(
                fromDir: p.dirname(file.path),
                projectRoot: projectRoot,
                ownedEntry: _ownedForDeep(id, uri, ownedEntry),
              );
        edits.add(_Edit(
          directive.uriInnerStart,
          directive.uriInnerEnd - directive.uriInnerStart,
          target,
        ));
        notes.add('retargeted $uri to $target');
        if (target == ownedRelative) ownedImportPresent = true;
        continue;
      }
      if (uri != kDashcnBarrelUri) continue;
      final rewrite = _rewriteBarrel(
        directive: directive,
        content: content,
        firstToken: firstToken,
        directiveSpans: spans,
        apiSymbols: apiSymbols,
        ownedRelative: ownedRelative,
        ownedImportPresent: ownedImportPresent,
      );
      if (rewrite == null) continue;
      edits.addAll(rewrite.edits);
      notes.addAll(rewrite.notes);
      if (rewrite.addsOwnedImport) ownedImportPresent = true;
    }

    if (edits.isEmpty) {
      return const [];
    }
    if (!dryRun) {
      file.writeAsStringSync(_applyEdits(content, edits));
    }
    return notes;
  }

  /// Owned install path for a deep `package:dashcn/components/<id>/<rest>`
  /// import: the registry-relative suffix lands under the install dir.
  static String _ownedForDeep(String id, String uri, String ownedEntry) {
    final suffix = uri.substring(packageImportPrefix(id).length + 1);
    return p.join(p.dirname(ownedEntry), suffix);
  }

  static String _relativeImport({
    required String fromDir,
    required String projectRoot,
    required String ownedEntry,
  }) {
    final target = p.normalize(p.join(projectRoot, ownedEntry));
    return p.relative(target, from: fromDir).replaceAll('\\', '/');
  }

  static ({List<_Edit> edits, List<String> notes, bool addsOwnedImport})?
      _rewriteBarrel({
    required _DirectiveInfo directive,
    required String content,
    required Token firstToken,
    required List<(int, int)> directiveSpans,
    required Set<String> apiSymbols,
    required String ownedRelative,
    required bool ownedImportPresent,
  }) {
    final node = directive.node;
    final prefix = node.prefix?.name;
    final used = _usedSymbols(
      firstToken: firstToken,
      directiveSpans: directiveSpans,
      apiSymbols: apiSymbols,
      prefix: prefix,
    );
    if (used.isEmpty) {
      return null;
    }
    final edits = <_Edit>[];
    final notes = <String>[];

    ShowCombinator? showCombinator;
    HideCombinator? hideCombinator;
    for (final combinator in node.combinators) {
      if (combinator is ShowCombinator) showCombinator = combinator;
      if (combinator is HideCombinator) hideCombinator = combinator;
    }
    final hidden = hideCombinator == null
        ? <String>{}
        : {for (final name in hideCombinator.hiddenNames) name.name};
    final visible = used.difference(hidden);
    if (visible.isEmpty) {
      return null;
    }

    var directiveRemoved = false;
    if (showCombinator != null) {
      final remaining = [
        for (final name in showCombinator.shownNames)
          if (!used.contains(name.name)) name.name,
      ];
      if (remaining.isEmpty) {
        edits.add(_Edit(node.offset, node.end - node.offset, ''));
        notes.add('removed barrel import (show list emptied)');
        directiveRemoved = true;
      } else if (remaining.length != showCombinator.shownNames.length) {
        edits.add(_Edit(
          showCombinator.offset,
          showCombinator.end - showCombinator.offset,
          'show ${remaining.join(', ')}',
        ));
        notes.add('narrowed barrel show to ${remaining.join(', ')}');
      } else {
        notes.add('kept barrel show (owned import takes over)');
      }
    } else {
      final hideAll = {...hidden, ...visible}.toList()..sort();
      if (hideCombinator == null) {
        edits.add(_Edit(
          directive.uriInnerEnd + 1,
          0,
          ' hide ${hideAll.join(', ')}',
        ));
        notes.add('added hide ${visible.join(', ')} to barrel import');
      } else {
        edits.add(_Edit(
          hideCombinator.offset,
          hideCombinator.end - hideCombinator.offset,
          'hide ${hideAll.join(', ')}',
        ));
        notes.add('extended barrel hide with ${visible.join(', ')}');
      }
    }

    // Rewrite `prefix.Symbol` uses to bare `Symbol` so the owned import
    // resolves them.
    if (prefix != null) {
      for (final span in _prefixedUses(
          firstToken: firstToken, prefix: prefix, used: used)) {
        edits.add(_Edit(span.$1, span.$2 - span.$1, span.$3));
      }
      notes.add('unprefixed ${used.join(', ')} (was $prefix.)');
    }
    var addsOwnedImport = false;
    if (!ownedImportPresent) {
      final anchorOffset =
          directiveRemoved ? node.offset : _lineEnd(content, node.end);
      edits.add(_Edit(anchorOffset, 0, "import '$ownedRelative';\n"));
      notes.add('added owned import $ownedRelative');
      addsOwnedImport = true;
    }
    return (edits: edits, notes: notes, addsOwnedImport: addsOwnedImport);
  }

  /// Api symbols referenced outside import directives: bare identifiers, plus
  /// `prefix.Symbol` targets when [prefix] is set.
  static Set<String> _usedSymbols({
    required Token firstToken,
    required List<(int, int)> directiveSpans,
    required Set<String> apiSymbols,
    required String? prefix,
  }) {
    final used = <String>{};
    var token = firstToken;
    while (!token.isEof) {
      if (token.type == TokenType.IDENTIFIER &&
          !_inSpans(directiveSpans, token.offset)) {
        final lexeme = token.lexeme;
        if (apiSymbols.contains(lexeme)) {
          used.add(lexeme);
        } else if (prefix != null && lexeme == prefix) {
          final dot = token.next;
          final name = dot?.next;
          if (dot?.type == TokenType.PERIOD &&
              name?.type == TokenType.IDENTIFIER &&
              apiSymbols.contains(name!.lexeme)) {
            used.add(name.lexeme);
          }
        }
      }
      token = token.next!;
    }
    return used;
  }

  static List<(int, int, String)> _prefixedUses({
    required Token firstToken,
    required String prefix,
    required Set<String> used,
  }) {
    final spans = <(int, int, String)>[];
    var token = firstToken;
    while (!token.isEof) {
      if (token.type == TokenType.IDENTIFIER && token.lexeme == prefix) {
        final dot = token.next;
        final name = dot?.next;
        if (dot?.type == TokenType.PERIOD &&
            name?.type == TokenType.IDENTIFIER &&
            used.contains(name!.lexeme)) {
          spans.add((token.offset, name.end, name.lexeme));
        }
      }
      token = token.next!;
    }
    return spans;
  }

  static bool _inSpans(List<(int, int)> spans, int offset) {
    return spans.any((span) => offset >= span.$1 && offset < span.$2);
  }

  static int _lineEnd(String content, int offset) {
    final newline = content.indexOf('\n', offset);
    return newline < 0 ? content.length : newline + 1;
  }

  static String _applyEdits(String content, List<_Edit> edits) {
    final sorted = [...edits]..sort((a, b) => b.offset.compareTo(a.offset));
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
}

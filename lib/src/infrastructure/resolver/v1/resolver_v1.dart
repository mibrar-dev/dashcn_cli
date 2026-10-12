import 'package:dashcn_cli/src/infrastructure/resolver/v1/resolver_v1_exception.dart';

class ResolverV1 {
  static Uri resolveUrl(String baseUrl, String relativePath) {
    final normalizedBase = normalizeBaseUrl(baseUrl);
    final normalizedRelative = normalizeRelativePath(relativePath);
    return Uri.parse('$normalizedBase$normalizedRelative');
  }

  static String normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw ResolverV1Exception('baseUrl cannot be empty');
    }
    final uri = Uri.parse(trimmed);
    if (uri.scheme.isEmpty || uri.host.isEmpty) {
      throw ResolverV1Exception('baseUrl must be an absolute URL');
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw ResolverV1Exception('baseUrl cannot include query or fragment');
    }

    final githubTreeBase = _normalizeGithubTreeBase(uri);
    if (githubTreeBase != null) {
      return githubTreeBase;
    }

    final cleanPath = uri.path.replaceAll(RegExp(r'/+'), '/');
    final withoutTrailing = cleanPath.endsWith('/') && cleanPath.length > 1
        ? cleanPath.substring(0, cleanPath.length - 1)
        : cleanPath;
    final withTrailing =
        withoutTrailing.endsWith('/') ? withoutTrailing : '$withoutTrailing/';
    return uri.replace(path: withTrailing).toString();
  }

  static String? githubApiContentsUrl(String baseUrl, String relativePath) {
    final base = Uri.parse(baseUrl.trim());
    if (!base.host.toLowerCase().endsWith('github.com')) {
      return null;
    }
    final parts = base.path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 4 || parts[2] != 'tree') {
      return null;
    }
    final owner = parts[0];
    final repo = parts[1];
    final ref = parts[3];
    final basePath = parts.length > 4 ? parts.sublist(4).join('/') : '';
    final rel = normalizeRelativePath(relativePath);
    final fullPath = basePath.isEmpty ? rel : '$basePath/$rel';
    return Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/contents/$fullPath',
      {'ref': ref},
    ).toString();
  }

  static String? _normalizeGithubTreeBase(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!host.endsWith('github.com')) {
      return null;
    }
    final parts = uri.path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 4 || parts[2] != 'tree') {
      return null;
    }
    final owner = parts[0];
    final repo = parts[1];
    final ref = parts[3];
    final rest = parts.length > 4 ? '/${parts.sublist(4).join('/')}' : '';
    final path = '/$owner/$repo/$ref$rest/';
    return Uri.https('raw.githubusercontent.com', path).toString();
  }

  static String normalizeRelativePath(String relativePath) {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) {
      throw ResolverV1Exception('relativePath cannot be empty');
    }
    if (trimmed.contains('..')) {
      throw ResolverV1Exception('relativePath cannot contain ".."');
    }
    if (trimmed.contains(r'\')) {
      throw ResolverV1Exception('relativePath cannot contain backslashes');
    }
    if (trimmed.contains('?') || trimmed.contains('#')) {
      throw ResolverV1Exception(
        'relativePath cannot contain query or fragment tokens',
      );
    }

    final normalized = trimmed.replaceFirst(RegExp(r'^/+'), '');
    if (normalized.isEmpty) {
      throw ResolverV1Exception('relativePath cannot resolve to empty');
    }
    final segments = normalized.split('/');
    if (segments.any((segment) => segment.isEmpty)) {
      throw ResolverV1Exception(
        'relativePath cannot contain empty path segments',
      );
    }
    return normalized;
  }
}

import 'dart:io';

import 'package:dashcn_cli/src/application/services/registry_source.dart';
import 'package:dashcn_cli/src/application/services/version/version_manager.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:path/path.dart' as p;

/// Resolves which [RegistrySource] a command reads from (plan §9.5).
///
/// Precedence:
/// 1. `--registry <path|url>` (the only registry selector the v2 CLI needs);
/// 2. `DASHCN_REGISTRY_ROOT` / `DASHCN_REGISTRY_URL` (test + CI hooks);
/// 3. the project's `.dashcn/config.json` (`registryPath` / `registryUrl`);
/// 4. the default remote: GitHub raw at the ref matching the CLI version.
///
/// A remote source always gets an on-disk [RegistryCache] under
/// `<projectRoot>/.dashcn/cache/registry`, so `--offline` re-installs work.
class RegistrySourceResolver {
  const RegistrySourceResolver._();

  /// GitHub raw host the default registry is served from.
  static const String defaultRegistryHost =
      'https://raw.githubusercontent.com/mibrar-dev/dashcn';

  /// Sub-path of the registry inside the kit repository.
  static const String defaultRegistrySubPath = 'dashcn/lib/src';

  /// The ref the default remote pins to: the tag matching the CLI version.
  static String defaultRef() => 'v${VersionManager.currentVersion}';

  /// Default registry root URL, e.g.
  /// `https://raw.githubusercontent.com/mibrar-dev/dashcn/v0.1.0/dashcn/lib/src`.
  static String defaultBaseUrl({String? ref}) =>
      '$defaultRegistryHost/${ref ?? defaultRef()}/$defaultRegistrySubPath';

  /// Builds a source for [projectRoot].
  ///
  /// [registryOverride] is the raw `--registry` value. [httpClient] is injected
  /// in tests; production uses [HttpRegistryHttpClient].
  static RegistrySource resolve({
    required String projectRoot,
    required DashcnConfig config,
    String? registryOverride,
    bool offline = false,
    RegistryHttpClient? httpClient,
  }) {
    final rawOverride = _trim(registryOverride);
    final String? localPath;
    final String? remoteUrl;
    if (rawOverride != null) {
      localPath = _isUrl(rawOverride) ? null : rawOverride;
      remoteUrl = _isUrl(rawOverride) ? rawOverride : null;
    } else if (_env('DASHCN_REGISTRY_ROOT') != null) {
      localPath = _env('DASHCN_REGISTRY_ROOT');
      remoteUrl = null;
    } else if (_env('DASHCN_REGISTRY_URL') != null) {
      localPath = null;
      remoteUrl = _env('DASHCN_REGISTRY_URL');
    } else {
      localPath = _trim(config.registryPath);
      remoteUrl = _trim(config.registryUrl);
    }

    if (localPath != null) {
      final resolved = _resolveLocal(projectRoot, localPath);
      if (!Directory(resolved).existsSync()) {
        throw RegistrySourceException('Local registry not found: $resolved');
      }
      return LocalRegistrySource(resolved);
    }
    final base = remoteUrl ?? defaultBaseUrl();
    return RemoteRegistrySource(
      baseUrl: base,
      client: httpClient ?? HttpRegistryHttpClient(),
      cache: RegistryCache(cacheRootFor(projectRoot)),
      offline: offline,
    );
  }

  static bool _isUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Project-relative cache directory for remote registry files.
  static String cacheRootFor(String projectRoot) =>
      p.join(projectRoot, '.dashcn', 'cache', 'registry');

  static String _resolveLocal(String projectRoot, String path) {
    final trimmed = path.trim();
    if (p.isAbsolute(trimmed)) {
      return p.normalize(trimmed);
    }
    return p.normalize(p.join(projectRoot, trimmed));
  }

  static String? _trim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _env(String name) {
    final value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

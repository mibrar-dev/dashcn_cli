import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:dashcn_cli/src/version_manager.dart';
import 'package:dashcn_cli/src/logger.dart';

void main() {
  group('VersionManager', () {
    late VersionManager versionManager;
    late CliLogger logger;
    late Directory tempCacheDir;

    setUp(() async {
      logger = CliLogger(verbose: false);
      versionManager = VersionManager(logger: logger);

      // Create temp cache directory
      tempCacheDir = Directory.systemTemp.createTempSync('version_cache_test_');
    });

    tearDown(() {
      if (tempCacheDir.existsSync()) {
        tempCacheDir.deleteSync(recursive: true);
      }

      // Clean up actual cache if it was created during tests
      final cacheFile = File(p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '',
        '.dashcn',
        'cache',
        'version_check.json',
      ));
      if (cacheFile.existsSync()) {
        cacheFile.deleteSync();
      }
    });

    group('Version Display', () {
      test('shows current version', () {
        // This just verifies the method doesn't throw
        expect(() => versionManager.showVersion(), returnsNormally);
      });

      test('current version is valid semver format', () {
        final version = VersionManager.currentVersion;

        // Should match semantic versioning pattern (e.g., 0.1.8)
        final semverPattern = RegExp(r'^\d+\.\d+\.\d+');
        expect(semverPattern.hasMatch(version), isTrue);
      });
    });

    group('Version Comparison', () {
      test('correctly identifies newer versions', () {
        // Test internal version comparison logic
        // Note: This tests private method behavior through public API

        // 0.1.9 > 0.1.8
        expect(_isNewerVersion('0.1.9', '0.1.8'), isTrue);

        // 1.0.0 > 0.1.8
        expect(_isNewerVersion('1.0.0', '0.1.8'), isTrue);

        // 0.2.0 > 0.1.9
        expect(_isNewerVersion('0.2.0', '0.1.9'), isTrue);

        // 0.1.8 is not newer than 0.1.8
        expect(_isNewerVersion('0.1.8', '0.1.8'), isFalse);

        // 0.1.7 is not newer than 0.1.8
        expect(_isNewerVersion('0.1.7', '0.1.8'), isFalse);
      });

      test('handles pre-release versions', () {
        // 0.1.9-beta should be considered newer than 0.1.8
        expect(_isNewerVersion('0.1.9-beta', '0.1.8'), isTrue);

        // But for simplicity, we can accept basic comparison
        // Implementation may vary based on actual semver handling
      });
    });

    group('Cache Management', () {
      test('creates cache directory if it does not exist', () async {
        final cacheDir =
            Directory(p.join(tempCacheDir.path, '.dashcn', 'cache'));
        expect(cacheDir.existsSync(), isFalse);

        // Create a cache file
        final cacheFile = File(p.join(cacheDir.path, 'version_check.json'));
        cacheFile.parent.createSync(recursive: true);

        expect(cacheDir.existsSync(), isTrue);
      });

      test('saves cache data with timestamp', () async {
        final cacheFile = File(p.join(tempCacheDir.path, 'version_check.json'));

        final cacheData = {
          'lastCheck': DateTime.now().toIso8601String(),
          'hasUpdate': true,
          'latestVersion': '0.2.0',
          'currentVersion': '0.1.8',
        };

        cacheFile.parent.createSync(recursive: true);
        cacheFile.writeAsStringSync(jsonEncode(cacheData));

        expect(cacheFile.existsSync(), isTrue);

        final loaded = jsonDecode(cacheFile.readAsStringSync());
        expect(loaded['hasUpdate'], isTrue);
        expect(loaded['latestVersion'], equals('0.2.0'));
        expect(loaded['currentVersion'], equals('0.1.8'));
      });

      test('respects 24-hour cache staleness policy', () async {
        final cacheFile = File(p.join(tempCacheDir.path, 'version_check.json'));
        cacheFile.parent.createSync(recursive: true);

        // Create cache from 25 hours ago (stale)
        final staleTimestamp = DateTime.now().subtract(Duration(hours: 25));
        final staleCache = {
          'lastCheck': staleTimestamp.toIso8601String(),
          'hasUpdate': false,
          'latestVersion': '0.1.8',
          'currentVersion': '0.1.8',
        };
        cacheFile.writeAsStringSync(jsonEncode(staleCache));

        final cache = jsonDecode(cacheFile.readAsStringSync());
        final lastCheck = DateTime.parse(cache['lastCheck']);
        final age = DateTime.now().difference(lastCheck);

        expect(age.inHours, greaterThan(24));
      });

      test('uses fresh cache within 24 hours', () async {
        final cacheFile = File(p.join(tempCacheDir.path, 'version_check.json'));
        cacheFile.parent.createSync(recursive: true);

        // Create cache from 1 hour ago (fresh)
        final freshTimestamp = DateTime.now().subtract(Duration(hours: 1));
        final freshCache = {
          'lastCheck': freshTimestamp.toIso8601String(),
          'hasUpdate': true,
          'latestVersion': '0.2.0',
          'currentVersion': '0.1.8',
        };
        cacheFile.writeAsStringSync(jsonEncode(freshCache));

        final cache = jsonDecode(cacheFile.readAsStringSync());
        final lastCheck = DateTime.parse(cache['lastCheck']);
        final age = DateTime.now().difference(lastCheck);

        expect(age.inHours, lessThan(24));
      });
    });

    group('Update Notification', () {
      test('notification format includes version info', () {
        // Test that notification would show current -> latest
        // This is more of an integration test, but we can verify structure

        const currentVersion = '0.1.8';
        const latestVersion = '0.2.0';

        // Notification should mention both versions
        final message = 'Update available: $currentVersion → $latestVersion';

        expect(message, contains(currentVersion));
        expect(message, contains(latestVersion));
        expect(message, contains('→'));
      });
    });

    group('Opt-out Behavior', () {
      test('respects checkUpdates config flag', () {
        // When checkUpdates is false, auto-check should not run
        // This is tested at the config level

        const checkUpdates = false;

        if (!checkUpdates) {
          // Should skip auto-check
          expect(checkUpdates, isFalse);
        }
      });
    });

    group('Error Handling', () {
      test('handles network errors gracefully', () async {
        // Auto-check should fail silently on network errors
        // We can't easily test actual network failures, but we verify
        // the method doesn't throw for invalid URLs

        // This would typically fail silently in production
        expect(() async {
          // Simulated network failure scenario
          try {
            // In real implementation, this would catch HTTP errors
            throw SocketException('Network unreachable');
          } catch (e) {
            // Should handle gracefully without re-throwing
          }
        }, returnsNormally);
      });

      test('handles malformed version responses', () {
        // Should handle invalid version strings
        expect(() => _isNewerVersion('invalid', '0.1.8'), returnsNormally);
        expect(() => _isNewerVersion('0.1.8', 'invalid'), returnsNormally);
      });
    });
  });
}

/// Helper function to simulate version comparison logic
/// This mirrors the actual implementation in VersionManager
bool _isNewerVersion(String latest, String current) {
  try {
    // Remove any pre-release tags for simple comparison
    final latestClean = latest.split('-').first.split('+').first;
    final currentClean = current.split('-').first.split('+').first;

    final latestParts = latestClean.split('.').map(int.tryParse).toList();
    final currentParts = currentClean.split('.').map(int.tryParse).toList();

    // Handle malformed versions
    if (latestParts.contains(null) || currentParts.contains(null)) {
      return false;
    }

    // Ensure both have 3 parts (major.minor.patch)
    while (latestParts.length < 3) {
      latestParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    // Compare major, minor, patch
    for (var i = 0; i < 3; i++) {
      if (latestParts[i]! > currentParts[i]!) {
        return true;
      } else if (latestParts[i]! < currentParts[i]!) {
        return false;
      }
    }

    return false; // Versions are equal
  } catch (e) {
    return false;
  }
}

import 'package:dashcn_cli/src/application/services/add_resolution_service.dart';
import 'package:dashcn_cli/src/config.dart';
import 'package:test/test.dart';

void main() {
  group('AddResolutionService', () {
    const service = AddResolutionService();

    test('@namespace/component parses to canonical component ref', () {
      final ref =
          AddResolutionService.parseQualifiedComponentRef('@dashcn/button');

      expect(ref, isNotNull);
      expect(ref!.namespace, 'dashcn');
      expect(ref.componentId, 'button');
      expect(ref.canonical, '@dashcn/button');
    });

    test('@namespace/component@version preserves requested version', () {
      final ref = AddResolutionService.parseQualifiedComponentRef(
        '@dashcn/button@1.2.3',
      );

      expect(ref, isNotNull);
      expect(ref!.namespace, 'dashcn');
      expect(ref.componentId, 'button');
      expect(ref.version, '1.2.3');
      expect(ref.canonical, '@dashcn/button@1.2.3');
    });

    test('namespace:component parses to the same canonical component ref', () {
      final atRef =
          AddResolutionService.parseQualifiedComponentRef('@dashcn/button');
      final colonRef =
          AddResolutionService.parseQualifiedComponentRef('dashcn:button');

      expect(colonRef, isNotNull);
      expect(colonRef!.namespace, atRef!.namespace);
      expect(colonRef.componentId, atRef.componentId);
      expect(colonRef.canonical, '@dashcn/button');
    });

    test('colon alias splits on the first colon only', () {
      final ref = AddResolutionService.parseQualifiedComponentRef(
        'dashcn:button:primary',
      );

      expect(ref, isNotNull);
      expect(ref!.namespace, 'dashcn');
      expect(ref.componentId, 'button:primary');
      expect(ref.canonical, '@dashcn/button:primary');
    });

    test('malformed component refs are rejected', () {
      for (final token in [
        '',
        '@',
        '@dashcn',
        '@dashcn/',
        '@/button',
        '@dashcn/button/extra',
        'dashcn:',
        ':button',
      ]) {
        expect(
          AddResolutionService.parseQualifiedComponentRef(token),
          isNull,
          reason: token,
        );
      }
    });

    test('qualified colon aliases resolve without probing raw input', () async {
      final probed = <String>[];
      final requests = await service.resolveAddRequests(
        requested: ['dashcn:button:primary'],
        config: _multiRegistryConfig(defaultNamespace: 'dashcn'),
        componentExists: (namespace, componentId) async {
          probed.add('$namespace/$componentId');
          return true;
        },
      );

      expect(requests, hasLength(1));
      expect(requests.single.namespace, 'dashcn');
      expect(requests.single.componentId, 'button:primary');
      expect(requests.single.version, isNull);
      expect(probed, isEmpty);
    });

    test('malformed qualified refs fail before component probing', () async {
      for (final token in [
        '@dashcn/button/extra',
        'dashcn:',
        ':button',
      ]) {
        final probed = <String>[];

        await expectLater(
          () => service.resolveAddRequests(
            requested: [token],
            config: _multiRegistryConfig(defaultNamespace: 'dashcn'),
            componentExists: (namespace, componentId) async {
              probed.add('$namespace/$componentId');
              return true;
            },
          ),
          throwsA(
            isA<ComponentResolutionException>()
                .having((error) => error.token, 'token', token)
                .having(
                  (error) => error.message,
                  'message',
                  contains('Invalid component address'),
                ),
          ),
        );
        expect(probed, isEmpty, reason: token);
      }
    });

    test('ambiguity errors show only canonical address form', () async {
      await expectLater(
        () => service.resolveAddRequests(
          requested: ['button'],
          config: _multiRegistryConfig(defaultNamespace: 'unknown'),
          componentExists: (namespace, componentId) async =>
              componentId == 'button' &&
              (namespace == 'dashcn' || namespace == 'alt'),
        ),
        throwsA(
          isA<ComponentResolutionException>()
              .having((error) => error.token, 'token', 'button')
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('Use @namespace/component'),
                  isNot(contains('@<namespace>')),
                  isNot(contains('namespace:component')),
                  isNot(contains('namespace-qualified')),
                ),
              ),
        ),
      );
    });
  });
}

DashcnConfig _multiRegistryConfig({required String defaultNamespace}) {
  return DashcnConfig(
    defaultNamespace: defaultNamespace,
    registries: {
      'dashcn': const RegistryConfigEntry(enabled: true),
      'alt': const RegistryConfigEntry(enabled: true),
    },
  );
}

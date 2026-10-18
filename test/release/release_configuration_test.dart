import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 8 release configuration', () {
    test(
      'release signing is guarded and internal debug signing is explicit',
      () {
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();

        expect(gradle, contains('releaseSigningReady'));
        expect(gradle, contains('MARIANOBH_KEYSTORE_PATH'));
        expect(gradle, contains('MARIANOBH_ALLOW_DEBUG_RELEASE'));
        expect(gradle, contains('requestedReleaseTask'));
        expect(
          gradle,
          contains(
            'releaseSigningReady -> signingConfigs.getByName("release")',
          ),
        );
        expect(
          gradle,
          contains('allowDebugRelease -> signingConfigs.getByName("debug")'),
        );
        expect(
          gradle,
          isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
        );
      },
    );

    test('private Android signing material is ignored', () {
      final rootIgnore = File('.gitignore').readAsStringSync();
      final androidIgnore = File('android/.gitignore').readAsStringSync();

      expect(androidIgnore, contains('key.properties'));
      expect(androidIgnore, contains('**/*.keystore'));
      expect(androidIgnore, contains('**/*.jks'));
      expect(rootIgnore, contains('/build/'));
      expect(File('android/key.properties.example').existsSync(), isTrue);
    });

    test('Android requests only the network permission used by the app', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final permissions = RegExp('<uses-permission').allMatches(manifest);

      expect(permissions, hasLength(1));
      expect(manifest, contains('android.permission.INTERNET'));
    });

    test('Firestore index configuration stays explicit', () {
      final indexes = jsonDecode(
        File('firestore.indexes.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(indexes['indexes'], isA<List<dynamic>>());
      expect(indexes['fieldOverrides'], isA<List<dynamic>>());
    });

    test('release runbook covers recovery and physical-phone validation', () {
      final runbook = File('docs/PHASE_8_RELEASE.md').readAsStringSync();

      expect(runbook, contains('Restore it to a **new test database**'));
      expect(runbook, contains('without an emulator'));
      expect(runbook, contains('MARIANOBH_ALLOW_DEBUG_RELEASE'));
      expect(runbook, contains('Play Integrity'));
      expect(runbook, contains('375 logical-pixel'));
      expect(runbook, contains('largest practical system text size'));
      expect(runbook, contains('TalkBack'));
    });
  });
}

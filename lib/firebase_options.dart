// Firebase client configuration generated for the MarianoBH Android app.
// These client identifiers are not service-account credentials.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'This Phase 1 project is currently configured for Android only.',
      );
    }
    if (android.apiKey.isEmpty ||
        android.appId.isEmpty ||
        android.messagingSenderId.isEmpty ||
        android.projectId.isEmpty) {
      throw StateError(
        'Firebase is not configured. Run flutterfire configure for Android.',
      );
    }
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCTg6_9NK0K62QKzMdQHsbT182zA27_8R8',
    appId: '1:200568608153:android:261d8e57b9b807db5e6f08',
    messagingSenderId: '200568608153',
    projectId: 'marianobh-fcc1b',
    storageBucket: 'marianobh-fcc1b.firebasestorage.app',
  );
}

// Firebase configuration for Vinex Technology app
// Project: vinex-storage85  |  Project Number: 544250708114
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return web;
      case TargetPlatform.macOS:
        return web;
      default:
        return web;
    }
  }

  // ── Web ───────────────────────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'AIzaSyCfQ9n3BZv0mniiWyZ9ELhAs7OqJB0a6UE',
    appId:             '1:544250708114:web:b709b505bb8b0a4ab8e64b',
    messagingSenderId: '544250708114',
    projectId:         'vinex-storage85',
    storageBucket:     'vinex-storage85.firebasestorage.app',
    authDomain:        'vinex-storage85.firebaseapp.com',
    databaseURL:       'https://vinex-storage85-default-rtdb.firebaseio.com',
  );

  // ── Android ───────────────────────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyCfQ9n3BZv0mniiWyZ9ELhAs7OqJB0a6UE',
    appId:             '1:544250708114:android:b709b505bb8b0a4ab8e64b',
    messagingSenderId: '544250708114',
    projectId:         'vinex-storage85',
    storageBucket:     'vinex-storage85.firebasestorage.app',
  );
}

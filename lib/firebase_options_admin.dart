// Firebase options untuk BUILD ADMIN (appId com.chatyuk.chatyuk.admin)
// — project chatyuk-7c9e4. Hanya di-import oleh lib/main_admin.dart.
// Nilai dari android/app/src/admin/google-services.json.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptionsAdmin {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Admin web build belum dikonfigurasi');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptionsAdmin belum diset untuk platform ini',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBWXDO4EGxsxoyz66B1Be2pMzruUK-zl6o',
    appId: '1:599111437536:android:c6fbd326295b92684bd485',
    messagingSenderId: '599111437536',
    projectId: 'chatyuk-7c9e4',
    storageBucket: 'chatyuk-7c9e4.firebasestorage.app',
    databaseURL: 'https://chatyuk-7c9e4-default-rtdb.firebaseio.com',
  );
}

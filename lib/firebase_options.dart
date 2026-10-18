import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase project: cricket-37a8a
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return android;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAjB2S5i3NfXRFg5LMT8NHa6b6943SxchU',
    appId: '1:600375391620:web:30329c68739b9ea61bd9d1',
    messagingSenderId: '600375391620',
    projectId: 'cricket-37a8a',
    authDomain: 'cricket-37a8a.firebaseapp.com',
    storageBucket: 'cricket-37a8a.firebasestorage.app',
    measurementId: 'G-LJMYXLP068',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCVS8lLqe3kzTv-USGpWCgXRqE-0rFi8m0',
    appId: '1:600375391620:android:6ded0636c0a7c3ab1bd9d1',
    messagingSenderId: '600375391620',
    projectId: 'cricket-37a8a',
    storageBucket: 'cricket-37a8a.firebasestorage.app',
  );
}

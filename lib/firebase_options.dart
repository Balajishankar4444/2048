import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return web; // Since we are starting with Web/General
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyBFKvOwZNvPdcEL5IERYDOgVOmqfe-m3do",
  authDomain: "game-2048-8b6d8.firebaseapp.com",
  projectId: "game-2048-8b6d8",
  storageBucket: "game-2048-8b6d8.firebasestorage.app",
  messagingSenderId: "381990610211",
  appId: "1:381990610211:web:8ff0a54b295f6beca31896",
  measurementId: "G-ZQ5MZG0SNF"
  );
}
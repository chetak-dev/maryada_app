import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Initializes Firebase if a project has been connected (via
/// `flutterfire configure`, which generates `firebase_options.dart` and the
/// platform config). Until then, [isReady] stays false and the app runs in a
/// local "demo" mode so the UI is fully usable without a backend.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool isReady = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      isReady = true;
    } catch (e) {
      isReady = false;
      debugPrint('GuardNest: Firebase not connected yet — running in demo mode. ($e)');
    }
  }
}

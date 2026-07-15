import 'package:flutter/material.dart';

import 'firebase/firebase_bootstrap.dart';
import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.init();
  runApp(const GuardNestApp());
}

/// GuardNest — the parent (guardian) app. Transparent, tamper-resistant family
/// safety. This is the fresh, from-scratch build.
class GuardNestApp extends StatelessWidget {
  const GuardNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GuardNest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

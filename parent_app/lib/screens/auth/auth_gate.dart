import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

/// Routes between the login screen and the dashboard based on auth state.
///
/// - When Firebase isn't connected yet (demo mode), it simply shows the login
///   screen, which navigates to the demo dashboard on submit.
/// - When connected, it reacts to `authStateChanges`: signed-out -> login,
///   signed-in -> dashboard (with the guardian's uid for live data).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isConfigured) {
      return const LoginScreen();
    }
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return HomeShell(uid: user.uid);
      },
    );
  }
}

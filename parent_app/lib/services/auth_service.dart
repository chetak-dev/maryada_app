import 'package:firebase_auth/firebase_auth.dart';

import '../firebase/firebase_bootstrap.dart';

/// Thin wrapper over Firebase Auth for guardian sign-in/up. When Firebase isn't
/// connected yet ([FirebaseBootstrap.isReady] == false) the methods no-op so the
/// UI can run in demo mode.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  bool get isConfigured => FirebaseBootstrap.isReady;

  User? get currentUser => isConfigured ? _auth.currentUser : null;

  Stream<User?> authStateChanges() =>
      isConfigured ? _auth.authStateChanges() : const Stream.empty();

  Future<void> signIn(String email, String password) async {
    if (!isConfigured) return;
    await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
  }

  Future<void> signUp(String email, String password) async {
    if (!isConfigured) return;
    await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    await _auth.signOut();
  }

  /// Sends a password-reset email. No-op in demo mode.
  Future<void> sendPasswordReset(String email) async {
    if (!isConfigured) return;
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Maps common Firebase auth errors to friendly messages.
  static String friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'That email address looks invalid.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'An account already exists for that email.';
        case 'weak-password':
          return 'Please choose a stronger password (6+ characters).';
        case 'network-request-failed':
          return 'Network error. Check your connection and try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait and retry.';
      }
      return 'Sign-in error: ${e.message ?? e.code}';
    }
    return 'Something went wrong. Please try again.';
  }
}

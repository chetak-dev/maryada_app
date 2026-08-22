import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  /// Signs in with Google.
  ///
  /// Mobile uses the native account picker rather than Firebase's
  /// [signInWithProvider], which hands off to a browser tab and depends on
  /// sessionStorage surviving the round trip — on Android that failed with
  /// "missing initial state" and left the flow wedged.
  ///
  /// Returns false when the user dismissed the picker, so callers can stay
  /// silent instead of reporting an error.
  Future<bool> signInWithGoogle() async {
    if (!isConfigured) return false;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      await _auth.signInWithPopup(provider);
      return true;
    }
    final google = GoogleSignIn.instance;
    // The web client id from google-services.json; Google needs it to mint an
    // ID token Firebase will accept.
    await google.initialize(serverClientId: _serverClientId);
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google did not return an ID token.',
      );
    }
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    return true;
  }

  static const _serverClientId =
      '361102633654-9cku0qiunhd6qb6rdn4t7nb31taalk8i.apps.googleusercontent.com';

  Future<void> signOut() async {
    if (!isConfigured) return;
    if (!kIsWeb) {
      // Otherwise the picker silently reuses the same account next time.
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Never signed in with Google; nothing to clear.
      }
    }
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

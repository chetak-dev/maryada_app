import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Turns a thrown object into something worth showing a parent.
///
/// Firestore errors stringify to a long `[cloud_firestore/...]` blob — pasting
/// that into a snack bar reads like a crash report, and none of it is
/// actionable. Only the two causes a parent can do something about are named.
String friendlyError(Object error) {
  // Deliberate guard messages (e.g. "this family still has 2 profiles") are
  // already written for the user — pass them through.
  if (error is StateError) return error.message;
  final text = error.toString();
  if (text.contains('permission-denied')) {
    return 'you don’t have permission to change this.';
  }
  if (text.contains('unavailable') || text.contains('network')) {
    return 'you appear to be offline.';
  }
  return 'please try again.';
}

/// Snack-bar helpers used whenever a Firestore read or write fails.
///
/// A failed save used to be invisible: the switch stayed flipped, so a parent
/// would believe a site or app was blocked when nothing had actually been
/// written. Every fire-and-forget write should report through here (and revert
/// its optimistic UI change) so what's on screen always matches the backend.
extension Feedback on BuildContext {
  void showError(String what, [Object? error]) {
    final messenger = ScaffoldMessenger.maybeOf(this);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(error == null ? what : '$what — ${friendlyError(error)}'),
        ),
      );
  }

  void showMessage(String text) {
    ScaffoldMessenger.maybeOf(this)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

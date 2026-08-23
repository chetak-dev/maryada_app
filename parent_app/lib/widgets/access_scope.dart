import 'package:flutter/widgets.dart';

/// Propagates the signed-in org admin's edit permission down the widget tree so
/// screens can hide or disable add-child and rule-editing affordances for
/// view-only accounts. The Firestore security rules are the hard backstop —
/// this is purely for UX.
class AccessScope extends InheritedWidget {
  const AccessScope({super.key, required this.canEdit, required super.child});

  /// Whether the current account may add children and change rules.
  final bool canEdit;

  /// What routes outside the scoped subtree get. Screens opened with
  /// Navigator.push don't inherit from a scope wrapped around `home`, so this
  /// is set alongside every role change; true covers demo mode and the admin
  /// console.
  static bool fallback = true;

  /// Reads the nearest access scope, falling back to [fallback] when absent
  /// (pushed routes, demo mode, the admin console).
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AccessScope>();
    return scope?.canEdit ?? fallback;
  }

  @override
  bool updateShouldNotify(AccessScope oldWidget) => canEdit != oldWidget.canEdit;
}

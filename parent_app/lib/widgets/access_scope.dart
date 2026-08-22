import 'package:flutter/widgets.dart';

/// Propagates the signed-in org admin's edit permission down the widget tree so
/// screens can hide or disable add-child and rule-editing affordances for
/// view-only accounts. The Firestore security rules are the hard backstop —
/// this is purely for UX.
class AccessScope extends InheritedWidget {
  const AccessScope({super.key, required this.canEdit, required super.child});

  /// Whether the current account may add children and change rules.
  final bool canEdit;

  /// Reads the nearest access scope. Defaults to editable when absent (e.g.
  /// demo mode or the admin console), so unscoped screens keep working.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AccessScope>();
    return scope?.canEdit ?? true;
  }

  @override
  bool updateShouldNotify(AccessScope oldWidget) => canEdit != oldWidget.canEdit;
}

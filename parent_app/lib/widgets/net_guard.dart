import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'dialog_buttons.dart';

/// Guards writes behind a connectivity check and a blocking progress dialog.
///
/// Firestore queues offline writes and resolves their futures locally, so a
/// delete or create appears to succeed while nothing reached the server. These
/// helpers make the failure explicit instead, and stop long operations from
/// looking like a frozen screen.
class Net {
  Net._();

  static Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  /// Shows the "no connection" dialog. Returns false so callers can
  /// `if (!await Net.require(context)) return;`.
  static Future<bool> require(BuildContext context) async {
    if (await isOnline()) return true;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.wifi_off_rounded,
            color: AppColors.danger, size: 32),
        title: const Text('No internet connection'),
        content: const Text(
          'You need to be online to make changes. Reconnect and try again.',
        ),
        actions: [
          DialogConfirmButton(
            onPressed: () => Navigator.pop(ctx),
            label: 'OK',
          ),
        ],
      ),
    );
    return false;
  }

  /// Runs [task] behind a modal progress dialog that can't be dismissed.
  static Future<T> withProgress<T>(
    BuildContext context,
    String message,
    Future<T> Function() task,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(message,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await task();
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
  }
}

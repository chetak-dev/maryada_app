import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_update_repository.dart';
import '../data/db.dart';
import '../theme/tokens.dart';
import '../widgets/dialog_buttons.dart';
import 'app_version.dart';

/// Self-update for the parent app.
///
/// Unlike the child app this cannot install silently — that needs Device Owner,
/// which a parent's own phone will never be. So the job here is to notice a
/// newer build and hand the download to the browser, which then runs Android's
/// normal install prompt.
class ParentUpdate {
  ParentUpdate._();

  static bool _askedThisRun = false;

  /// The published build, or null when nothing newer is available.
  static Future<AppUpdateConfig?> available() async {
    if (!Db.ready) return null;
    try {
      final c = await AppUpdateRepository.instance
          .load(AppUpdateRepository.parentDoc);
      if (!c.enabled) return null;
      if (!c.url.startsWith('https://')) return null;
      if (c.versionCode <= AppVersion.build) return null;
      return c;
    } catch (_) {
      return null;
    }
  }

  /// Checks once per app run and offers the update. Silent when up to date.
  static Future<void> promptIfAvailable(BuildContext context) async {
    if (_askedThisRun) return;
    _askedThisRun = true;
    final update = await available();
    if (update == null || !context.mounted) return;
    await _show(context, update, manual: false);
  }

  /// The "Check for updates" action: always says something, even when current.
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final update = await available();
    if (!context.mounted) return;
    if (update == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Maryada Host ${AppVersion.label} is up to date.')),
        );
      return;
    }
    await _show(context, update, manual: true);
  }

  static Future<void> _show(
    BuildContext context,
    AppUpdateConfig update, {
    required bool manual,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded,
            color: AppColors.primary, size: 30),
        title: const Text('Update available'),
        content: Text(
          'A newer Maryada Host is ready (build ${update.versionCode}); '
          'you have build ${AppVersion.build}.\n\n'
          'The download opens in your browser — tap it when it finishes to '
          'install.',
        ),
        actions: [
          DialogCancelButton(
            onPressed: () => Navigator.pop(ctx, false),
            label: manual ? 'Not now' : 'Later',
          ),
          DialogConfirmButton(
            onPressed: () => Navigator.pop(ctx, true),
            label: 'Download',
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(
      Uri.parse(update.url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t open the download link.')),
      );
    }
  }
}

import 'db.dart';
import 'data_clear_repository.dart';
import 'site_policy_repository.dart';

/// Enforces the site admin's retention window.
///
/// There is no server-side scheduler on this project, so the purge runs from
/// the admin's own app: once a day, on open, everything older than the window
/// is deleted for every paired child. The last run is stamped in Firestore
/// rather than locally, so it stays once a day across admins and devices.
class RetentionService {
  RetentionService._();

  static const _interval = Duration(hours: 20);
  static bool _running = false;

  /// Runs the purge if one is due. Safe to call on every app open; failures are
  /// swallowed because this is housekeeping, not something to interrupt an
  /// admin with.
  static Future<void> runIfDue() async {
    if (!Db.ready || _running) return;
    _running = true;
    try {
      final policy = await SitePolicyRepository.instance.loadRetention();
      if (!policy.enabled) return;
      final last = policy.lastRunAt;
      if (last != null && DateTime.now().difference(last) < _interval) return;

      final children = await DataClearRepository.instance.listAllChildren();
      if (children.isEmpty) return;
      await DataClearRepository.instance.clearActivity(
        children: children,
        cutoff: DateTime.now().subtract(Duration(days: policy.days)),
      );
      await SitePolicyRepository.instance.markRetentionRun();
    } catch (_) {
      // Retried on the next open.
    } finally {
      _running = false;
    }
  }
}

import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';

/// Notifies the parent's phone when a child device reports that Maryada's
/// device admin was switched off — the step that has to happen before the app
/// can be uninstalled, and the last thing a device can tell us before it goes
/// silent for good.
///
/// This runs as a periodic background task rather than a push message: sending
/// FCM needs a server (Cloud Functions), which the project's billing plan
/// doesn't include. The trade-off is latency — Android decides when to run the
/// task, and never more often than every 15 minutes.
class RemovalWatch {
  RemovalWatch._();

  static const _task = 'maryada-removal-watch';
  static const _channelId = 'maryada_removal';
  static const _seenKey = 'removalNotified';

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Registers the periodic check. Safe to call on every launch.
  static Future<void> start() async {
    try {
      await Workmanager().initialize(_callback);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // Background work is best-effort; never block startup over it.
    }
  }

  static Future<void> _ensurePlugin() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Checks every child of the signed-in parent's family and notifies once per
  /// device that has lost its admin. Returns true when the check completed.
  static Future<bool> check() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;
    final db = FirebaseFirestore.instance;

    final me = await db.collection('users').doc(uid).get();
    final familyId = (me.data()?['familyId'] ?? '').toString();
    if (familyId.isEmpty) return true;

    final kids =
        await db.collection('families').doc(familyId).collection('children').get();

    final prefs = await SharedPreferences.getInstance();
    final notified = prefs.getStringList(_seenKey)?.toSet() ?? <String>{};
    final removed = <String, ({String name, DateTime? at})>{};
    for (final kid in kids.docs) {
      final data = kid.data();
      if (data['paired'] != true) continue;
      if (data['adminActive'] != false) {
        // Protection restored — allow a future removal to notify again.
        notified.remove(kid.id);
        continue;
      }
      if (notified.contains(kid.id)) continue;
      removed[kid.id] = (
        name: (data['name'] ?? 'A child').toString(),
        at: (data['adminChangedAt'] as Timestamp?)?.toDate(),
      );
    }

    if (removed.isNotEmpty) {
      await _ensurePlugin();
      for (final entry in removed.entries) {
        await _notify(entry.key, entry.value.name, entry.value.at);
        notified.add(entry.key);
      }
    }
    await prefs.setStringList(_seenKey, notified.toList());
    return true;
  }

  static String _when(DateTime? at) {
    if (at == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = at.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'am' : 'pm';
    return '${local.day} ${months[local.month - 1]} ${local.year}, $h:$m $ampm';
  }

  static Future<void> _notify(
      String childId, String name, DateTime? at) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Protection removed',
        channelDescription:
            'Warns you when Maryada is switched off on a child device.',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        styleInformation: BigTextStyleInformation(''),
      ),
    );
    final when = _when(at);
    final body = when.isEmpty
        ? '$name’s device switched Maryada off — the app can now be removed.'
        : '$name’s device switched Maryada off on $when — the app can now be '
            'removed.';
    await _plugin.show(
      id: childId.hashCode & 0x7fffffff,
      title: 'Maryada was turned off',
      body: body,
      notificationDetails: details,
    );
  }
}

/// Background entry point. Must be a top-level function.
@pragma('vm:entry-point')
void _callback() {
  Workmanager().executeTask((task, input) async {
    try {
      DartPluginRegistrant.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return await RemovalWatch.check();
    } catch (_) {
      // A failed run must not disable the schedule.
      return true;
    }
  });
}

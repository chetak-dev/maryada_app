import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/device.dart';
import 'data_clear_repository.dart';
import 'db.dart';

/// Reads the devices attached to a child's profile from
/// `families/{familyId}/children/{childId}/devices`.
class DeviceRepository {
  DeviceRepository._();
  static final instance = DeviceRepository._();

  Stream<List<Device>> watch(String familyId, String childId) {
    return Db.child(familyId, childId)
        .collection('devices')
        .snapshots()
        .map((snap) {
        final devices = snap.docs
          .where((d) => d.data()['revoked'] != true)
          .map((d) => Device.fromDoc(d.id, d.data()))
          .toList();
      // Online first, then most recently seen — the device a parent is looking
      // for is the one doing something.
      devices.sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return (b.lastSeenAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.lastSeenAt?.millisecondsSinceEpoch ?? 0);
      });
      return devices;
    });
  }

  /// Removes one installation and everything it reported. The profile and its
  /// other devices stay; when this was the last device the whole activity
  /// history is wiped and the profile returns to "no device linked".
  Future<void> revoke(String familyId, String childId, String deviceId) async {
    final childRef = Db.child(familyId, childId);
    await childRef.collection('devices').doc(deviceId).set({
      'revoked': true,
      'revokedAt': FieldValue.serverTimestamp(),
      'online': false,
    }, SetOptions(merge: true));

    // This device's own report documents (one per feed, keyed by device id;
    // 'current' is the shared doc legacy single-device builds wrote).
    for (final feed in const [
      'webHistory',
      'callHistory',
      'smsHistory',
      'youtubeHistory',
    ]) {
      try {
        await childRef.collection(feed).doc(deviceId).delete();
      } catch (_) {}
    }

    // Its global registration — revoking must also cut the device's read
    // access and free a slot under the device limit.
    try {
      await Db.instance.collection('devices').doc(deviceId).delete();
    } catch (_) {}

    // Stop the pairing slot pointing at the removed installation.
    try {
      final child = await childRef.get();
      if ((child.data()?['deviceUid'] ?? '') == deviceId) {
        await childRef.set(
            {'deviceUid': FieldValue.delete()}, SetOptions(merge: true));
      }
    } catch (_) {}

    // Last device gone: wipe every remaining trace (usage, location, chats,
    // alerts, the legacy 'current' docs) and un-pair the profile so it shows
    // no status and no apps.
    final remaining = await childRef.collection('devices').get();
    final anyActive =
        remaining.docs.any((d) => d.data()['revoked'] != true);
    if (!anyActive) {
      await DataClearRepository.instance.clearChildActivity(familyId, childId);
      await childRef.set({
        'paired': false,
        'online': false,
        'setupComplete': false,
      }, SetOptions(merge: true));
    }
  }

  /// Renames a device — a parent-facing label only; the child app keeps
  /// reporting its own model, which is used as the fallback when this is blank.
  Future<void> rename(
      String familyId, String childId, String deviceId, String name) {
    return Db.child(familyId, childId).collection('devices').doc(deviceId).set({
      'displayName': name,
    }, SetOptions(merge: true));
  }
}

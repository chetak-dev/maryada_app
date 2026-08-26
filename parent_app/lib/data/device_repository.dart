import 'package:cloud_firestore/cloud_firestore.dart';

import 'data_clear_repository.dart';
import 'db.dart';

/// Changes a parent can make to one installation.
///
/// Devices live in a `devices` map on the profile document, keyed by device
/// uid, so the one listener over the family's profiles already carries every
/// device's state. A subcollection needed a listener per profile, and a family
/// of fifty ran straight into Firestore's hundred-listener limit.
class DeviceRepository {
  DeviceRepository._();
  static final instance = DeviceRepository._();

  /// Removes one installation and everything it reported. The profile and its
  /// other devices stay; when this was the last device the whole activity
  /// history is wiped and the profile returns to "no device linked".
  Future<void> revoke(String familyId, String childId, String deviceId) async {
    final childRef = Db.child(familyId, childId);
    await childRef.set({
      'devices': {
        deviceId: {
          'revoked': true,
          'revokedAt': FieldValue.serverTimestamp(),
          'online': false,
        },
      },
    }, SetOptions(merge: true));

    // This device's own report documents (one per feed, keyed by device id;
    // 'current' is the shared doc legacy single-device builds wrote).
    for (final feed in const [
      'webHistory',
      'callHistory',
      'smsHistory',
      'youtubeHistory',
      'appCalls',
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

    Map<String, dynamic> data = const {};
    try {
      data = (await childRef.get()).data() ?? const {};
    } catch (_) {}

    // Stop the pairing slot pointing at the removed installation.
    if ((data['deviceUid'] ?? '') == deviceId) {
      try {
        await childRef
            .set({'deviceUid': FieldValue.delete()}, SetOptions(merge: true));
      } catch (_) {}
    }

    // Last device gone: wipe every remaining trace (usage, location, chats,
    // alerts, the legacy 'current' docs) and un-pair the profile so it shows
    // no status and no apps.
    final devices = data['devices'];
    final anyActive = devices is Map &&
        devices.entries.any((e) =>
            e.key != deviceId &&
            e.value is Map &&
            (e.value as Map)['revoked'] != true);
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
    return Db.child(familyId, childId).set({
      'devices': {
        deviceId: {'displayName': name},
      },
    }, SetOptions(merge: true));
  }
}

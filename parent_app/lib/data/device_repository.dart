import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/device.dart';
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

  /// Revokes one installation without deleting its profile or other devices.
  Future<void> revoke(String familyId, String childId, String deviceId) {
    return Db.child(familyId, childId).collection('devices').doc(deviceId).set({
      'revoked': true,
      'revokedAt': FieldValue.serverTimestamp(),
      'online': false,
    }, SetOptions(merge: true));
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

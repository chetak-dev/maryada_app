import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/child.dart';
import '../models/device.dart';
import '../models/family.dart';
import 'data_clear_repository.dart';
import 'db.dart';
import 'reporting_cadence.dart';

/// Reads/writes families, children and the pairing handshake in Firestore.
/// All calls assume Firebase is connected ([Db.ready] == true); the UI keeps
/// its demo data until then.
class FamilyRepository {
  FamilyRepository._();
  static final instance = FamilyRepository._();

  static const _codeChars =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusables
  static const _codeTtl = Duration(minutes: 15);

  // ---- Families ----------------------------------------------------------

  Stream<List<FamilyModel>> watchFamilies(String uid) {
    return Db.families
        .where('parentUids', arrayContains: uid)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => FamilyModel.fromMap(d.id, d.data())).toList(),
        );
  }

  /// The one family this account may see: the one the site admin's grant
  /// assigned (`users/{uid}.familyId`), and only once the account is actually
  /// in its `parentUids` (the dashboard joins on sign-in — reading children
  /// before that would be denied by the rules). Emits '' when unassigned.
  Stream<String> watchMyFamilyId(String uid) {
    return Db.instance.collection('users').doc(uid).snapshots().asyncExpand((
      d,
    ) {
      final granted = (d.data()?['familyId'] ?? '').toString();
      if (granted.isEmpty) return Stream.value('');
      return watchFamilies(
        uid,
      ).map((fams) => fams.any((f) => f.id == granted) ? granted : '');
    });
  }

  /// Creates the household a grant will attach a parent to. It has no owner
  /// yet — the invited parent becomes its first guardian when they sign in.
  /// Site-admin only (the security rules say so).
  Future<FamilyModel> createFamilyForGrant(String name) async {
    final doc = Db.families.doc();
    final family = FamilyModel(
      id: doc.id,
      name: name.trim(),
      ownerUid: '',
      parentUids: const [],
    );
    await doc.set(family.toMap());
    return family;
  }

  /// Adds a guardian to the household their grant named. The security rules
  /// only allow adding themselves, and only to that one family. A plain
  /// update, so a deleted family isn't silently resurrected.
  Future<void> joinFamily(String familyId, String uid) {
    return Db.families.doc(familyId).update({
      'parentUids': FieldValue.arrayUnion([uid]),
    });
  }

  /// Removes a guardian from a household — their own membership only (rules).
  /// Run when a grant moved them elsewhere, so a stale membership can't keep
  /// showing them another family's children.
  Future<void> leaveFamily(String familyId, String uid) {
    return Db.families.doc(familyId).update({
      'parentUids': FieldValue.arrayRemove([uid]),
    });
  }

  /// Every family, for the site admin's grant dialog.
  Future<List<FamilyModel>> listFamilies() async {
    final snap = await Db.families.get();
    return snap.docs.map((d) => FamilyModel.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Every family, live, for the site admin's console.
  Stream<List<FamilyModel>> watchAllFamilies() {
    return Db.families.snapshots().map(
      (s) => s.docs.map((d) => FamilyModel.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  /// What's attached to a family: child profiles and registered devices.
  Future<({int children, int devices})> familyLoad(String familyId) async {
    final kids = await Db.children(familyId).count().get();
    final devices = await Db.instance
        .collection('devices')
        .where('familyId', isEqualTo: familyId)
        .count()
        .get();
    return (children: kids.count ?? 0, devices: devices.count ?? 0);
  }

  /// Site-admin rename. The name identifies the household to the admin who
  /// created it and is stamped onto pairing codes and child documents, so the
  /// rules refuse it from a guardian however the UI is reached.
  Future<void> renameFamily(String familyId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('a family needs a name.');
    }
    return Db.families.doc(familyId).set(
      {'name': trimmed},
      SetOptions(merge: true),
    );
  }

  /// Site-admin delete of an **empty** family. Refused while any child profile
  /// or registered device is attached — those must be removed first, so a
  /// household can never be pulled out from under live monitoring.
  Future<void> deleteFamily(String familyId) async {
    final load = await familyLoad(familyId);
    if (load.children > 0) {
      throw StateError(
        'this family still has ${load.children} child profile(s). Delete them first.',
      );
    }
    if (load.devices > 0) {
      throw StateError(
        'this family still has ${load.devices} registered device(s). Remove them first.',
      );
    }
    // Firestore doesn't cascade-delete subcollections with the parent doc.
    for (final sub in ['rules', 'appRules', 'alerts']) {
      final docs = await Db.families.doc(familyId).collection(sub).get();
      for (final d in docs.docs) {
        await d.reference.delete();
      }
    }
    await Db.families.doc(familyId).delete();
  }

  // ---- Children ----------------------------------------------------------

  Stream<List<Child>> watchChildren(String familyId, {String tagId = ''}) {
    final q = tagId.isEmpty
        ? Db.children(familyId)
        : Db.children(familyId).where('tagIds', arrayContains: tagId);
    return q.snapshots().map(
      (s) => s.docs.map((d) => _childFromDoc(d.id, d.data())).toList(),
    );
  }

  /// The tag a parent's grant restricts them to, or '' for the whole family.
  Stream<String> watchMyTagId(String uid) {
    return Db.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((d) => (d.data()?['tagId'] ?? '').toString());
  }

  /// One-shot read of the signed-in parent's tag scope. '' means the whole
  /// family, which is what a site admin and every pre-scoping account gets.
  Future<String> myTagId([String? uid]) async {
    final me = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return '';
    try {
      final d = await Db.instance.collection('users').doc(me).get();
      return (d.data()?['tagId'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  /// The profiles of [familyId] the signed-in parent may see. Every read of the
  /// children collection should go through this or [watchScopedChildren], or a
  /// scoped parent sees profiles their grant excluded.
  Future<QuerySnapshot<Map<String, dynamic>>> scopedChildren(
    String familyId,
  ) async {
    final tag = await myTagId();
    final Query<Map<String, dynamic>> q = tag.isEmpty
        ? Db.children(familyId)
        : Db.children(familyId).where('tagIds', arrayContains: tag);
    return q.get();
  }

  /// Live version of [scopedChildren].
  Stream<List<Child>> watchScopedChildren(String familyId) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return watchChildren(familyId);
    return watchMyTagId(
      me,
    ).asyncExpand((tagId) => watchChildren(familyId, tagId: tagId));
  }

  /// Every child profile in the signed-in parent's own family.
  ///
  /// Families are isolated: a parent must never see another household's
  /// children, so this follows the family their grant assigned — not whatever
  /// families they happen to still be listed in. Profiles without a device
  /// show too — a parent creates the profile first, then pairs devices to it.
  ///
  /// A grant may narrow this further to one tag, so a parent responsible for
  /// one group doesn't see the rest of the household.
  Stream<List<({Child child, String familyId})>> watchMyChildren([
    String? uid,
  ]) {
    final me = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return Stream.value(const <({Child child, String familyId})>[]);
    }
    return watchMyFamilyId(me).asyncExpand((familyId) {
      if (familyId.isEmpty) {
        return Stream.value(const <({Child child, String familyId})>[]);
      }
      return watchMyTagId(me).asyncExpand((tagId) {
        return watchChildren(familyId, tagId: tagId).map(
          (kids) => kids.map((c) => (child: c, familyId: familyId)).toList()
            ..sort(
              (a, b) => a.child.name.toLowerCase().compareTo(
                b.child.name.toLowerCase(),
              ),
            ),
        );
      });
    });
  }

  Future<Child> addChild({
    required String familyId,
    required String name,
    int avatarColor = 0xFF4F46E5,
    List<String> tagIds = const [],
  }) async {
    final doc = Db.children(familyId).doc();
    await doc.set({
      'name': name,
      'avatarColor': avatarColor,
      'deviceModel': '',
      'paired': false,
      'online': false,
      'setupComplete': false,
      'permissionsOk': false,
      if (tagIds.isNotEmpty) 'tagIds': tagIds,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // One more mouth at the write budget: everyone slows down a little.
    unawaited(syncReportingCadence(familyId));
    return Child(
      id: doc.id,
      name: name,
      deviceModel: '',
      avatarColor: Color(avatarColor),
      status: ChildStatus.offline,
      tagIds: tagIds,
    );
  }

  /// Republishes the heartbeat cadence for [familyId] from its current profile
  /// count. Devices read this and slow down as the family grows, so the free
  /// tier's daily write allowance is shared rather than raced for.
  ///
  /// Safe to call often: it only writes when the interval actually changes.
  Future<void> syncReportingCadence(String familyId) async {
    if (familyId.isEmpty) return;
    final doc =
        Db.families.doc(familyId).collection('rules').doc('reporting');
    try {
      final kids = await Db.children(familyId).count().get();
      final count = kids.count ?? 0;
      final wanted = ReportingCadence.forChildCount(count).inMilliseconds;
      final current = await doc.get();
      if (current.data()?['heartbeatMs'] == wanted) return;
      await doc.set({
        'heartbeatMs': wanted,
        'childCount': count,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort: devices fall back to their own default cadence.
    }
  }

  Future<void> renameChild(String familyId, String childId, String name) {
    return Db.children(
      familyId,
    ).doc(childId).set({'name': name}, SetOptions(merge: true));
  }

  /// Asks every device in the family to report right now.
  ///
  /// There is no push channel, so this stamps each profile and the devices that
  /// are awake pick it up from the listener they already hold. A device that is
  /// off or asleep reports at its next check-in, as it would anyway.
  /// Returns how many profiles were asked.
  Future<int> requestSync(String familyId) async {
    final kids = await scopedChildren(familyId);
    if (kids.docs.isEmpty) return 0;
    final batch = Db.instance.batch();
    for (final kid in kids.docs) {
      batch.set(kid.reference, {
        'syncRequestedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    return kids.docs.length;
  }

  Future<void> deleteProfile(String familyId, String childId) async {
    await DataClearRepository.instance.deleteProfile(familyId, childId);
    await syncReportingCadence(familyId);
  }

  /// Live stream of a single child doc (banking-mode & protection status).
  Stream<Child?> watchChild(String familyId, String childId) {
    return Db.children(familyId)
        .doc(childId)
        .snapshots()
        .map((d) => d.exists ? _childFromDoc(d.id, d.data()!) : null);
  }

  // ---- Pairing -----------------------------------------------------------

  /// Creates a one-time pairing code bound to a child slot. [deviceName] is
  /// the parent's label for the device being paired ("Aarav's tablet").
  Future<String> generatePairingCode({
    required String familyId,
    required String childId,
    String deviceName = '',
  }) async {
    final code = _randomCode();
    // Capture the family's display name so the child device can show it (the
    // child can't read the family root doc under the security rules). Stamp it
    // on both the pairing code (read at redeem) and the child doc (read live by
    // the child's own-doc listener).
    String familyName = '';
    try {
      final fam = await Db.families.doc(familyId).get();
      familyName = (fam.data()?['name'] as String?)?.trim() ?? '';
    } catch (_) {
      // Non-fatal: pairing still works without the name.
    }
    if (familyName.isNotEmpty) {
      await Db.children(
        familyId,
      ).doc(childId).set({'familyName': familyName}, SetOptions(merge: true));
    }
    await Db.pairingCodes.doc(code).set({
      'familyId': familyId,
      'childId': childId,
      'familyName': familyName,
      'deviceName': deviceName.trim(),
      'used': false,
      'expiresAt': Timestamp.fromDate(DateTime.now().add(_codeTtl)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  // ---- Mapping -----------------------------------------------------------

  @visibleForTesting
  Child childFromMapForTest(String id, Map<String, dynamic> map) =>
      _childFromDoc(id, map);

  Child _childFromDoc(String id, Map<String, dynamic> map) {
    final paired = map['paired'] == true;
    final permissionsOk = map['permissionsOk'] == true;
    final setupComplete = map['setupComplete'] == true;

    final rawProt = map['protections'];
    final protections = <String, bool>{
      if (rawProt is Map)
        for (final e in rawProt.entries) e.key.toString(): e.value == true,
    };

    // Protected means every required permission is granted on the device. The
    // `online` flag is deliberately NOT part of it: a phone that killed the
    // background service is still protected, and flipping the badge whenever
    // the child had the app closed made the status meaningless.
    final allProtectionsOk = protections.isEmpty
        ? permissionsOk
        : protections.values.every((granted) => granted);
    // Device admin off means the app can be (or already has been) uninstalled
    // — the one thing that must never hide behind "needs attention".
    final adminActive = map['adminActive'] != false;
    final status = !adminActive && paired
        ? ChildStatus.removed
        : paired && setupComplete && allProtectionsOk
        ? ChildStatus.online
        : ChildStatus.offline;

    double? d(dynamic v) => v is num ? v.toDouble() : null;

    final seenAt = (map['lastSeenAt'] as Timestamp?)?.toDate();
    var devices = devicesFromMap(map['devices'], seenAt);
    if (devices.isEmpty) devices = _legacyDevice(map);

    return Child(
      id: id,
      name: (map['name'] ?? 'Child').toString(),
      deviceModel: (map['deviceModel'] ?? '').toString(),
      avatarColor: Color(
        (map['avatarColor'] is int) ? map['avatarColor'] as int : 0xFF4F46E5,
      ),
      status: status,
      lat: d(map['lat']),
      lng: d(map['lng']),
      locationAccuracy: d(map['locationAccuracy']),
      locationUpdatedAt: (map['locationUpdatedAt'] as Timestamp?)?.toDate(),
      address: (map['address'] as String?),
      lastSeenAt: (map['lastSeenAt'] as Timestamp?)?.toDate(),
      paired: paired,
      lockboxActive: map['lockboxActive'] == true,
      lockboxSince: (map['lockboxSince'] as Timestamp?)?.toDate(),
      protections: protections,
      appVersionCode: (map['appVersionCode'] as num?)?.toInt() ?? 0,
      appVersionName: (map['appVersionName'] as String?),
      lastError: (map['lastError'] as String?),
      lastErrorAt: (map['lastErrorAt'] as Timestamp?)?.toDate(),
      devices: devices,
      tagIds: (map['tagIds'] is List)
          ? List<String>.from((map['tagIds'] as List).map((e) => '$e'))
          : const [],
    );
  }

  /// The one device of a profile paired by a build that predates the `devices`
  /// map, which writes only the (no longer read) subcollection.
  ///
  /// Without this such a device is invisible: it never appears on the profile,
  /// the pairing screen never notices it linked, and the delete guard counts
  /// zero devices and lets a live profile be deleted. The profile document is
  /// stamped by every build ever shipped, so its own fields describe the device
  /// well enough to stand in until it takes an update. Costs no extra read.
  static List<Device> _legacyDevice(Map<String, dynamic> map) {
    final uid = (map['deviceUid'] ?? '').toString();
    if (uid.isEmpty || map['paired'] != true) return const [];
    return [
      Device.fromDoc(uid, {
        'deviceModel': map['deviceModel'] ?? 'Device',
        'lastSeenAt': map['lastSeenAt'],
        'protections': map['protections'],
        'permissionsOk': map['permissionsOk'],
        'appVersionCode': map['appVersionCode'],
        'appVersionName': map['appVersionName'],
        'adminActive': map['adminActive'],
        'lastError': map['lastError'],
        'lastErrorAt': map['lastErrorAt'],
      }),
    ];
  }

  /// The profile's installations, each under its own device uid so they never
  /// overwrite one another. Ordered by platform then label — sorting by "last
  /// seen" reshuffled the list on every heartbeat, which moved the default
  /// device selection under the parent's finger.
  ///
  /// [profileSeenAt] is the profile's own heartbeat, used only when it holds a
  /// single device: that device *is* the profile, so the two are the same
  /// event. Devices on a build that predates the `devices` map stamp only the
  /// profile, and would otherwise sit at whatever time they were last recorded
  /// and read as "not reporting" while perfectly healthy.
  @visibleForTesting
  static List<Device> devicesFromMap(dynamic raw, [DateTime? profileSeenAt]) {
    if (raw is! Map) return const [];
    final live = [
      for (final e in raw.entries)
        if (e.value is Map && (e.value as Map)['revoked'] != true) e,
    ];
    final devices = [
      for (final e in live)
        Device.fromDoc(
          e.key.toString(),
          Map<String, dynamic>.from(e.value as Map),
          profileSeenAt: live.length == 1 ? profileSeenAt : null,
        ),
    ];
    devices.sort((a, b) {
      final platform = _platformRank(a).compareTo(_platformRank(b));
      if (platform != 0) return platform;
      final label = a.label.toLowerCase().compareTo(b.label.toLowerCase());
      return label != 0 ? label : a.id.compareTo(b.id);
    });
    return devices;
  }

  static int _platformRank(Device d) => switch (d.platform) {
    'android' => 0,
    'windows' => 1,
    _ => 2,
  };

  String _randomCode([int length = 6]) {
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => _codeChars[rand.nextInt(_codeChars.length)],
    ).join();
  }
}

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/child.dart';
import '../models/family.dart';
import 'data_clear_repository.dart';
import 'db.dart';

/// Reads/writes families, children and the pairing handshake in Firestore.
/// All calls assume Firebase is connected ([Db.ready] == true); the UI keeps
/// its demo data until then.
class FamilyRepository {
  FamilyRepository._();
  static final instance = FamilyRepository._();

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusables
  static const _codeTtl = Duration(minutes: 15);

  // ---- Families ----------------------------------------------------------

  Stream<List<FamilyModel>> watchFamilies(String uid) {
    return Db.families
        .where('parentUids', arrayContains: uid)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => FamilyModel.fromMap(d.id, d.data())).toList());
  }

  /// The one family this account may see: the one the site admin's grant
  /// assigned (`users/{uid}.familyId`), and only once the account is actually
  /// in its `parentUids` (the dashboard joins on sign-in — reading children
  /// before that would be denied by the rules). Emits '' when unassigned.
  Stream<String> watchMyFamilyId(String uid) {
    return Db.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .asyncExpand((d) {
      final granted = (d.data()?['familyId'] ?? '').toString();
      if (granted.isEmpty) return Stream.value('');
      return watchFamilies(uid)
          .map((fams) => fams.any((f) => f.id == granted) ? granted : '');
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
    return snap.docs
        .map((d) => FamilyModel.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Every family, live, for the site admin's console.
  Stream<List<FamilyModel>> watchAllFamilies() {
    return Db.families.snapshots().map((s) => s.docs
        .map((d) => FamilyModel.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
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

  /// Site-admin delete of an **empty** family. Refused while any child profile
  /// or registered device is attached — those must be removed first, so a
  /// household can never be pulled out from under live monitoring.
  Future<void> deleteFamily(String familyId) async {
    final load = await familyLoad(familyId);
    if (load.children > 0) {
      throw StateError(
          'this family still has ${load.children} child profile(s). Delete them first.');
    }
    if (load.devices > 0) {
      throw StateError(
          'this family still has ${load.devices} registered device(s). Remove them first.');
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

  Stream<List<Child>> watchChildren(String familyId) {
    return Db.children(familyId).snapshots().map(
          (s) => s.docs
              .map((d) => _childFromDoc(d.id, d.data()))
              .toList(),
        );
  }

  /// Every child profile in the signed-in parent's own family.
  ///
  /// Families are isolated: a parent must never see another household's
  /// children, so this follows the family their grant assigned — not whatever
  /// families they happen to still be listed in. Profiles without a device
  /// show too — a parent creates the profile first, then pairs devices to it.
  Stream<List<({Child child, String familyId})>> watchMyChildren([String? uid]) {
    final me = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return Stream.value(const <({Child child, String familyId})>[]);
    }
    return watchMyFamilyId(me).asyncExpand((familyId) {
      if (familyId.isEmpty) {
        return Stream.value(const <({Child child, String familyId})>[]);
      }
      return watchChildren(familyId).map((kids) => kids
          .map((c) => (child: c, familyId: familyId))
          .toList()
        ..sort((a, b) =>
            a.child.name.toLowerCase().compareTo(b.child.name.toLowerCase())));
    });
  }

  Future<Child> addChild({
    required String familyId,
    required String name,
    int avatarColor = 0xFF4F46E5,
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
      'createdAt': FieldValue.serverTimestamp(),
    });
    return Child(
      id: doc.id,
      name: name,
      deviceModel: '',
      avatarColor: Color(avatarColor),
      status: ChildStatus.offline,
    );
  }

  Future<void> renameChild(String familyId, String childId, String name) {
    return Db.children(familyId)
        .doc(childId)
        .set({'name': name}, SetOptions(merge: true));
  }

  Future<void> deleteProfile(String familyId, String childId) {
    return DataClearRepository.instance.deleteProfile(familyId, childId);
  }

  /// Live stream of a single child doc (banking-mode & protection status).
  Stream<Child?> watchChild(String familyId, String childId) {
    return Db.children(familyId).doc(childId).snapshots().map(
          (d) => d.exists ? _childFromDoc(d.id, d.data()!) : null,
        );
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
      await Db.children(familyId)
          .doc(childId)
          .set({'familyName': familyName}, SetOptions(merge: true));
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

  Child _childFromDoc(String id, Map<String, dynamic> map) {
    final paired = map['paired'] == true;
    final permissionsOk = map['permissionsOk'] == true;
    final setupComplete = map['setupComplete'] == true;

    final rawProt = map['protections'];
    final protections = <String, bool>{
      if (rawProt is Map)
        for (final e in rawProt.entries)
          e.key.toString(): e.value == true,
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

    return Child(
      id: id,
      name: (map['name'] ?? 'Child').toString(),
      deviceModel: (map['deviceModel'] ?? '').toString(),
      avatarColor: Color(
          (map['avatarColor'] is int) ? map['avatarColor'] as int : 0xFF4F46E5),
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
    );
  }

  String _randomCode([int length = 6]) {
    final rand = Random.secure();
    return List.generate(
        length, (_) => _codeChars[rand.nextInt(_codeChars.length)]).join();
  }
}

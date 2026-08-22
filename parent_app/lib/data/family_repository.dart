import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  Future<FamilyModel> createFamily({
    required String name,
    required String ownerUid,
  }) async {
    final doc = Db.families.doc();
    final family = FamilyModel(
      id: doc.id,
      name: name,
      ownerUid: ownerUid,
      parentUids: [ownerUid],
    );
    await doc.set(family.toMap());
    return family;
  }

  // ---- Children ----------------------------------------------------------

  Stream<List<Child>> watchChildren(String familyId) {
    return Db.children(familyId).snapshots().map(
          (s) => s.docs
              .map((d) => _childFromDoc(d.id, d.data()))
              .toList(),
        );
  }

  /// Every child profile across ALL families, each with its family id. Org
  /// admins share one view of all children (security rules allow org admins to
  /// read the whole `children` collection group). Profiles without a device
  /// show too — a parent creates the profile first, then pairs devices to it.
  Stream<List<({Child child, String familyId})>> watchAllChildren() {
    return Db.instance.collectionGroup('children').snapshots().map(
          (s) => s.docs.map((d) {
            final familyId = d.reference.parent.parent!.id;
            return (child: _childFromDoc(d.id, d.data()), familyId: familyId);
          }).toList()
            ..sort((a, b) =>
                a.child.name.toLowerCase().compareTo(b.child.name.toLowerCase())),
        );
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
    final status = paired && setupComplete && allProtectionsOk
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

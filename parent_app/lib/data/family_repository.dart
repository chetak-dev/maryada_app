import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/child.dart';
import '../models/family.dart';
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
              // Only show children whose device has actually linked; a freshly
              // generated pairing code creates a placeholder that must not appear
              // until the child completes pairing.
              .where((d) => d.data()['paired'] == true)
              .map((d) => _childFromDoc(d.id, d.data()))
              .toList(),
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

  Future<void> removeChild(String familyId, String childId) {
    return Db.children(familyId).doc(childId).delete();
  }

  /// Live stream of a single child doc (banking-mode & protection status).
  Stream<Child?> watchChild(String familyId, String childId) {
    return Db.children(familyId).doc(childId).snapshots().map(
          (d) => d.exists ? _childFromDoc(d.id, d.data()!) : null,
        );
  }

  // ---- Pairing -----------------------------------------------------------

  /// Creates a one-time pairing code bound to a child slot.
  Future<String> generatePairingCode({
    required String familyId,
    required String childId,
  }) async {
    final code = _randomCode();
    await Db.pairingCodes.doc(code).set({
      'familyId': familyId,
      'childId': childId,
      'used': false,
      'expiresAt': Timestamp.fromDate(DateTime.now().add(_codeTtl)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  // ---- Mapping -----------------------------------------------------------

  Child _childFromDoc(String id, Map<String, dynamic> map) {
    final paired = map['paired'] == true;
    final online = map['online'] == true;
    final permissionsOk = map['permissionsOk'] == true;
    final setupComplete = map['setupComplete'] == true;

    final ChildStatus status;
    if (!paired) {
      status = ChildStatus.offline;
    } else if (permissionsOk && online) {
      status = ChildStatus.online;
    } else if (setupComplete) {
      status = ChildStatus.needsAttention;
    } else {
      status = ChildStatus.paired;
    }

    double? d(dynamic v) => v is num ? v.toDouble() : null;

    final rawProt = map['protections'];
    final protections = <String, bool>{
      if (rawProt is Map)
        for (final e in rawProt.entries)
          e.key.toString(): e.value == true,
    };

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
    );
  }

  String _randomCode([int length = 6]) {
    final rand = Random.secure();
    return List.generate(
        length, (_) => _codeChars[rand.nextInt(_codeChars.length)]).join();
  }
}

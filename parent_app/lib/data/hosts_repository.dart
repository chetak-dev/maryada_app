import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'db.dart';

/// Site-admin management of org-admin (parent) accounts (`users` where role is
/// `orgAdmin`, plus legacy `host`).
class HostsRepository {
  HostsRepository._();
  static final instance = HostsRepository._();

  CollectionReference<Map<String, dynamic>> get _col =>
      Db.instance.collection('users');

  Stream<List<AppUser>> watchHosts() {
    return _col
        .where('role', whereIn: ['orgAdmin', 'host'])
        .snapshots()
        .map((s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
          ..sort((a, b) =>
              a.email.toLowerCase().compareTo(b.email.toLowerCase())));
  }

  Future<void> setMaxChildren(String uid, int max) {
    return _col.doc(uid).set({'maxChildren': max}, SetOptions(merge: true));
  }

  Future<void> setSuspended(String uid, bool suspended) {
    return _col.doc(uid).set({'suspended': suspended}, SetOptions(merge: true));
  }

  Future<void> setAccess(String uid, AccessLevel access) {
    return _col.doc(uid).set({'access': accessId(access)}, SetOptions(merge: true));
  }

  /// Narrows a parent to one tag's profiles, or '' for the whole family. Also
  /// written onto the grant so re-signing-in doesn't restore the old scope.
  Future<void> setTagId(String uid, String tagId) async {
    await _col.doc(uid).set({'tagId': tagId}, SetOptions(merge: true));
    final snap = await _col.doc(uid).get();
    final code = (snap.data()?['inviteCode'] ?? '').toString();
    if (code.isEmpty) return;
    try {
      await Db.instance
          .collection('invites')
          .doc(code)
          .set({'tagId': tagId}, SetOptions(merge: true));
    } catch (_) {
      // The grant may have been revoked; the account record is what counts.
    }
  }

  /// Removes an org admin's account record, revoking their access. Their
  /// families/children are left intact; they become a blocked account until
  /// granted access again.
  Future<void> delete(String uid) => _col.doc(uid).delete();
}

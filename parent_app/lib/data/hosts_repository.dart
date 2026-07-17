import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'db.dart';

/// Admin-facing management of host accounts (`users` where role == 'host').
class HostsRepository {
  HostsRepository._();
  static final instance = HostsRepository._();

  CollectionReference<Map<String, dynamic>> get _col =>
      Db.instance.collection('users');

  Stream<List<AppUser>> watchHosts() {
    return _col.where('role', isEqualTo: 'host').snapshots().map((s) =>
        s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase())));
  }

  Future<void> setMaxChildren(String uid, int max) {
    return _col.doc(uid).set({'maxChildren': max}, SetOptions(merge: true));
  }

  Future<void> setSuspended(String uid, bool suspended) {
    return _col.doc(uid).set({'suspended': suspended}, SetOptions(merge: true));
  }
}

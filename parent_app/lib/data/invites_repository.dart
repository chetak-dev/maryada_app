import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// A pending host invite (`invites/{code}`). An admin creates one for an email
/// (optionally pre-setting a child limit); when that email signs in for the
/// first time it's redeemed and the account becomes a host.
class Invite {
  final String code;
  final String email;
  final int maxChildren;
  final bool used;
  final DateTime? createdAt;

  const Invite({
    required this.code,
    required this.email,
    required this.maxChildren,
    required this.used,
    this.createdAt,
  });

  factory Invite.fromMap(String code, Map<String, dynamic> m) {
    final ts = m['createdAt'];
    return Invite(
      code: code,
      email: (m['email'] ?? '').toString(),
      maxChildren: (m['maxChildren'] as num?)?.toInt() ?? 5,
      used: m['used'] == true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class InvitesRepository {
  InvitesRepository._();
  static final instance = InvitesRepository._();

  CollectionReference<Map<String, dynamic>> get _col =>
      Db.instance.collection('invites');

  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _genCode() {
    final r = Random.secure();
    return List.generate(8, (_) => _chars[r.nextInt(_chars.length)]).join();
  }

  Stream<List<Invite>> watch() {
    return _col.orderBy('createdAt', descending: true).snapshots().map((s) =>
        s.docs.map((d) => Invite.fromMap(d.id, d.data())).toList());
  }

  Future<String> createInvite({
    required String email,
    required int maxChildren,
  }) async {
    final code = _genCode();
    await _col.doc(code).set({
      'email': email.trim().toLowerCase(),
      'maxChildren': maxChildren,
      'used': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findUnusedForEmail(
      String email) async {
    final q = await _col
        .where('email', isEqualTo: email.trim().toLowerCase())
        .where('used', isEqualTo: false)
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : q.docs.first;
  }

  Future<void> markUsed(String code, String uid) {
    return _col.doc(code).set({
      'used': true,
      'usedBy': uid,
      'usedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String code) => _col.doc(code).delete();
}

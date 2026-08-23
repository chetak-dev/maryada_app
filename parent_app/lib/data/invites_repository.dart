import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'db.dart';

/// A pending org-admin access grant (`invites/{email}`). A site admin creates
/// one for an email (setting view/edit access and a child limit); when that
/// email signs in — with Google or a password — it's redeemed and the account
/// becomes an org admin with that access. There is no code to type: the grant
/// is looked up by the address the account signs in with.
class Invite {
  /// The grant's document id. Now the granted email; older grants used a
  /// random access code.
  final String code;
  final String email;
  final AccessLevel access;
  final int maxChildren;
  final bool used;
  final DateTime? createdAt;

  /// The family this grant joins. Empty means "give them their own family",
  /// which is what a first parent gets; set it to add a second guardian to a
  /// household that already exists.
  final String familyId;

  const Invite({
    required this.code,
    required this.email,
    required this.access,
    required this.maxChildren,
    required this.used,
    this.familyId = '',
    this.createdAt,
  });

  factory Invite.fromMap(String code, Map<String, dynamic> m) {
    final ts = m['createdAt'];
    return Invite(
      code: code,
      email: (m['email'] ?? '').toString(),
      access: accessFromId(m['access']?.toString() ?? 'edit'),
      maxChildren: (m['maxChildren'] as num?)?.toInt() ?? 5,
      used: m['used'] == true,
      familyId: (m['familyId'] ?? '').toString(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class InvitesRepository {
  InvitesRepository._();
  static final instance = InvitesRepository._();

  CollectionReference<Map<String, dynamic>> get _col =>
      Db.instance.collection('invites');

  /// Grants are stored under the email they were issued to, so granting the
  /// same person again replaces the earlier grant instead of racing it.
  String keyFor(String email) => email.trim().toLowerCase();

  Stream<List<Invite>> watch() {
    return _col.orderBy('createdAt', descending: true).snapshots().map((s) =>
        s.docs.map((d) => Invite.fromMap(d.id, d.data())).toList());
  }

  /// The grant that applies to [email], newest first. Falls back to a lookup by
  /// field for grants issued before they were keyed by email.
  Future<Invite?> findForEmail(String email) async {
    final key = keyFor(email);
    final direct = await _col.doc(key).get();
    if (direct.exists) return Invite.fromMap(direct.id, direct.data()!);

    final q = await _col.where('email', isEqualTo: key).get();
    if (q.docs.isEmpty) return null;
    final all = q.docs.map((d) => Invite.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
    return all.first;
  }

  Future<void> createInvite({
    required String email,
    required int maxChildren,
    required AccessLevel access,
    String familyId = '',
  }) async {
    await _col.doc(keyFor(email)).set({
      'email': keyFor(email),
      'access': accessId(access),
      'maxChildren': maxChildren,
      'familyId': familyId,
      'used': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
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

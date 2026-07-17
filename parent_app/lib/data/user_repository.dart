import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/app_user.dart';
import 'db.dart';
import 'invites_repository.dart';

/// Reads/creates the signed-in account record (`users/{uid}`) and resolves its
/// role on first sign-in (admin by bootstrap email, otherwise host).
class UserRepository {
  UserRepository._();
  static final instance = UserRepository._();

  CollectionReference<Map<String, dynamic>> get _col =>
      Db.instance.collection('users');

  Stream<AppUser?> watch(String uid) {
    return _col.doc(uid).snapshots().map(
        (d) => d.exists ? AppUser.fromMap(uid, d.data()!) : null);
  }

  /// Ensures a `users/{uid}` record exists, creating one on first sign-in.
  /// Returns the resolved account (admin / host).
  Future<AppUser> resolve(String uid, String email) async {
    final ref = _col.doc(uid);
    final snap = await ref.get();
    if (snap.exists) return AppUser.fromMap(uid, snap.data()!);

    final lower = email.trim().toLowerCase();

    // Bootstrap admin by email.
    if (lower == kBootstrapAdminEmail.toLowerCase()) {
      final u = AppUser(
        uid: uid,
        email: email,
        role: UserRole.admin,
        maxChildren: 1 << 20,
      );
      await ref.set(u.toCreateMap());
      return u;
    }

    // Host: apply an invite's limit if one matches, else the default.
    var maxChildren = kDefaultMaxChildren;
    String? inviteCode;
    try {
      final inv = await InvitesRepository.instance.findUnusedForEmail(lower);
      if (inv != null) {
        maxChildren =
            (inv.data()['maxChildren'] as num?)?.toInt() ?? kDefaultMaxChildren;
        inviteCode = inv.id;
      }
    } catch (_) {
      // Ignore invite lookup failures; fall back to the default limit.
    }

    final u = AppUser(
      uid: uid,
      email: email,
      role: UserRole.host,
      maxChildren: maxChildren,
    );
    await ref.set(u.toCreateMap());
    if (inviteCode != null) {
      try {
        await InvitesRepository.instance.markUsed(inviteCode, uid);
      } catch (_) {}
    }
    return u;
  }
}

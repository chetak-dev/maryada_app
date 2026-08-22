import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/app_user.dart';
import 'db.dart';
import 'invites_repository.dart';

/// Reads/creates the signed-in account record (`users/{uid}`) and resolves its
/// role on first sign-in: the site admin by bootstrap email, an org admin if a
/// matching access grant exists for the email, otherwise a blocked `user`.
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
  /// Returns the resolved account (site admin / org admin / blocked user).
  Future<AppUser> resolve(String uid, String email) async {
    final ref = _col.doc(uid);
    final snap = await ref.get();
    if (snap.exists) return AppUser.fromMap(uid, snap.data()!);

    final lower = email.trim().toLowerCase();

    // Bootstrap the site admin by email.
    if (lower == kBootstrapAdminEmail.toLowerCase()) {
      final u = AppUser(
        uid: uid,
        email: email,
        role: UserRole.siteAdmin,
        access: AccessLevel.edit,
        maxChildren: 1 << 20,
      );
      await ref.set(u.toCreateMap());
      return u;
    }

    // Otherwise the account must have been granted access by the site admin.
    // Find a matching, unused grant — first by an explicitly typed code, then
    // by the account's email. The grant's email must match, so a code alone
    // can't be redeemed by a different address.
    Invite? grant;

    final typed = InvitesRepository.instance.pendingCode;
    if (typed != null && typed.trim().isNotEmpty) {
      try {
        final inv = await InvitesRepository.instance.findByCode(typed);
        if (inv != null && !inv.used && inv.email.toLowerCase() == lower) {
          grant = inv;
        }
      } catch (_) {}
      InvitesRepository.instance.pendingCode = null;
    }

    if (grant == null) {
      try {
        final doc = await InvitesRepository.instance.findUnusedForEmail(lower);
        if (doc != null) grant = Invite.fromMap(doc.id, doc.data());
      } catch (_) {
        // Ignore lookup failures; treated as no grant below.
      }
    }

    if (grant != null) {
      final u = AppUser(
        uid: uid,
        email: email,
        role: UserRole.orgAdmin,
        access: grant.access,
        maxChildren: grant.maxChildren,
        inviteCode: grant.code,
      );
      await ref.set(u.toCreateMap());
      try {
        await InvitesRepository.instance.markUsed(grant.code, uid);
      } catch (_) {}
      return u;
    }

    // No grant — record a blocked account so the site admin can see them, and
    // show the "access pending" screen.
    final u = AppUser(
      uid: uid,
      email: email,
      role: UserRole.user,
      access: AccessLevel.view,
      maxChildren: 0,
    );
    await ref.set(u.toCreateMap());
    return u;
  }
}

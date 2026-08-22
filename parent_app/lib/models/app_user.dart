import 'package:cloud_firestore/cloud_firestore.dart';

/// Account roles in the Site admin -> Org admin (parent) -> Family -> Child
/// hierarchy. `user` is a signed-in account that hasn't been granted access
/// yet (blocked until a site admin grants it view or edit).
enum UserRole { siteAdmin, orgAdmin, user }

/// The access a site admin grants an org admin. `view` is read-only; `edit`
/// can add children and change rules.
enum AccessLevel { view, edit }

UserRole roleFromId(String? id) => switch (id) {
      // New ids.
      'siteAdmin' => UserRole.siteAdmin,
      'orgAdmin' => UserRole.orgAdmin,
      'user' => UserRole.user,
      // Legacy ids (pre-roles rename) — keep existing accounts working.
      'admin' => UserRole.siteAdmin,
      'host' => UserRole.orgAdmin,
      _ => UserRole.user,
    };

String roleId(UserRole r) => switch (r) {
      UserRole.siteAdmin => 'siteAdmin',
      UserRole.orgAdmin => 'orgAdmin',
      UserRole.user => 'user',
    };

AccessLevel accessFromId(String? id) =>
    id == 'view' ? AccessLevel.view : AccessLevel.edit;

String accessId(AccessLevel a) => a == AccessLevel.view ? 'view' : 'edit';

/// A signed-in account (`users/{uid}`). Org admins are parents who manage
/// families; the site admin manages org admins and their access.
class AppUser {
  final String uid;
  final String email;
  final String? name;
  final UserRole role;
  final AccessLevel access;
  final int maxChildren;
  final bool suspended;
  final String? inviteCode;
  final DateTime? createdAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.role,
    this.access = AccessLevel.edit,
    this.name,
    this.maxChildren = 5,
    this.suspended = false,
    this.inviteCode,
    this.createdAt,
  });

  bool get isSiteAdmin => role == UserRole.siteAdmin;
  bool get isOrgAdmin => role == UserRole.orgAdmin;
  bool get isUser => role == UserRole.user;

  /// A `user` account has no access until a site admin grants it.
  bool get hasAccess => isSiteAdmin || isOrgAdmin;

  /// Can add children and change rules. Site admins always can; org admins only
  /// with edit access.
  bool get canEdit => isSiteAdmin || (isOrgAdmin && access == AccessLevel.edit);

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) {
    final ts = m['createdAt'];
    return AppUser(
      uid: uid,
      email: (m['email'] ?? '').toString(),
      name: m['name']?.toString(),
      role: roleFromId(m['role']?.toString()),
      // Legacy accounts have no `access` field — treat them as full-access
      // editors so nothing they could do before breaks.
      access: accessFromId(m['access']?.toString() ?? 'edit'),
      maxChildren: (m['maxChildren'] as num?)?.toInt() ?? 5,
      suspended: m['suspended'] == true,
      inviteCode: m['inviteCode']?.toString(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'email': email,
        if (name != null) 'name': name,
        'role': roleId(role),
        'access': accessId(access),
        'maxChildren': maxChildren,
        'suspended': suspended,
        if (inviteCode != null) 'inviteCode': inviteCode,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Account roles in the Admin -> Host -> Family -> Child hierarchy.
enum UserRole { admin, host, unknown }

UserRole roleFromId(String? id) => switch (id) {
      'admin' => UserRole.admin,
      'host' => UserRole.host,
      _ => UserRole.unknown,
    };

String roleId(UserRole r) => switch (r) {
      UserRole.admin => 'admin',
      UserRole.host => 'host',
      UserRole.unknown => 'unknown',
    };

/// A signed-in account (`users/{uid}`). Hosts are parents who manage a family;
/// the admin manages hosts.
class AppUser {
  final String uid;
  final String email;
  final String? name;
  final UserRole role;
  final int maxChildren;
  final bool suspended;
  final DateTime? createdAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.role,
    this.name,
    this.maxChildren = 5,
    this.suspended = false,
    this.createdAt,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get isHost => role == UserRole.host;

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) {
    final ts = m['createdAt'];
    return AppUser(
      uid: uid,
      email: (m['email'] ?? '').toString(),
      name: m['name']?.toString(),
      role: roleFromId(m['role']?.toString()),
      maxChildren: (m['maxChildren'] as num?)?.toInt() ?? 5,
      suspended: m['suspended'] == true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'email': email,
        if (name != null) 'name': name,
        'role': roleId(role),
        'maxChildren': maxChildren,
        'suspended': suspended,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

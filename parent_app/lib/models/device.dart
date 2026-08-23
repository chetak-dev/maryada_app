import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One device attached to a child's profile.
///
/// A child used to *be* a device — name and `deviceUid` lived on the same
/// document. Profiles can hold more than one device (phone, tablet, laptop), so
/// device state lives here while the profile keeps the person and the rules.
class Device {
  final String id;
  final String deviceModel;

  /// The parent's label for this device ("Aarav's tablet"); may be empty.
  final String displayName;
  final String platform;
  final bool online;
  final DateTime? lastSeenAt;
  final bool permissionsOk;
  final int appVersionCode;
  final String? appVersionName;

  /// The version exactly as the child's own screen shows it, e.g. "v1.0.0(0)".
  /// Empty on devices running a build from before it was reported.
  final String appVersionLabel;
  final Map<String, bool> protections;

  const Device({
    required this.id,
    required this.deviceModel,
    this.displayName = '',
    this.platform = 'android',
    this.online = false,
    this.lastSeenAt,
    this.permissionsOk = false,
    this.appVersionCode = 0,
    this.appVersionName,
    this.appVersionLabel = '',
    this.protections = const {},
  });

  /// What the parent sees first: their own name for it, else the model.
  String get label => displayName.isNotEmpty ? displayName : deviceModel;

  /// A device that hasn't reported for a while can't be trusted to say it's
  /// online — it can't update the flag once it stops reporting at all.
  bool get isStale {
    final at = lastSeenAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > const Duration(minutes: 10);
  }

  bool get isOnline => online && !isStale;

  List<String> get offProtections =>
      protections.entries.where((e) => !e.value).map((e) => e.key).toList();

  /// Every required permission granted. The protections map is authoritative
  /// when present; `permissionsOk` is stamped true at pairing.
  bool get allProtectionsOk => protections.isEmpty
      ? permissionsOk
      : protections.values.every((granted) => granted);

  /// The platform's own mark, so a phone, iPad and laptop are told apart at a
  /// glance rather than by reading the model name.
  IconData get icon => switch (platform) {
        'ios' || 'ipados' || 'macos' => Icons.apple,
        'windows' => Icons.window_rounded,
        'linux' => Icons.terminal_rounded,
        _ => Icons.android,
      };

  /// Brand colour for [icon]; the status colour stays on the status line.
  Color get platformColor => switch (platform) {
        'ios' || 'ipados' || 'macos' => const Color(0xFF1D1D1F),
        'windows' => const Color(0xFF0078D4),
        'linux' => const Color(0xFF4D4D4D),
        _ => const Color(0xFF3DDC84),
      };

  Color get statusColor =>
      allProtectionsOk ? AppColors.success : AppColors.warning;

  /// Permissions decide this, not the heartbeat: a device whose background
  /// service was killed is still protected, and saying "Offline" whenever the
  /// child had the app closed told the parent nothing they could act on.
  String get statusLabel =>
      allProtectionsOk ? 'Protected' : 'Permission missing';

  /// What to print next to the status. Falls back to the raw version name for
  /// devices that predate the reported label.
  String get versionLabel {
    if (appVersionLabel.isNotEmpty) return appVersionLabel;
    final name = appVersionName;
    return (name == null || name.isEmpty) ? '' : 'v$name';
  }

  static Device fromDoc(String id, Map<String, dynamic> m) {
    final rawProt = m['protections'];
    return Device(
      id: id,
      deviceModel: (m['deviceModel'] ?? 'Device').toString(),
      displayName: (m['displayName'] ?? '').toString().trim(),
      platform: (m['platform'] ?? 'android').toString(),
      online: m['online'] == true,
      lastSeenAt: (m['lastSeenAt'] as Timestamp?)?.toDate(),
      permissionsOk: m['permissionsOk'] == true,
      appVersionCode: (m['appVersionCode'] as num?)?.toInt() ?? 0,
      appVersionName: m['appVersionName'] as String?,
      appVersionLabel: (m['appVersionLabel'] ?? '').toString(),
      protections: {
        if (rawProt is Map)
          for (final e in rawProt.entries) e.key.toString(): e.value == true,
      },
    );
  }
}

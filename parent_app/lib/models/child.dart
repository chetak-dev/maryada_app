import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'device.dart';

/// A profile is either fully protected (every required permission granted on
/// the device) or it isn't. A quiet device is NOT the same thing: phones kill
/// background services, so a missed heartbeat used to flip a perfectly
/// protected child to "Offline" until they opened the app. Only a missing
/// permission — something the parent can actually act on — reads as offline.
enum ChildStatus { online, offline, removed }

extension ChildStatusUi on ChildStatus {
  String get label => switch (this) {
        ChildStatus.online => 'Protected',
        ChildStatus.offline => 'Needs attention',
        ChildStatus.removed => 'App removed',
      };

  Color get color => switch (this) {
        ChildStatus.online => AppColors.success,
        ChildStatus.offline => AppColors.warning,
        ChildStatus.removed => AppColors.danger,
      };

  IconData get icon => switch (this) {
        ChildStatus.online => Icons.verified_user_rounded,
        ChildStatus.offline => Icons.gpp_maybe_rounded,
        ChildStatus.removed => Icons.gpp_bad_rounded,
      };
}

/// A monitored child, their status and the last thing their device reported.
class Child {
  final String id;
  final String name;
  final String deviceModel;
  final Color avatarColor;
  final ChildStatus status;
  final double? lat;
  final double? lng;
  final double? locationAccuracy;
  final DateTime? locationUpdatedAt;
  final String? address;

  /// Last heartbeat from the device. Used to detect a device that has gone
  /// silent (e.g. uninstalled, powered off, or no network).
  final DateTime? lastSeenAt;

  /// Whether any device is linked to this profile. A profile without a device
  /// has no protection status at all — neither protected nor needing
  /// attention. Defaults true so demo children look alive.
  final bool paired;

  /// True while the child has a required protection turned off and the device
  /// is in "banking mode" — every app except the allow-list is suspended.
  final bool lockboxActive;

  /// When banking mode started (for showing duration to the parent).
  final DateTime? lockboxSince;

  /// Live grant state of each protection, e.g. {'accessibility': false, ...}.
  /// Empty until the device reports it via heartbeat.
  final Map<String, bool> protections;

  /// The child app's installed version, reported via heartbeat. 0 / null until
  /// the device reports it (builds older than 1.0.4 don't report a version).
  final int appVersionCode;
  final String? appVersionName;

  /// The most recent failure the child device reported through its heartbeat
  /// (e.g. a rejected write or a permission it lost). The device can't show a
  /// parent anything itself, so this is the only way a silent breakage on a
  /// remote device becomes visible.
  final String? lastError;
  final DateTime? lastErrorAt;

  /// Every installation on this profile. They each stamp the fields above too,
  /// so on their own those read as whichever device reported last — anything
  /// that must be true of the *profile* is worked out from this list.
  final List<Device> devices;

  /// The family tags this profile wears, for grouping the list.
  final List<String> tagIds;

  const Child({
    required this.id,
    required this.name,
    required this.deviceModel,
    required this.avatarColor,
    required this.status,
    this.lat,
    this.lng,
    this.locationAccuracy,
    this.locationUpdatedAt,
    this.address,
    this.lastSeenAt,
    this.paired = true,
    this.lockboxActive = false,
    this.lockboxSince,
    this.protections = const {},
    this.appVersionCode = 0,
    this.appVersionName,
    this.lastError,
    this.lastErrorAt,
    this.devices = const [],
    this.tagIds = const [],
  });

  /// A silent device is still worth surfacing, but as "last seen", never as the
  /// headline status — see [ChildStatus].
  static const heartbeatTimeout = Duration(minutes: 5);

  bool get isStale {
    final ls = lastSeenAt;
    return ls == null || DateTime.now().difference(ls) > heartbeatTimeout;
  }

  /// What the UI should show. Kept as a getter so callers don't have to know
  /// that the status already accounts for everything.
  ChildStatus get effectiveStatus {
    final worst = ProfileStatus.worst(devices);
    if (worst == null) return status;
    if (worst.likelyRemoved || worst.removalUnlocked) return ChildStatus.removed;
    return worst.severity == 0 ? ChildStatus.online : ChildStatus.offline;
  }

  bool get hasLocation => lat != null && lng != null;

  /// A device error is only worth showing while it's recent — an old one has
  /// usually been resolved by a restart or a re-grant.
  bool get hasRecentError {
    final at = lastErrorAt;
    final error = lastError;
    if (error == null || error.isEmpty || at == null) return false;
    // Existing devices run before the hardened rules are deployed. Their
    // best-effort global registration is expected to be rejected while the
    // legacy child-document trust path continues protecting them; that is a
    // migration state, not a device problem the parent can act on.
    final normalized = error.toLowerCase();
    if (normalized.startsWith('ensuredeviceregistered:') &&
        normalized.contains('permission_denied')) {
      return false;
    }
    return DateTime.now().difference(at) < const Duration(hours: 24);
  }

  /// Protections currently turned off on the device (from the live heartbeat).
  List<String> get offProtections => protections.entries
      .where((e) => e.value == false)
      .map((e) => e.key)
      .toList();

  String get initials =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

/// Sample profiles shown only before Firebase is connected, so the app can be
/// explored offline.
const demoChildren = <Child>[
  Child(
    id: '1',
    name: 'Aarav',
    deviceModel: 'Realme RMX3286',
    avatarColor: Color(0xFF4F46E5),
    status: ChildStatus.online,
  ),
  Child(
    id: '2',
    name: 'Meera',
    deviceModel: 'Samsung Galaxy A15',
    avatarColor: Color(0xFF10B981),
    status: ChildStatus.offline,
  ),
];

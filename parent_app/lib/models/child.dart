import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// High-level status of a child's device, shown to the guardian.
enum ChildStatus { online, needsAttention, paired, offline }

extension ChildStatusUi on ChildStatus {
  String get label => switch (this) {
        ChildStatus.online => 'Protected',
        ChildStatus.needsAttention => 'Permission missing',
        ChildStatus.paired => 'Setting up',
        ChildStatus.offline => 'Offline',
      };

  Color get color => switch (this) {
        ChildStatus.online => AppColors.success,
        ChildStatus.needsAttention => AppColors.warning,
        ChildStatus.paired => AppColors.primary,
        ChildStatus.offline => AppColors.danger,
      };

  IconData get icon => switch (this) {
        ChildStatus.online => Icons.verified_user_rounded,
        ChildStatus.needsAttention => Icons.gpp_maybe_rounded,
        ChildStatus.paired => Icons.sync_rounded,
        ChildStatus.offline => Icons.cloud_off_rounded,
      };
}

/// A monitored child + their device (UI model; backend wiring comes later).
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

  /// True while the child has a required protection turned off and the device
  /// is in "banking mode" — every app except the allow-list is suspended.
  final bool lockboxActive;

  /// When banking mode started (for showing duration to the parent).
  final DateTime? lockboxSince;

  /// Live grant state of each protection, e.g. {'accessibility': false, ...}.
  /// Empty until the device reports it via heartbeat.
  final Map<String, bool> protections;

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
    this.lockboxActive = false,
    this.lockboxSince,
    this.protections = const {},
  });

  /// If the device stops sending heartbeats (uninstalled / off / no network)
  /// its stored `online` flag can't update — so we treat a stale heartbeat as
  /// offline regardless of what the document says.
  static const heartbeatTimeout = Duration(minutes: 5);

  bool get isStale {
    final ls = lastSeenAt;
    return ls == null || DateTime.now().difference(ls) > heartbeatTimeout;
  }

  /// Status corrected for heartbeat freshness (what the UI should show).
  ChildStatus get effectiveStatus {
    if (status == ChildStatus.offline) return status; // unpaired
    return isStale ? ChildStatus.offline : status;
  }

  bool get hasLocation => lat != null && lng != null;

  /// Protections currently turned off on the device (from the live heartbeat).
  List<String> get offProtections => protections.entries
      .where((e) => e.value == false)
      .map((e) => e.key)
      .toList();

  String get initials =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

/// Placeholder data so the dashboard is explorable before the backend exists.
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
    status: ChildStatus.needsAttention,
  ),
];

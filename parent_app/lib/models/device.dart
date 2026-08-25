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

  /// False once the child device reported that its device admin was turned
  /// off. Deactivating the admin is required before the app can be
  /// uninstalled, so this is the clearest warning of a removal in progress.
  final bool adminActive;

  /// When that happened, so the parent knows how long it has been off.
  final DateTime? adminChangedAt;
  final Map<String, bool> protections;

  /// What this platform can actually report. Empty on Android and on anything
  /// installed before devices declared it, which is read as "everything" —
  /// hiding a feed those devices do fill would lose real data.
  final Map<String, bool> capabilities;

  /// The last failure this device reported. Held per device: a profile-level
  /// copy is overwritten by whichever device happens to report last, so one
  /// machine's old problem used to show against a phone that was perfectly fine.
  final String? lastError;
  final DateTime? lastErrorAt;

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
    this.adminActive = true,
    this.adminChangedAt,
    this.protections = const {},
    this.capabilities = const {},
    this.lastError,
    this.lastErrorAt,
  });

  /// True unless this device says otherwise.
  bool supports(String feature) => capabilities[feature] ?? true;

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

  /// Long enough without a heartbeat that the app is no longer running at all.
  /// A phone is carried all day, so an hour of quiet is already odd; a PC is
  /// switched off every night, and calling that "not reporting" cried wolf.
  bool get isSilent {
    final at = lastSeenAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > silenceWindow;
  }

  Duration get silenceWindow => platform == 'android'
      ? const Duration(hours: 1)
      : const Duration(hours: 12);

  /// A failure worth showing: recent, and not the known migration noise from
  /// devices predating the hardened rules.
  bool get hasRecentError {
    final at = lastErrorAt;
    final error = lastError;
    if (error == null || error.isEmpty || at == null) return false;
    final normalized = error.toLowerCase();
    if (normalized.startsWith('ensuredeviceregistered:') &&
        normalized.contains('permission_denied')) {
      return false;
    }
    // A heartbeat after the failure proves the device recovered, whether or not
    // it managed to clear the field itself.
    final seen = lastSeenAt;
    if (seen != null && seen.isAfter(at)) return false;
    return DateTime.now().difference(at) < const Duration(hours: 24);
  }

  /// The app can be removed: its device admin was switched off.
  bool get removalUnlocked => !adminActive;

  /// Silent *and* unprotected — as close to "it's gone" as the phone can tell
  /// us, since an uninstalled app cannot report its own removal.
  bool get likelyRemoved => removalUnlocked && isSilent;

  List<String> get offProtections =>
      protections.entries.where((e) => !e.value).map((e) => e.key).toList();

  /// The missing protections in words a parent can act on. "Permission
  /// missing" alone left them opening every screen to find out which.
  List<String> get missingProtectionLabels => [
        for (final key in offProtections) _protectionLabels[key] ?? key,
      ];

  static const _protectionLabels = <String, String>{
    'accessibility': 'App blocking',
    'monitoring': 'Monitoring service (turn App blocking off and on)',
    'notificationAccess': 'Notification access',
    'usageAccess': 'Usage access',
    'callLog': 'Call log',
    'sms': 'Messages',
    'battery': 'Battery exemption',
    'deviceAdmin': 'Device admin',
    'overlay': 'Display over other apps',
    'service': 'Background service',
    'startup': 'Start with Windows',
  };

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

  Color get statusColor {
    if (removalUnlocked) return AppColors.danger;
    if (!allProtectionsOk) return AppColors.warning;
    if (isSilent) return AppColors.warning;
    return AppColors.success;
  }

  /// Permissions decide this, not the heartbeat: a device whose background
  /// service was killed is still protected, and saying "Offline" whenever the
  /// child had the app closed told the parent nothing they could act on.
  /// A missing permission outranks silence — it is the thing the parent can
  /// actually go and fix, and hiding it behind "Not reporting" made two devices
  /// in the very same state read as two different problems.
  String get statusLabel {
    if (likelyRemoved) return 'App removed${_removedOn()}';
    if (removalUnlocked) return 'Protection turned off${_removedOn()}';
    if (!allProtectionsOk) return 'Permission missing';
    if (isSilent) return 'Not reporting';
    return 'Protected';
  }

  /// Ranks devices by how badly a profile needs attention, so a profile with
  /// several devices can show the worst one rather than the last to report.
  int get severity {
    if (likelyRemoved || removalUnlocked) return 3;
    if (!allProtectionsOk) return 2;
    if (isSilent) return 1;
    return 0;
  }

  /// " · 12 Aug" — the day protection was switched off, when it is known.
  String _removedOn() {
    final at = adminChangedAt;
    if (at == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = at.toLocal();
    return ' · ${d.day} ${months[d.month - 1]}';
  }

  /// What to print next to the status. Falls back to the raw version name for
  /// devices that predate the reported label.
  String get versionLabel {
    if (appVersionLabel.isNotEmpty) return appVersionLabel;
    final name = appVersionName;
    return (name == null || name.isEmpty) ? '' : 'v$name';
  }

  static Device fromDoc(String id, Map<String, dynamic> m) {
    final rawProt = m['protections'];
    final rawCaps = m['capabilities'];
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
      // Absent on devices that predate the marker; assume intact rather than
      // crying wolf on every existing install.
      adminActive: m['adminActive'] != false,
      adminChangedAt: (m['adminChangedAt'] as Timestamp?)?.toDate(),
      protections: {
        if (rawProt is Map)
          for (final e in rawProt.entries) e.key.toString(): e.value == true,
      },
      capabilities: {
        if (rawCaps is Map)
          for (final e in rawCaps.entries) e.key.toString(): e.value == true,
      },
      lastError: m['lastError'] as String?,
      lastErrorAt: (m['lastErrorAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// The feature keys a device may declare, matching what the agents report.
class DeviceFeature {
  static const calls = 'calls';
  static const sms = 'sms';
  static const chats = 'chats';
  static const youtube = 'youtube';
  static const webHistory = 'webHistory';
  static const appBlocking = 'appBlocking';
  static const location = 'location';

  /// True when any of a profile's devices can report [feature]. A profile with
  /// no devices supports everything, so an unpaired child still shows the full
  /// set rather than an empty screen.
  static bool supportedBy(Iterable<Device> devices, String feature) =>
      devices.isEmpty || devices.any((d) => d.supports(feature));
}

/// The single status a profile shows when it holds more than one device.
///
/// Every device writes its own state, but they all also stamp the profile
/// document, so the last one to report used to decide what the parent saw — a
/// laptop with a permission off could be hidden behind a healthy phone.
class ProfileStatus {
  /// The device a parent should be told about first, or null when there is none.
  static Device? worst(Iterable<Device> devices) {
    Device? worst;
    for (final d in devices) {
      if (worst == null || d.severity > worst.severity) worst = d;
    }
    return worst;
  }

  /// The first device with something the parent can act on.
  static Device? faulty(Iterable<Device> devices) {
    final w = worst(devices);
    return (w != null && w.severity > 0) ? w : null;
  }
}

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Kinds of alert surfaced to the guardian.
enum AlertType {
  blockedApp,
  blockedWebsite,
  protectionOff,
  permissionRemoved,
  secureModeOn,
  secureModeOff,
  appInstalled,
  unknown,
}

/// Parses the string `type` stored on an alert document.
AlertType alertTypeFromId(String? id) => switch (id) {
      'blockedApp' => AlertType.blockedApp,
      'blockedWebsite' => AlertType.blockedWebsite,
      'protectionOff' => AlertType.protectionOff,
      'permissionRemoved' => AlertType.permissionRemoved,
      'secureModeOn' => AlertType.secureModeOn,
      'secureModeOff' => AlertType.secureModeOff,
      'appInstalled' => AlertType.appInstalled,
      _ => AlertType.unknown,
    };

/// A short human "x minutes ago" style label for an alert time.
String timeAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${at.day}/${at.month}';
}

extension AlertTypeUi on AlertType {
  String get label => switch (this) {
        AlertType.blockedApp => 'Blocked app opened',
        AlertType.blockedWebsite => 'Blocked website',
        AlertType.protectionOff => 'Protection was turned off',
        AlertType.permissionRemoved => 'Permission removed',
        AlertType.secureModeOn => 'Entered Secure App Mode',
        AlertType.secureModeOff => 'Returned to normal',
        AlertType.appInstalled => 'New app installed',
        AlertType.unknown => 'Alert',
      };

  IconData get icon => switch (this) {
        AlertType.blockedApp => Icons.block_rounded,
        AlertType.blockedWebsite => Icons.public_off_rounded,
        AlertType.protectionOff => Icons.gpp_bad_rounded,
        AlertType.permissionRemoved => Icons.remove_moderator_rounded,
        AlertType.secureModeOn => Icons.lock_rounded,
        AlertType.secureModeOff => Icons.lock_open_rounded,
        AlertType.appInstalled => Icons.download_rounded,
        AlertType.unknown => Icons.notifications_rounded,
      };

  Color get color => switch (this) {
        AlertType.blockedApp => AppColors.danger,
        AlertType.blockedWebsite => AppColors.danger,
        AlertType.protectionOff => AppColors.danger,
        AlertType.permissionRemoved => AppColors.warning,
        AlertType.secureModeOn => AppColors.primary,
        AlertType.secureModeOff => AppColors.success,
        AlertType.appInstalled => AppColors.info,
        AlertType.unknown => AppColors.info,
      };
}

class Alert {
  final AlertType type;
  final String detail;
  final String timeAgo;
  const Alert(this.type, this.detail, this.timeAgo);
}

/// One day's total screen time (minutes) for the weekly bar chart.
class DailyUsage {
  final String dayLabel; // Mon, Tue, ...
  final int minutes;
  const DailyUsage(this.dayLabel, this.minutes);
}

const demoWeekUsage = <DailyUsage>[
  DailyUsage('Mon', 95),
  DailyUsage('Tue', 140),
  DailyUsage('Wed', 60),
  DailyUsage('Thu', 175),
  DailyUsage('Fri', 210),
  DailyUsage('Sat', 240),
  DailyUsage('Sun', 130),
];

const demoAlerts = <Alert>[
  Alert(AlertType.blockedApp, 'Tried to open TikTok', '10:15 AM'),
  Alert(AlertType.blockedWebsite, 'Blocked badsite.com', '3:05 PM'),
  Alert(AlertType.secureModeOn, 'Started using a banking app', '1:20 PM'),
  Alert(AlertType.secureModeOff, 'Back to normal protection', '1:34 PM'),
  Alert(AlertType.appInstalled, 'Installed Instagram', '11:02 AM'),
  Alert(AlertType.protectionOff, 'Monitoring was turned off', '9:48 AM'),
];

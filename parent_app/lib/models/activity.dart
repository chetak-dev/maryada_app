import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Kinds of alert surfaced to the guardian. Deliberately narrow: a blocked
/// website, unsafe content the child met in a chat or a video, or a
/// tamper/removal attempt.
enum AlertType {
  blockedWebsite,
  unsafeMessage,
  unsafeVideo,
  tamper,
  unknown,
}

/// Parses the string `type` stored on an alert document (with a couple of
/// legacy tamper-ish types mapped to [AlertType.tamper]).
AlertType alertTypeFromId(String? id) => switch (id) {
  'blockedWebsite' => AlertType.blockedWebsite,
  'unsafeMessage' => AlertType.unsafeMessage,
  'unsafeVideo' => AlertType.unsafeVideo,
  'tamper' || 'protectionOff' || 'protection_disabled' || 'secureModeOn' =>
    AlertType.tamper,
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
    AlertType.blockedWebsite => 'Blocked website',
    AlertType.unsafeMessage => 'Unsafe message',
    AlertType.unsafeVideo => 'Unsafe video',
    AlertType.tamper => 'App tampering',
    AlertType.unknown => 'Alert',
  };

  IconData get icon => switch (this) {
    AlertType.blockedWebsite => Icons.public_off_rounded,
    AlertType.unsafeMessage => Icons.forum_rounded,
    AlertType.unsafeVideo => Icons.smart_display_rounded,
    AlertType.tamper => Icons.gpp_bad_rounded,
    AlertType.unknown => Icons.notifications_rounded,
  };

  Color get color => switch (this) {
    AlertType.blockedWebsite => AppColors.danger,
    AlertType.unsafeMessage => AppColors.warning,
    AlertType.unsafeVideo => AppColors.warning,
    AlertType.tamper => AppColors.danger,
    AlertType.unknown => AppColors.info,
  };

  /// The website was stopped; a message or a video had already been seen by the
  /// time it was read, so saying "blocked" would be a lie.
  bool get wasBlocked =>
      this == AlertType.blockedWebsite || this == AlertType.tamper;
}

class Alert {
  final AlertType type;
  final String detail;
  final String timeAgo;
  final String childId;

  /// The reporting device's parent-given name, so a family with several
  /// devices can tell which one raised the alert. Empty on old alerts.
  final String deviceName;

  /// What kind of unsafe content, e.g. 'adult' or 'gambling'. Empty when the
  /// term came from a parent's own keyword list, which has no category.
  final String category;

  const Alert(
    this.type,
    this.detail,
    this.timeAgo, {
    this.childId = '',
    this.deviceName = '',
    this.category = '',
  });
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
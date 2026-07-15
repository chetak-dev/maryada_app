import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Kinds of alert surfaced to the guardian.
enum AlertType {
  geofenceEnter,
  geofenceExit,
  blockedApp,
  blockedWebsite,
  screenTimeReached,
  appInstalled,
  lowBattery,
}

extension AlertTypeUi on AlertType {
  String get label => switch (this) {
        AlertType.geofenceEnter => 'Arrived at a place',
        AlertType.geofenceExit => 'Left a place',
        AlertType.blockedApp => 'Blocked app opened',
        AlertType.blockedWebsite => 'Blocked website',
        AlertType.screenTimeReached => 'Screen-time limit reached',
        AlertType.appInstalled => 'New app installed',
        AlertType.lowBattery => 'Low battery',
      };

  IconData get icon => switch (this) {
        AlertType.geofenceEnter => Icons.login_rounded,
        AlertType.geofenceExit => Icons.logout_rounded,
        AlertType.blockedApp => Icons.block_rounded,
        AlertType.blockedWebsite => Icons.public_off_rounded,
        AlertType.screenTimeReached => Icons.timelapse_rounded,
        AlertType.appInstalled => Icons.download_rounded,
        AlertType.lowBattery => Icons.battery_alert_rounded,
      };

  Color get color => switch (this) {
        AlertType.geofenceEnter => AppColors.accent,
        AlertType.geofenceExit => AppColors.info,
        AlertType.blockedApp => AppColors.danger,
        AlertType.blockedWebsite => AppColors.danger,
        AlertType.screenTimeReached => AppColors.warning,
        AlertType.appInstalled => AppColors.primary,
        AlertType.lowBattery => AppColors.warning,
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
  Alert(AlertType.geofenceEnter, 'Arrived at School', '8:42 AM'),
  Alert(AlertType.blockedApp, 'Tried to open TikTok', '10:15 AM'),
  Alert(AlertType.screenTimeReached, 'Daily limit reached', '1:20 PM'),
  Alert(AlertType.blockedWebsite, 'Blocked badsite.com', '3:05 PM'),
  Alert(AlertType.geofenceExit, 'Left School', '3:30 PM'),
  Alert(AlertType.lowBattery, 'Battery at 15%', '6:48 PM'),
];

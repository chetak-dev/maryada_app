import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../models/activity.dart';
import '../../theme/tokens.dart';

/// Recent notable events across the family — geofence, blocks, screen-time and
/// battery alerts. Live alert history isn't wired to a backend collection yet,
/// so when connected we show a friendly empty state; in demo mode we show
/// representative sample alerts.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, this.uid});

  final String? uid;

  bool get _live => uid != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: _live
          ? _EmptyAlerts()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
              children: [
                for (var i = 0; i < demoAlerts.length; i++) ...[
                  _AlertCard(alert: demoAlerts[i]),
                  if (i < demoAlerts.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded,
                  color: AppColors.success, size: 40),
            ),
            const SizedBox(height: AppSpacing.md),
            Text("You're all caught up",
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'New alerts about your family will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final Alert alert;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: alert.type.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(alert.type.icon, color: alert.type.color, size: 22),
        ),
        title: Text(alert.type.label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(alert.detail),
        trailing: Text(alert.timeAgo,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ),
    );
  }
}

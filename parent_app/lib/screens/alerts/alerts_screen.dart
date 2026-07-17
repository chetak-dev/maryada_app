import 'package:flutter/material.dart';

import '../../data/alerts_repository.dart';
import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../models/activity.dart';
import '../../models/family.dart';
import '../../theme/tokens.dart';

/// Recent notable events across the family — blocked apps/sites, tamper
/// (protection turned off), Secure App Mode changes and new installs. Reads
/// the live `families/{id}/alerts` feed when connected; shows sample alerts in
/// demo mode.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, this.uid});

  final String? uid;

  bool get _live => uid != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: _live ? _LiveAlerts(uid: uid!) : _demoList(),
    );
  }

  Widget _demoList() => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          for (var i = 0; i < demoAlerts.length; i++) ...[
            _AlertCard(alert: demoAlerts[i]),
            if (i < demoAlerts.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
}

/// Resolves the guardian's first family, then streams its alert feed.
class _LiveAlerts extends StatelessWidget {
  const _LiveAlerts({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FamilyModel>>(
      stream: FamilyRepository.instance.watchFamilies(uid),
      builder: (context, famSnap) {
        if (famSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final families = famSnap.data ?? const <FamilyModel>[];
        if (families.isEmpty) return _EmptyAlerts();
        return StreamBuilder<List<Alert>>(
          stream: AlertsRepository.instance.watch(families.first.id),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final alerts = snap.data ?? const <Alert>[];
            if (alerts.isEmpty) return _EmptyAlerts();
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md,
                  AppSpacing.md, AppSpacing.xxl),
              children: [
                for (var i = 0; i < alerts.length; i++) ...[
                  _AlertCard(alert: alerts[i]),
                  if (i < alerts.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        );
      },
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

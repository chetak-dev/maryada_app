import 'package:flutter/material.dart';

import '../../data/alerts_repository.dart';
import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../models/activity.dart';
import '../../models/child.dart';
import '../../theme/tokens.dart';
import '../../widgets/profile_button.dart';
import '../../widgets/theme_toggle_button.dart';

/// Recent notable events — only a blocked website visit or an app-tampering /
/// removal attempt. Alerts are grouped under each child (collapsed by default).
/// Shows real alerts from the live `families/{id}/alerts` feed only.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, this.uid});

  final String? uid;

  bool get _live => uid != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: const [
          ThemeToggleButton(),
          ProfileButton(),
          SizedBox(width: AppSpacing.xs)
        ],
      ),
      body: _live ? _LiveAlerts(uid: uid!) : _EmptyAlerts(),
    );
  }
}

/// Resolves the guardian's granted family, then streams its children (for
/// names) and its alert feed, grouped per child.
class _LiveAlerts extends StatelessWidget {
  const _LiveAlerts({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: FamilyRepository.instance.watchMyFamilyId(uid),
      builder: (context, famSnap) {
        if (famSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final familyId = famSnap.data ?? '';
        if (familyId.isEmpty) return _EmptyAlerts();
        return StreamBuilder<List<Child>>(
          stream: FamilyRepository.instance.watchChildren(familyId),
          builder: (context, kidSnap) {
            final names = <String, String>{
              for (final c in (kidSnap.data ?? const <Child>[])) c.id: c.name,
            };
            return StreamBuilder<List<Alert>>(
              stream: AlertsRepository.instance.watch(familyId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Tamper events are surfaced on the device/profile screens, not
                // here — parents asked to keep this list to content alerts only.
                final relevant = (snap.data ?? const <Alert>[])
                    .where((a) =>
                        a.type != AlertType.unknown && a.type != AlertType.tamper)
                    .toList();
                if (relevant.isEmpty) return _EmptyAlerts();
                return _GroupedAlerts(
                  alerts: relevant,
                  nameFor: (id) => names[id] ?? 'Device',
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Renders alerts grouped under each child's name, children ordered by their
/// most recent alert (the incoming list is newest-first).
class _GroupedAlerts extends StatelessWidget {
  const _GroupedAlerts({required this.alerts, required this.nameFor});
  final List<Alert> alerts;
  final String Function(String childId) nameFor;

  @override
  Widget build(BuildContext context) {
    final order = <String>[];
    final byChild = <String, List<Alert>>{};
    for (final a in alerts) {
      byChild.putIfAbsent(a.childId, () {
        order.add(a.childId);
        return <Alert>[];
      }).add(a);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
      children: [
        for (final childId in order) ...[
          _ChildAlertsCard(
            name: nameFor(childId),
            alerts: byChild[childId]!,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// One child's alerts as a collapsible card (collapsed by default).
class _ChildAlertsCard extends StatelessWidget {
  const _ChildAlertsCard({required this.name, required this.alerts});
  final String name;
  final List<Alert> alerts;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.only(
              left: AppSpacing.md, right: AppSpacing.md, bottom: AppSpacing.sm),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child:
                const Icon(Icons.person_rounded, color: AppColors.primary),
          ),
          title: Text(name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${alerts.length} alert${alerts.length == 1 ? '' : 's'}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          children: [
            for (final a in alerts) _AlertRow(alert: a),
          ],
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});
  final Alert alert;

  @override
  Widget build(BuildContext context) {
    // Profile groups the card; the row names the exact device that reported.
    final meta = [
      if (alert.detail.isNotEmpty) alert.detail,
      if (alert.deviceName.isNotEmpty) 'Device: ${alert.deviceName}',
    ].join('\n');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: alert.type.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(alert.type.icon, color: alert.type.color, size: 20),
      ),
      title: Text(alert.type.label,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: meta.isEmpty ? null : Text(meta),
      trailing: Text(alert.timeAgo,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
                  ?.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

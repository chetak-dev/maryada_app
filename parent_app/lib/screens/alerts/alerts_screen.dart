import 'package:flutter/material.dart';

import '../../data/alerts_repository.dart';
import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../models/activity.dart';
import '../../models/child.dart';
import '../../models/family.dart';
import '../../theme/tokens.dart';

/// Recent notable events — only a blocked website visit or an app-tampering /
/// removal attempt. Alerts are grouped under each child's name. Reads the live
/// `families/{id}/alerts` feed when connected; shows sample alerts in demo mode.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, this.uid});

  final String? uid;

  bool get _live => uid != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: _live ? _LiveAlerts(uid: uid!) : _demoBody(),
    );
  }

  Widget _demoBody() {
    final relevant =
        demoAlerts.where((a) => a.type != AlertType.unknown).toList();
    if (relevant.isEmpty) return _EmptyAlerts();
    return _GroupedAlerts(
      alerts: relevant,
      nameFor: (id) => demoAlertChildNames[id] ?? 'Child',
    );
  }
}

/// Resolves the guardian's first family, then streams its children (for names)
/// and its alert feed, grouped per child.
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
        final familyId = families.first.id;
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
                final relevant = (snap.data ?? const <Alert>[])
                    .where((a) => a.type != AlertType.unknown)
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
          _ChildHeader(
              name: nameFor(childId), count: byChild[childId]!.length),
          const SizedBox(height: AppSpacing.sm),
          for (final a in byChild[childId]!) ...[
            _AlertCard(alert: a),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _ChildHeader extends StatelessWidget {
  const _ChildHeader({required this.name, required this.count});
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.person_rounded, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text('$count',
              style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ),
      ],
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

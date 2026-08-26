import 'package:flutter/material.dart';

import '../../data/alerts_repository.dart';
import '../../data/db.dart';
import '../../data/family_repository.dart';
import '../../models/activity.dart';
import '../../models/child.dart';
import '../../theme/tokens.dart';
import '../../widgets/profile_button.dart';
import '../../widgets/theme_toggle_button.dart';

/// Recent notable events — a blocked website, or unsafe content the child met
/// in a chat or a video. Shown newest-first across the whole family, filterable
/// by kind. Shows real alerts from the live `families/{id}/alerts` feed only.
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
                return _AlertFeed(
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

/// What the feed is narrowed to. Alerts are worth acting on in different ways —
/// a blocked site is handled, a message the child actually received is not.
enum _Filter { all, websites, messages, videos }

extension on _Filter {
  String get label => switch (this) {
    _Filter.all => 'All',
    _Filter.websites => 'Websites',
    _Filter.messages => 'Messages',
    _Filter.videos => 'Videos',
  };

  bool matches(Alert a) => switch (this) {
    _Filter.all => true,
    _Filter.websites => a.type == AlertType.blockedWebsite,
    _Filter.messages => a.type == AlertType.unsafeMessage,
    _Filter.videos => a.type == AlertType.unsafeVideo,
  };
}

/// A flat, newest-first feed across the whole family.
///
/// These used to be collapsed under one card per child, so nothing at all was
/// visible until a parent tapped a name — and with fifty profiles the newest
/// alert could be several taps deep. Time order is what matters here; the
/// child's name rides on each row instead.
class _AlertFeed extends StatefulWidget {
  const _AlertFeed({required this.alerts, required this.nameFor});
  final List<Alert> alerts;
  final String Function(String childId) nameFor;

  @override
  State<_AlertFeed> createState() => _AlertFeedState();
}

class _AlertFeedState extends State<_AlertFeed> {
  _Filter _filter = _Filter.all;

  int _countFor(_Filter f) => widget.alerts.where(f.matches).length;

  @override
  Widget build(BuildContext context) {
    final visible = widget.alerts.where(_filter.matches).toList();
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: Text('${f.label} (${_countFor(f)})'),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _EmptyAlerts()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xxl,
                  ),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _AlertCard(
                    alert: visible[i],
                    childName: widget.nameFor(visible[i].childId),
                  ),
                ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.childName});
  final Alert alert;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final color = alert.type.color;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(alert.type.icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        childName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      alert.timeAgo,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Pill(
                      text: alert.type.label,
                      color: color,
                      // Only say "blocked" when it actually was.
                      icon: alert.type.wasBlocked
                          ? Icons.block_rounded
                          : Icons.visibility_rounded,
                    ),
                    if (alert.category.isNotEmpty)
                      _Pill(text: alert.category, color: AppColors.textMuted),
                  ],
                ),
                if (alert.detail.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    alert.detail,
                    style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 13,
                    ),
                  ),
                ],
                if (alert.deviceName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    alert.deviceName,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
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
                  ?.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

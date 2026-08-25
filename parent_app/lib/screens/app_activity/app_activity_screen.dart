import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/usage_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_state.dart';

/// How long the child spent in each app, from the screen-time their device
/// reports. The data was already being collected and uploaded; nothing in the
/// parent app ever showed it.
class AppActivityScreen extends StatefulWidget {
  const AppActivityScreen({
    super.key,
    this.childName,
    this.familyId,
    this.childId,
    this.deviceId,
    this.deviceLabel,
  });

  final String? childName;
  final String? familyId;
  final String? childId;

  /// When set, only this device's screen time is shown.
  final String? deviceId;
  final String? deviceLabel;

  @override
  State<AppActivityScreen> createState() => _AppActivityScreenState();
}

class _AppActivityScreenState extends State<AppActivityScreen> {
  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  // Built once: rebuilding the stream inside build() would re-subscribe on
  // every frame and flash the spinner.
  late final Stream<UsageSummary?>? _stream = _live
      ? UsageRepository.instance.watch(
          widget.familyId!,
          widget.childId!,
          deviceId: widget.deviceId,
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final title = widget.childName == null
        ? 'App activity'
        : 'App activity · ${widget.childName}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: !_live
          ? const EmptyState(
              icon: Icons.phonelink_off_rounded,
              title: 'No device connected',
              message: 'Pair a device to start seeing app activity here.',
            )
          : StreamBuilder<UsageSummary?>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Couldn’t load app activity',
                    message: 'Check your connection and try again.',
                  );
                }
                final usage = snap.data;
                if (usage == null || usage.isEmpty) {
                  return const EmptyState(
                    icon: Icons.hourglass_empty_rounded,
                    title: 'Nothing reported yet',
                    message:
                        'Screen time appears once the device has been used '
                        'with Usage access granted.',
                  );
                }
                return _UsageView(
                  usage: usage,
                  deviceLabel: widget.deviceLabel,
                );
              },
            ),
    );
  }
}

class _UsageView extends StatelessWidget {
  const _UsageView({required this.usage, this.deviceLabel});

  final UsageSummary usage;
  final String? deviceLabel;

  @override
  Widget build(BuildContext context) {
    // The child reports the last seven days oldest-first, so today is last.
    final today = usage.week.isEmpty ? 0 : usage.week.last.minutes;
    final weekTotal = usage.week.fold<int>(0, (sum, d) => sum + d.minutes);
    final average = usage.week.isEmpty ? 0 : weekTotal ~/ usage.week.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        _SummaryCard(
          today: today,
          weekTotal: weekTotal,
          average: average,
          deviceLabel: deviceLabel,
        ),
        if (usage.week.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('LAST 7 DAYS'),
          const SizedBox(height: AppSpacing.sm),
          _WeekChart(week: usage.week),
        ],
        if (usage.topApps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('MOST USED TODAY'),
          const SizedBox(height: AppSpacing.sm),
          _AppList(apps: usage.topApps),
        ],
        if (usage.updatedAt != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Reported ${_ago(usage.updatedAt!)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

String _duration(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.today,
    required this.weekTotal,
    required this.average,
    this.deviceLabel,
  });

  final int today;
  final int weekTotal;
  final int average;
  final String? deviceLabel;

  @override
  Widget build(BuildContext context) {
    final device = deviceLabel;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Screen time today',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (device != null && device.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      device,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            today <= 0 ? '—' : _duration(today),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _Stat(label: 'This week', value: _duration(weekTotal)),
              _Stat(label: 'Daily average', value: _duration(average)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondaryOf(context),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.week});
  final List<DayUsage> week;

  @override
  Widget build(BuildContext context) {
    final peak = week.fold<int>(1, (m, d) => d.minutes > m ? d.minutes : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: AppShadow.card,
      ),
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < week.length; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      week[i].minutes <= 0 ? '' : _duration(week[i].minutes),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 4 + 72 * (week[i].minutes / peak),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        // Today is the bar a parent looks for first.
                        color: i == week.length - 1
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      week[i].day,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppList extends StatelessWidget {
  const _AppList({required this.apps});
  final List<AppUsage> apps;

  @override
  Widget build(BuildContext context) {
    final peak = apps.fold<int>(1, (m, a) => a.minutes > m ? a.minutes : m);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < apps.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        apps[i].appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _duration(apps[i].minutes),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: apps[i].minutes / peak,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceMutedOf(context),
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/web_history_repository.dart';
import '../../theme/tokens.dart';

/// Activity & reports: a weekly screen-time bar chart and today's most-used
/// apps. Uses real reported usage when [familyId]/[childId] are set and the
/// child has granted usage access; otherwise shows sample data.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.childName, this.familyId, this.childId});

  final String? childName;
  final String? familyId;
  final String? childId;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    final title = widget.childName == null
        ? 'Website Visits'
        : 'Website Visits · ${widget.childName}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          if (_live)
            _WebHistorySection(
                familyId: widget.familyId!, childId: widget.childId!),
        ],
      ),
    );
  }
}

class _WebHistorySection extends StatefulWidget {
  const _WebHistorySection({required this.familyId, required this.childId});
  final String familyId;
  final String childId;

  @override
  State<_WebHistorySection> createState() => _WebHistorySectionState();
}

class _WebHistorySectionState extends State<_WebHistorySection> {
  int _period = 0; // 0 = Today, 1 = Last week, 2 = This month

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebHistory>(
      stream: WebHistoryRepository.instance
          .watch(widget.familyId, widget.childId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final history = snap.data ?? const WebHistory();
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final weekAgo = now.subtract(const Duration(days: 7));
        bool isToday(WebVisit v) => v.at != null && !v.at!.isBefore(startOfToday);
        bool isLastWeek(WebVisit v) =>
            v.at != null && v.at!.isBefore(startOfToday) && v.at!.isAfter(weekAgo);
        final visitedToday = history.visited.where(isToday).toList();
        final visitedWeek = history.visited.where(isLastWeek).toList();
        final visitedMonth = history.visited
            .where((v) => !isToday(v) && !isLastWeek(v))
            .toList();
        final selected =
            [visitedToday, visitedWeek, visitedMonth][_period];
        final emptyText =
            ['None today.', 'None this week.', 'None earlier.'][_period];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Websites visited',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _PeriodSelector(
              selected: _period,
              onChanged: (i) => setState(() => _period = i),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DomainCard(
              domains: selected,
              emptyText: emptyText,
              blocked: false,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Blocked websites',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _DomainCard(
              domains: history.blocked,
              emptyText: 'No blocked sites yet.',
              blocked: true,
            ),
          ],
        );
      },
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Today')),
          ButtonSegment(value: 1, label: Text('Last week')),
          ButtonSegment(value: 2, label: Text('This month')),
        ],
        selected: {selected},
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
            Theme.of(context).textTheme.bodySmall,
          ),
        ),
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _DomainCard extends StatelessWidget {
  const _DomainCard({
    required this.domains,
    required this.emptyText,
    required this.blocked,
  });
  final List<WebVisit> domains;
  final String emptyText;
  final bool blocked;

  static String _when(DateTime? t) {
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  static String _spent(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String? _subtitle(WebVisit v) {
    if (blocked) {
      if (v.count <= 0) return null;
      return v.count == 1 ? '1 attempt' : '${v.count} attempts';
    }
    final parts = <String>[];
    if (v.timeSpent.inSeconds > 0) parts.add('${_spent(v.timeSpent)} spent');
    if (v.count > 1) parts.add('${v.count} visits');
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    if (domains.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(emptyText,
              style: const TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    final color = blocked ? AppColors.danger : AppColors.primary;
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < domains.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              leading: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  blocked ? Icons.public_off_rounded : Icons.public_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              title: Text(domains[i].domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: _subtitle(domains[i]) == null
                  ? null
                  : Text(_subtitle(domains[i])!,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
              trailing: Text(_when(domains[i].at),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

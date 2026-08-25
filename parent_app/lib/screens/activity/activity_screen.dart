import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/web_history_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_state.dart';

/// What a child did on the web, newest first.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({
    super.key,
    this.childName,
    this.familyId,
    this.childId,
    this.deviceId,
    this.platform,
  });

  final String? childName;
  final String? familyId;
  final String? childId;

  /// When set, only this device's records are shown.
  final String? deviceId;
  final String? platform;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    final title = widget.childName == null
        ? 'Web activity'
        : 'Web activity · ${widget.childName}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: !_live
          ? const EmptyState(
              icon: Icons.phonelink_off_rounded,
              title: 'No device connected',
              message: 'Pair a device to start seeing web activity here.',
            )
          : _WebActivityView(
              familyId: widget.familyId!,
              childId: widget.childId!,
              deviceId: widget.deviceId,
              platform: widget.platform,
            ),
    );
  }
}

/// One row of the timeline. Searches, visits and blocks are different kinds of
/// the same event, so they share a shape and sort together.
class _Entry {
  const _Entry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.at,
    this.tag = '',
  });

  final _Kind kind;
  final String title;
  final String subtitle;
  final DateTime? at;

  /// Why a site was blocked, already in parent-facing words.
  final String tag;
}

enum _Kind { search, site, blocked }

enum _Filter { all, searches, sites, blocked }

extension on _Filter {
  bool accepts(_Kind kind) => switch (this) {
    _Filter.all => true,
    _Filter.searches => kind == _Kind.search,
    _Filter.sites => kind == _Kind.site,
    _Filter.blocked => kind == _Kind.blocked,
  };
}

String _clock(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

String _short(Duration d) {
  if (d.inMilliseconds > 0 && d.inSeconds == 0) return '<1s';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// The tags shown against a block. Anything else — the parent's own list, or a
/// device on an older build — is "Others".
const _reasonLabels = <String, String>{
  'adult': 'Porn',
  'gambling': 'Gambling',
  'drugs': 'Drugs',
  'social': 'Social media',
  'malware': 'Malware',
  'phishing': 'Phishing',
  'weapons': 'Weapons',
  'violence': 'Violence',
  'youtube': 'YouTube',
  'content': 'Unsafe content',
  'keyword': 'Blocked word',
  'blocklist': 'Your block list',
};

class _WebActivityView extends StatefulWidget {
  const _WebActivityView({
    required this.familyId,
    required this.childId,
    this.deviceId,
    this.platform,
  });
  final String familyId;
  final String childId;
  final String? deviceId;
  final String? platform;

  @override
  State<_WebActivityView> createState() => _WebActivityViewState();
}

class _WebActivityViewState extends State<_WebActivityView> {
  _Filter _filter = _Filter.all;

  /// Days back to show; 0 is every day the devices still hold.
  int _days = 0;

  // Built once: re-creating it inside build() re-subscribes on every setState,
  // which flashes the loading spinner each time a filter is tapped.
  late final Stream<WebHistory> _stream = WebHistoryRepository.instance.watch(
    widget.familyId,
    widget.childId,
    deviceId: widget.deviceId,
    platform: widget.platform,
  );

  bool _inPeriod(DateTime? at) {
    if (at == null) return false;
    if (_days == 0) return true;
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: _days - 1));
    return !at.isBefore(start);
  }

  static bool _isToday(DateTime? at) {
    if (at == null) return false;
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  // Building and sorting the timeline is the expensive part, and it doesn't
  // depend on the filter — doing it inside build() made every filter tap
  // re-sort the whole history before the tile could highlight.
  WebHistory? _cachedFor;
  int? _cachedDays;
  late List<_Entry> _allEntries;
  late Duration _todayTime;
  late int _searchCount;
  late int _siteCount;
  late int _blockCount;

  void _rebuild(WebHistory history) {
    if (identical(_cachedFor, history) && _cachedDays == _days) return;
    _cachedFor = history;
    _cachedDays = _days;

    // Searches typed into the YouTube app belong to the YouTube screen; this
    // one is about the browser.
    final searches = history.searches
        .where((s) => s.engine.toLowerCase() != 'youtube')
        .where((s) => _inPeriod(s.at))
        .toList();
    final visited = history.visited.where((v) => _inPeriod(v.at)).toList();
    final blocked = history.blocked.where((b) => _inPeriod(b.at)).toList();

    _searchCount = searches.length;
    _siteCount = visited.length;
    _blockCount = blocked.fold<int>(0, (sum, b) => sum + b.count);
    // The headline is always today, whatever period the list shows: a running
    // month-long total answers no question a parent actually asks.
    _todayTime = history.visited
        .where((v) => _isToday(v.at))
        .fold(Duration.zero, (sum, v) => sum + v.timeSpent);

    _allEntries =
        <_Entry>[
          for (final s in searches)
            _Entry(
              kind: _Kind.search,
              title: s.query,
              subtitle: s.engine,
              at: s.at,
            ),
          for (final v in visited)
            _Entry(
              kind: _Kind.site,
              title: v.domain,
              subtitle: [
                if (v.timeSpent.inMilliseconds > 0) _short(v.timeSpent),
                if (v.count > 1) '${v.count} visits',
              ].join('  ·  '),
              at: v.at,
            ),
          for (final b in blocked)
            _Entry(
              kind: _Kind.blocked,
              title: b.domain,
              subtitle: b.count == 1 ? 'Blocked' : 'Blocked ${b.count} times',
              at: b.at,
              tag: _reasonLabels[b.reason] ?? 'Others',
            ),
        ]..sort(
          (a, b) => (b.at?.millisecondsSinceEpoch ?? 0).compareTo(
            a.at?.millisecondsSinceEpoch ?? 0,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebHistory>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load activity',
            message: 'Check your connection and try again.',
          );
        }

        _rebuild(snap.data ?? const WebHistory());
        final entries = _allEntries
            .where((e) => _filter.accepts(e.kind))
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            _SummaryCard(
              total: _todayTime,
              days: _days,
              onDays: (d) => setState(() => _days = d),
              searches: _searchCount,
              sites: _siteCount,
              blocked: _blockCount,
              filter: _filter,
              // Tapping the active stat clears it, so "all" needs no chip.
              onFilter: (f) =>
                  setState(() => _filter = _filter == f ? _Filter.all : f),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xl),
                child: EmptyState(
                  icon: Icons.travel_explore_rounded,
                  title: 'Nothing yet',
                  message: 'Web activity for this period will appear here.',
                ),
              )
            else
              ..._buildDays(entries),
          ],
        );
      },
    );
  }

  List<Widget> _buildDays(List<_Entry> entries) {
    final out = <Widget>[];
    var i = 0;
    while (i < entries.length) {
      final day = entries[i].at!;
      final group = <_Entry>[];
      while (i < entries.length && _sameDay(entries[i].at!, day)) {
        group.add(entries[i]);
        i++;
      }
      out
        ..add(_DayHeader(day: day, count: group.length))
        ..add(const SizedBox(height: AppSpacing.sm))
        ..add(_DayCard(entries: group))
        ..add(const SizedBox(height: AppSpacing.lg));
    }
    return out;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// The period's headline: how long the child browsed, and a breakdown that
/// doubles as the filter.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.days,
    required this.onDays,
    required this.searches,
    required this.sites,
    required this.blocked,
    required this.filter,
    required this.onFilter,
  });

  final Duration total;
  final int days;
  final ValueChanged<int> onDays;
  final int searches;
  final int sites;
  final int blocked;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  static String _periodLabel(int d) => switch (d) {
    0 => 'All history',
    1 => 'Today',
    7 => 'Last 7 days',
    _ => 'Last 30 days',
  };

  String get _headline {
    if (total.inSeconds < 1) return '—';
    final h = total.inHours;
    final m = total.inMinutes % 60;
    if (h > 0) return m == 0 ? '${h}h' : '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${total.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
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
                  'Today on the web',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              PopupMenuButton<int>(
                initialValue: days,
                onSelected: onDays,
                position: PopupMenuPosition.under,
                itemBuilder: (_) => [
                  for (final d in [0, 1, 7, 30])
                    PopupMenuItem(value: d, child: Text(_periodLabel(d))),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _periodLabel(days),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _headline,
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
              _Stat(
                value: searches,
                label: 'Searches',
                icon: Icons.search_rounded,
                active: filter == _Filter.searches,
                onTap: () => onFilter(_Filter.searches),
              ),
              _Stat(
                value: sites,
                label: 'Sites',
                icon: Icons.language_rounded,
                active: filter == _Filter.sites,
                onTap: () => onFilter(_Filter.sites),
              ),
              _Stat(
                value: blocked,
                label: 'Blocked',
                icon: Icons.shield_rounded,
                active: filter == _Filter.blocked,
                onTap: () => onFilter(_Filter.blocked),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final int value;
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      // Highlight on finger-down: InkWell's onTap only fires on release, which
      // read as the tile lagging behind the tap.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onTap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.20)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.75)),
              const SizedBox(width: 5),
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});
  final DateTime day;
  final int count;

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today
        .difference(DateTime(day.year, day.month, day.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${day.day} ${months[day.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            _label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondaryOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(height: 1, color: AppColors.borderOf(context)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.entries});
  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 68, right: AppSpacing.md),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderOf(context),
                ),
              ),
            _Row(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry});
  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final blocked = entry.kind == _Kind.blocked;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Badge(entry: entry),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                    height: 1.25,
                  ),
                ),
                if (entry.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (entry.tag.isNotEmpty) _Tag(label: entry.tag),
                      Text(
                        entry.subtitle,
                        style: TextStyle(
                          color: blocked
                              ? AppColors.danger
                              : AppColors.textSecondaryOf(context),
                          fontSize: 12.5,
                          fontWeight: blocked
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _clock(entry.at),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The category that triggered the block, so a parent sees *why* at a glance.
class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.danger,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Sites get a lettered tile keyed to the domain, so a parent recognises a
/// repeat visit at a glance instead of scanning identical globe icons.
class _Badge extends StatelessWidget {
  const _Badge({required this.entry});
  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.kind == _Kind.search) {
      return Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(
          Icons.search_rounded,
          color: AppColors.info,
          size: 20,
        ),
      );
    }

    final domain = entry.title.replaceFirst(RegExp(r'^www\.'), '');
    final letter = domain.isEmpty ? '?' : domain.substring(0, 1).toUpperCase();
    final tint = AppColors.avatarFor(domain);
    final isBlocked = entry.kind == _Kind.blocked;

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (isBlocked ? AppColors.textMuted : tint).withValues(
                alpha: 0.14,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              letter,
              style: TextStyle(
                color: isBlocked ? AppColors.textSecondaryOf(context) : tint,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isBlocked)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.surfaceOf(context),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

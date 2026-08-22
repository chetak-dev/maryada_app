import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/db.dart';
import '../../data/web_history_repository.dart';
import '../../data/youtube_history_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_state.dart';

const _ytRed = Color(0xFFFF0000);

/// Shows what a child does on YouTube: the videos they watch (captured from
/// the on-screen title) and every search they submit in the app.
class YoutubeHistoryScreen extends StatelessWidget {
  const YoutubeHistoryScreen({
    super.key,
    required this.childName,
    this.familyId,
    this.childId,
    this.deviceId,
  });

  final String childName;
  final String? familyId;
  final String? childId;

  /// When set, only this device's records are shown.
  final String? deviceId;

  bool get _live => familyId != null && childId != null && Db.ready;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('YouTube · $childName')),
      body: !_live
          ? const EmptyState(
              icon: Icons.play_circle_outline_rounded,
              title: 'No device connected',
              message: 'Connect a device to see YouTube activity.',
            )
          : _YoutubeActivityView(
              familyId: familyId!,
              childId: childId!,
              deviceId: deviceId,
            ),
    );
  }
}

/// One row of the timeline. Watched videos and searches are different kinds
/// of the same event, so they share a shape and sort together.
class _Entry {
  const _Entry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.at,
    this.meta = '',
    this.watchedSeconds = 0,
    this.openUrl,
  });

  final _Kind kind;
  final String title;
  final String subtitle;
  final DateTime? at;

  /// The watch time, on its own line under the channel.
  final String meta;
  final int watchedSeconds;

  /// Tapping the title launches this — videos only.
  final String? openUrl;
}

enum _Kind { video, search }

enum _Filter { all, videos, searches }

/// Newest first, or longest watched first.
enum _Sort { recent, watched }

extension on _Filter {
  bool accepts(_Kind kind) => switch (this) {
        _Filter.all => true,
        _Filter.videos => kind == _Kind.video,
        _Filter.searches => kind == _Kind.search,
      };
}

String _clock(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

/// "5m 12s watched" / "1h 3m watched", plus " of 1:04:50" when the child device
/// could read the video's length.
String _watchedLabel(int watched, int duration) {
  if (watched <= 0) return '';
  final h = watched ~/ 3600;
  final m = (watched % 3600) ~/ 60;
  final s = watched % 60;
  final base = h > 0
      ? '${h}h ${m}m watched'
      : m > 0
          ? '${m}m ${s}s watched'
          : '${s}s watched';
  if (duration <= 0) return base;
  return '$base of ${_clockDuration(duration)}';
}

/// A length the way YouTube writes it: 4:07, or 1:04:50 once past an hour.
String _clockDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

String _videoSubtitle(YoutubeVideo v) => v.channel;

class _YoutubeActivityView extends StatefulWidget {
  const _YoutubeActivityView({
    required this.familyId,
    required this.childId,
    this.deviceId,
  });
  final String familyId;
  final String childId;
  final String? deviceId;

  @override
  State<_YoutubeActivityView> createState() => _YoutubeActivityViewState();
}

class _YoutubeActivityViewState extends State<_YoutubeActivityView> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.recent;
  int _days = 1;

  // Built once: re-creating them inside build() re-subscribes on every
  // setState, which flashes the loading spinner each time a filter is tapped.
  late final Stream<List<YoutubeVideo>> _videosStream =
      YoutubeHistoryRepository.instance.watch(widget.familyId, widget.childId,
          deviceId: widget.deviceId);
  late final Stream<WebHistory> _webStream = WebHistoryRepository.instance
      .watch(widget.familyId, widget.childId, deviceId: widget.deviceId);

  bool _inPeriod(DateTime? at) {
    if (at == null) return false;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _days - 1));
    return !at.isBefore(start);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<YoutubeVideo>>(
      stream: _videosStream,
      builder: (context, videoSnap) => StreamBuilder<WebHistory>(
        stream: _webStream,
        builder: (context, webSnap) {
          if (videoSnap.connectionState == ConnectionState.waiting ||
              webSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (videoSnap.hasError || webSnap.hasError) {
            return const EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn’t load YouTube activity',
              message: 'Check your connection and try again.',
            );
          }

          final videos = (videoSnap.data ?? const <YoutubeVideo>[])
              .where((v) => _inPeriod(v.at))
              .toList();
          // The child app records searches submitted in the YouTube app into
          // web history with engine == 'YouTube'.
          final searches = (webSnap.data?.searches ?? const <WebSearch>[])
              .where((s) => s.engine.toLowerCase() == 'youtube')
              .where((s) => _inPeriod(s.at))
              .toList();

          final total = videos.fold(Duration.zero,
              (sum, v) => sum + Duration(seconds: v.watchedSeconds));

          final entries = <_Entry>[
            for (final v in videos)
              _Entry(
                kind: _Kind.video,
                title: v.title,
                subtitle: _videoSubtitle(v),
                meta: _watchedLabel(v.watchedSeconds, v.durationSeconds),
                watchedSeconds: v.watchedSeconds,
                at: v.at,
                openUrl: v.searchUrl,
              ),
            for (final s in searches)
              _Entry(
                kind: _Kind.search,
                title: s.query,
                subtitle: 'Searched on YouTube',
                at: s.at,
              ),
          ]..sort((a, b) => (b.at?.millisecondsSinceEpoch ?? 0)
              .compareTo(a.at?.millisecondsSinceEpoch ?? 0));

          final shown =
              entries.where((e) => _filter.accepts(e.kind)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
            children: [
              _SummaryCard(
                total: total,
                days: _days,
                onDays: (d) => setState(() => _days = d),
                sort: _sort,
                onSort: (s) => setState(() => _sort = s),
                videos: videos.length,
                searches: searches.length,
                filter: _filter,
                // Tapping the active stat clears it, so "all" needs no chip.
                onFilter: (f) => setState(
                    () => _filter = _filter == f ? _Filter.all : f),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyState(
                    icon: Icons.play_circle_outline_rounded,
                    title: 'Nothing yet',
                    message:
                        'YouTube activity for this period will appear here.',
                  ),
                )
              else if (_sort == _Sort.watched)
                ..._buildMostWatched(shown)
              else
                ..._buildDays(shown),
            ],
          );
        },
      ),
    );
  }

  /// Longest watched first, as one list — day headers make no sense here.
  /// Searches carry no watch time, so they drop out of this view.
  List<Widget> _buildMostWatched(List<_Entry> entries) {
    final videos = entries
        .where((e) => e.kind == _Kind.video && e.watchedSeconds > 0)
        .toList()
      ..sort((a, b) => b.watchedSeconds.compareTo(a.watchedSeconds));
    if (videos.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: AppSpacing.xl),
          child: EmptyState(
            icon: Icons.timer_off_rounded,
            title: 'No watch time recorded yet',
            message: 'Videos appear here once the child watches them.',
          ),
        ),
      ];
    }
    return [_DayCard(entries: videos)];
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

/// The period's headline: how long the child watched, and a breakdown that
/// doubles as the filter.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.days,
    required this.onDays,
    required this.sort,
    required this.onSort,
    required this.videos,
    required this.searches,
    required this.filter,
    required this.onFilter,
  });

  final Duration total;
  final int days;
  final ValueChanged<int> onDays;
  final _Sort sort;
  final ValueChanged<_Sort> onSort;
  final int videos;
  final int searches;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  static String _periodLabel(int d) => switch (d) {
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
                  'Time on YouTube',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              // Both controls ride inside the card — a separate row of buttons
              // under it cost a whole strip of the screen.
              PopupMenuButton<_Sort>(
                initialValue: sort,
                onSelected: onSort,
                position: PopupMenuPosition.under,
                tooltip: 'Sort',
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Sort.recent, child: Text('Recent')),
                  PopupMenuItem(
                      value: _Sort.watched, child: Text('Most watched')),
                ],
                child: _CardPill(
                  label: sort == _Sort.watched ? 'Most watched' : 'Recent',
                  icon: sort == _Sort.watched
                      ? Icons.trending_up_rounded
                      : Icons.schedule_rounded,
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<int>(
                initialValue: days,
                onSelected: onDays,
                position: PopupMenuPosition.under,
                tooltip: 'Period',
                itemBuilder: (_) => [
                  for (final d in [1, 7, 30])
                    PopupMenuItem(value: d, child: Text(_periodLabel(d))),
                ],
                child: _CardPill(label: _periodLabel(days)),
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
                value: videos,
                label: 'Videos',
                icon: Icons.play_circle_outline_rounded,
                active: filter == _Filter.videos,
                onTap: () => onFilter(_Filter.videos),
              ),
              _Stat(
                value: searches,
                label: 'Searches',
                icon: Icons.search_rounded,
                active: filter == _Filter.searches,
                onTap: () => onFilter(_Filter.searches),
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

/// A tappable pill on the gradient card.
class _CardPill extends StatelessWidget {
  const _CardPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 1),
          const Icon(Icons.expand_more_rounded, size: 15, color: Colors.white),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {  const _DayHeader({required this.day, required this.count});
  final DateTime day;
  final int count;

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff =
        today.difference(DateTime(day.year, day.month, day.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
              child: Container(height: 1, color: AppColors.borderOf(context))),
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
                padding:
                    const EdgeInsets.only(left: 68, right: AppSpacing.md),
                child: Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderOf(context)),
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

  /// Opens YouTube (or the browser) searching for this exact video — the child
  /// device can't read the app's internal video id, so a title search is the
  /// closest we can get to "open this video".
  Future<void> _open(BuildContext context) async {
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(entry.openUrl!),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open YouTube')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(
      entry.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryOf(context),
        height: 1.25,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Badge(kind: entry.kind),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Only the title opens YouTube — tapping elsewhere on the row
                // does nothing, so scrolling the list never launches the app.
                if (entry.openUrl == null)
                  title
                else
                  InkWell(
                    onTap: () => _open(context),
                    borderRadius: BorderRadius.circular(6),
                    child: title,
                  ),
                if (entry.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 12.5,
                    ),
                  ),
                ],
                // Watch time gets its own line: on one line with the channel it
                // was the first thing to be cut off.
                if (entry.meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
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

/// Red YouTube tile: a play icon for watched videos, a magnifier for searches.
class _Badge extends StatelessWidget {
  const _Badge({required this.kind});
  final _Kind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _ytRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(
        kind == _Kind.video ? Icons.play_arrow_rounded : Icons.search_rounded,
        color: _ytRed,
        size: kind == _Kind.video ? 24 : 20,
      ),
    );
  }
}

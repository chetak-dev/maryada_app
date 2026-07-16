import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/youtube_history_repository.dart';
import '../../theme/tokens.dart';

/// Shows the YouTube videos a child has watched (captured from the on-screen
/// title in the YouTube app).
class YoutubeHistoryScreen extends StatefulWidget {
  const YoutubeHistoryScreen({
    super.key,
    required this.childName,
    this.familyId,
    this.childId,
  });

  final String childName;
  final String? familyId;
  final String? childId;

  @override
  State<YoutubeHistoryScreen> createState() => _YoutubeHistoryScreenState();
}

class _YoutubeHistoryScreenState extends State<YoutubeHistoryScreen> {
  String _query = '';
  int _period = 0; // 0 = Today, 1 = Last week, 2 = This month

  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  List<YoutubeVideo> _filter(List<YoutubeVideo> v) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return v;
    return v
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.channel.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('YouTube · ${widget.childName}')),
      body: !_live
          ? const _Empty(text: 'Connect a device to see YouTube history.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                      AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search videos or channels',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0,
                      AppSpacing.md, AppSpacing.sm),
                  child: _PeriodSelector(
                    selected: _period,
                    onChanged: (i) => setState(() => _period = i),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<YoutubeVideo>>(
                    stream: YoutubeHistoryRepository.instance
                        .watch(widget.familyId!, widget.childId!),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final all = snap.data ?? const <YoutubeVideo>[];
                      if (all.isEmpty) {
                        return const _Empty(
                          text:
                              'No videos yet. They appear as the child watches YouTube.',
                        );
                      }
                      final videos = _filter(all);
                      if (videos.isEmpty) {
                        return const _Empty(text: 'No matching videos.');
                      }
                      final now = DateTime.now();
                      final startOfToday =
                          DateTime(now.year, now.month, now.day);
                      final weekAgo = now.subtract(const Duration(days: 7));
                      bool isToday(YoutubeVideo v) =>
                          v.at != null && !v.at!.isBefore(startOfToday);
                      bool isLastWeek(YoutubeVideo v) =>
                          v.at != null &&
                          v.at!.isBefore(startOfToday) &&
                          v.at!.isAfter(weekAgo);
                      final today = videos.where(isToday).toList();
                      final lastWeek = videos.where(isLastWeek).toList();
                      final thisMonth = videos
                          .where((v) => !isToday(v) && !isLastWeek(v))
                          .toList();
                      final selected =
                          [today, lastWeek, thisMonth][_period];
                      if (selected.isEmpty) {
                        return const _Empty(
                            text: 'No videos in this period.');
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                            AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                        itemCount: selected.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => _VideoTile(video: selected[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
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

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video});
  final YoutubeVideo video;

  static String _when(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final time = '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
    return sameDay ? time : '${t.day}/${t.month} · $time';
  }

  /// "5m 12s" / "1h 3m" watched.
  static String _watched(int seconds) {
    if (seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m watched';
    if (m > 0) return '${m}m ${s}s watched';
    return '${s}s watched';
  }

  @override
  Widget build(BuildContext context) {
    final watched = _watched(video.watchedSeconds);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Color(0xFFFF0000), size: 26),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  if (video.channel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(video.channel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                  if (watched.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(watched,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(_when(video.at),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/call_history_repository.dart';
import '../../data/db.dart';
import '../../theme/tokens.dart';

/// Shows a child's recent call log (incoming, outgoing, missed) reported by the
/// child device. Live from Firestore when [familyId]/[childId] are set.
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({
    super.key,
    required this.childName,
    this.familyId,
    this.childId,
  });

  final String childName;
  final String? familyId;
  final String? childId;

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  String _query = '';

  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  List<CallRecord> _filter(List<CallRecord> calls) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return calls;
    return calls
        .where((c) =>
            (c.name ?? '').toLowerCase().contains(q) ||
            c.number.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calls · ${widget.childName}')),
      body: !_live
          ? const _Empty(text: 'Connect a device to see its call history.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                      AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search name or number',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<CallRecord>>(
                    stream: CallHistoryRepository.instance
                        .watch(widget.familyId!, widget.childId!),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final calls = snap.data ?? const <CallRecord>[];
                      if (calls.isEmpty) {
                        return const _Empty(
                          text:
                              'No calls yet — they appear once the child device syncs.',
                        );
                      }
                      final filtered = _filter(calls);
                      if (filtered.isEmpty) {
                        return const _Empty(text: 'No matching calls.');
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                            AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => _CallTile(call: filtered[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});
  final CallRecord call;

  static String _when(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final time = '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
    if (sameDay) return time;
    return '${t.day}/${t.month} · $time';
  }

  static String _duration(Duration d) {
    if (d.inSeconds <= 0) return '';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  ({IconData icon, Color color}) get _visual {
    switch (call.kind) {
      case CallKind.incoming:
        return (icon: Icons.call_received_rounded, color: AppColors.accent);
      case CallKind.outgoing:
        return (icon: Icons.call_made_rounded, color: AppColors.primary);
      case CallKind.missed:
        return (icon: Icons.call_missed_rounded, color: AppColors.danger);
      case CallKind.rejected:
      case CallKind.blocked:
        return (icon: Icons.call_end_rounded, color: AppColors.danger);
      case CallKind.voicemail:
        return (icon: Icons.voicemail_rounded, color: AppColors.warning);
      case CallKind.unknown:
        return (icon: Icons.call_rounded, color: AppColors.textMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual;
    final dur = _duration(call.duration);
    final subtitle = [
      call.kind.label,
      if (dur.isNotEmpty) dur,
    ].join(' · ');
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
                color: v.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(v.icon, color: v.color, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  if (call.name != null &&
                      call.name!.isNotEmpty &&
                      call.name != call.number) ...[
                    const SizedBox(height: 1),
                    Text(call.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(_when(call.at),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12)),
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

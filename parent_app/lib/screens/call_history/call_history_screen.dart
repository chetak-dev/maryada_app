import 'package:flutter/material.dart';

import '../../data/call_history_repository.dart';
import '../../data/db.dart';
import '../../theme/tokens.dart';
import '../../widgets/chat_bubble.dart' show sameDay, dayLabel;
import '../../widgets/empty_state.dart';

/// Which calls the log is showing.
enum _CallFilter { all, incoming, outgoing, missed }

extension on _CallFilter {
  String get label => switch (this) {
        _CallFilter.all => 'All',
        _CallFilter.incoming => 'Incoming',
        _CallFilter.outgoing => 'Outgoing',
        _CallFilter.missed => 'Missed',
      };

  bool matches(CallRecord c) => switch (this) {
        _CallFilter.all => true,
        _CallFilter.incoming => c.kind == CallKind.incoming,
        _CallFilter.outgoing => c.kind == CallKind.outgoing,
        // Rejected and blocked are calls the child didn't take either, so they
        // belong with missed rather than in a filter of their own.
        _CallFilter.missed => c.kind == CallKind.missed ||
            c.kind == CallKind.rejected ||
            c.kind == CallKind.blocked,
      };
}

/// A child's call log, grouped by day and led by totals — a parent reads "how
/// much, and anything odd?" before any individual call.
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({
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

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _CallFilter _filter = _CallFilter.all;

  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CallRecord> _visible(List<CallRecord> calls) {
    final q = _query.trim().toLowerCase();
    final out = calls.where((c) {
      if (!_filter.matches(c)) return false;
      if (q.isEmpty) return true;
      return (c.name ?? '').toLowerCase().contains(q) ||
          c.number.toLowerCase().contains(q);
    }).toList();
    out.sort((a, b) => (b.at?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.at?.millisecondsSinceEpoch ?? 0));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calls · ${widget.childName}')),
      body: !_live
          ? const EmptyState(
              icon: Icons.call_rounded,
              title: 'No device connected',
              message: 'Connect a device to see its call history.',
            )
          : StreamBuilder<List<CallRecord>>(
              stream: CallHistoryRepository.instance
                  .watch(widget.familyId!, widget.childId!,
            deviceId: widget.deviceId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Couldn’t load call history',
                    message: 'Check your connection and try again.',
                  );
                }
                final all = snap.data ?? const <CallRecord>[];
                if (all.isEmpty) {
                  return const EmptyState(
                    icon: Icons.call_rounded,
                    title: 'No calls yet',
                    message: 'They appear once the child device syncs.',
                  );
                }
                final visible = _visible(all);
                return Column(
                  children: [
                    _SearchBox(
                      controller: _searchCtrl,
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                    _FilterBar(
                      selected: _filter,
                      countOf: (f) => all.where(f.matches).length,
                      onSelect: (f) => setState(() => _filter = f),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? const EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No calls match this view',
                            )
                          : _CallList(calls: visible),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.countOf,
    required this.onSelect,
  });

  final _CallFilter selected;
  final int Function(_CallFilter) countOf;
  final ValueChanged<_CallFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          for (final f in _CallFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilterChip(
                label: Text('${f.label} (${countOf(f)})'),
                selected: selected == f,
                onSelected: (_) => onSelect(f),
              ),
            ),
        ],
      ),
    );
  }
}

/// The log itself: one flat list with a day separator wherever the date
/// changes, rather than a card per call.
class _CallList extends StatelessWidget {
  const _CallList({required this.calls});
  final List<CallRecord> calls;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < calls.length; i++) {
      final c = calls[i];
      final prev = i == 0 ? null : calls[i - 1];
      final newDay = c.at != null &&
          (prev?.at == null || !sameDay(c.at!, prev!.at!));
      if (newDay) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
          child: Text(
            dayLabel(c.at!).toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondaryOf(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ));
      }
      rows.add(_CallTile(call: c));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: rows,
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});
  final CallRecord call;

  /// True when nothing but a number was captured — an unsaved contact, which
  /// is the case a parent most wants to notice.
  bool get _unknown => (call.name ?? '').trim().isEmpty;

  static String _time(DateTime? t) {
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'am' : 'pm';
    return '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
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
        return (icon: Icons.call_received_rounded, color: AppColors.success);
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
    final subtitle =
        [call.kind.label, if (dur.isNotEmpty) dur].join(' · ');
    final avatarColor = AppColors.avatarFor(call.display);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          // Avatar carries the contact, the badge carries the call type — one
          // circle tinted by call kind made every row look like an alert.
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: avatarColor,
                child: Text(
                  call.display.isNotEmpty
                      ? call.display.characters.first.toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(v.icon, color: v.color, size: 13),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(call.display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                    if (_unknown) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Not in contacts',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: v.color, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(_time(call.at),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search name or number',
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}


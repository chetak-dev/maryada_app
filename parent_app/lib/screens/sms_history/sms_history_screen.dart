import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/sms_history_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/empty_state.dart';

/// One contact's SMS conversation, built from the flat message list the child
/// device reports.
class _SmsThread {
  _SmsThread(this.address);

  final String address;
  final List<SmsMessage> messages = []; // newest first

  SmsMessage get last => messages.first;
  DateTime? get at => last.at;

  /// An address with no letters is an unsaved number. A stranger texting a
  /// child is the thing worth a parent's attention, so it gets marked.
  bool get isUnknownNumber => !address.contains(RegExp(r'[A-Za-z]'));
}

/// A child's SMS history grouped into conversations, the same shape as the
/// WhatsApp view. A flat list of individual messages never answered the
/// question a parent actually has, which is who their child is talking to.
class SmsHistoryScreen extends StatefulWidget {
  const SmsHistoryScreen({
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
  State<SmsHistoryScreen> createState() => _SmsHistoryScreenState();
}

class _SmsHistoryScreenState extends State<SmsHistoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_SmsThread> _threads(List<SmsMessage> msgs) {
    final sorted = [...msgs]..sort((a, b) =>
        (b.at?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.at?.millisecondsSinceEpoch ?? 0));
    final byAddress = <String, _SmsThread>{};
    for (final m in sorted) {
      byAddress
          .putIfAbsent(m.address, () => _SmsThread(m.address))
          .messages
          .add(m);
    }
    final out = byAddress.values.toList()
      ..sort((a, b) => (b.at?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.at?.millisecondsSinceEpoch ?? 0));
    if (_query.isEmpty) return out;
    return out
        .where((t) =>
            t.address.toLowerCase().contains(_query) ||
            t.messages.any((m) => m.body.toLowerCase().contains(_query)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: ChatColors.listBgOf(isDark),
      appBar: AppBar(
        backgroundColor: ChatColors.listBgOf(isDark),
        foregroundColor: ChatColors.headerTextOf(isDark),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Messages · ${widget.childName}',
          style: TextStyle(
            color: ChatColors.headerTextOf(isDark),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: !_live
          ? const EmptyState(
              icon: Icons.sms_rounded,
              title: 'No device connected',
              message: 'Connect a device to see its text messages.',
            )
          : Column(
              children: [
                _SearchBox(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
                Expanded(
                  child: StreamBuilder<List<SmsMessage>>(
                    stream: SmsHistoryRepository.instance
                        .watch(widget.familyId!, widget.childId!,
            deviceId: widget.deviceId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return const EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Couldn’t load messages',
                          message: 'Check your connection and try again.',
                        );
                      }
                      final msgs = snap.data ?? const <SmsMessage>[];
                      if (msgs.isEmpty) {
                        return const EmptyState(
                          icon: Icons.sms_rounded,
                          title: 'No messages yet',
                          message:
                              'They appear once the child device syncs.',
                        );
                      }
                      final threads = _threads(msgs);
                      if (threads.isEmpty) {
                        return const EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No messages match your search',
                        );
                      }
                      return ListView.builder(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.xxl),
                        itemCount: threads.length,
                        itemBuilder: (_, i) =>
                            _ThreadTile(thread: threads[i]),
                      );
                    },
                  ),
                ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 15, color: ChatColors.textOf(isDark)),
        decoration: InputDecoration(
          hintText: 'Search messages or sender',
          hintStyle: TextStyle(color: ChatColors.metaOf(isDark), fontSize: 15),
          prefixIcon:
              Icon(Icons.search, size: 20, color: ChatColors.metaOf(isDark)),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close,
                      size: 20, color: ChatColors.metaOf(isDark)),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          filled: true,
          fillColor: ChatColors.searchFillOf(isDark),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// One contact row in the conversation list.
class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});
  final _SmsThread thread;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = ChatColors.metaOf(isDark);
    final last = thread.last;
    final preview = last.isSent ? 'Sent: ${last.body}' : last.body;
    final initial = thread.address.isNotEmpty
        ? thread.address.characters.first.toUpperCase()
        : '?';
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _SmsThreadScreen(thread: thread)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: thread.isUnknownNumber
                  ? AppColors.textMuted
                  : AppColors.avatarFor(thread.address),
              child: thread.isUnknownNumber
                  ? const Icon(Icons.person_outline_rounded,
                      color: Colors.white)
                  : Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ChatColors.textOf(isDark),
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_shortWhen(thread.at),
                          style: TextStyle(color: subtle, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (thread.isUnknownNumber) ...[
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
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtle, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${thread.messages.length}',
                          style: TextStyle(color: subtle, fontSize: 12)),
                    ],
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

/// The full SMS conversation with one contact, as bubbles.
class _SmsThreadScreen extends StatelessWidget {
  const _SmsThreadScreen({required this.thread});
  final _SmsThread thread;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = thread.address.isNotEmpty
        ? thread.address.characters.first.toUpperCase()
        : '?';
    final msgs = thread.messages; // newest first, matching the reversed list
    final rows = <Widget>[];
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
      final startsRun = older == null || older.isSent != m.isSent;
      rows.add(Padding(
        padding: EdgeInsets.only(top: 1, bottom: startsRun ? 2 : 1),
        child: ChatBubble(
          text: m.body,
          time: _timeOnly(m.at),
          outgoing: m.isSent,
          withTail: startsRun,
        ),
      ));
      final dayChanged = older == null ||
          (m.at != null && older.at != null && !sameDay(m.at!, older.at!));
      if (dayChanged && m.at != null) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(child: DayChip(label: dayLabel(m.at!))),
        ));
      }
    }

    return Scaffold(
      backgroundColor: ChatColors.wallpaperOf(isDark),
      appBar: AppBar(
        backgroundColor: ChatColors.headerOf(isDark),
        foregroundColor: ChatColors.headerTextOf(isDark),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leadingWidth: 42,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: thread.isUnknownNumber
                  ? AppColors.textMuted
                  : AppColors.avatarFor(thread.address),
              child: Text(
                initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    thread.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ChatColors.headerTextOf(isDark),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'SMS · ${msgs.length} message${msgs.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12, color: ChatColors.metaOf(isDark)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ChatWallpaper(
        child: ListView(
          reverse: true,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          children: [
            ...rows,
            const ThreadNotice(
              text:
                  'Messages are mirrored from the child’s device to keep them safe.',
            ),
          ],
        ),
      ),
    );
  }
}

String _timeOnly(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'am' : 'pm';
  return '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
}

String _shortWhen(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  if (sameDay(t, now)) return _timeOnly(t);
  return '${t.day}/${t.month}/${t.year % 100}';
}


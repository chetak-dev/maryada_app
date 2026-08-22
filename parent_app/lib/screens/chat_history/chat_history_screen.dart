import 'package:flutter/material.dart';

import '../../data/chat_history_repository.dart';
import '../../data/db.dart';
import '../../theme/tokens.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/empty_state.dart';

/// Shows chats captured from messaging apps (WhatsApp) on the child device,
/// as a WhatsApp-style contact list. Tapping a contact opens the full
/// conversation, which loads older messages page by page.
class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({
    super.key,
    required this.childName,
    this.familyId,
    this.childId,
    this.deviceId,
  });

  final String childName;
  final String? familyId;
  final String? childId;

  /// When set, only this device's chats are shown.
  final String? deviceId;

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _live =>
      widget.familyId != null && widget.childId != null && Db.ready;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          'Chats · ${widget.childName}',
          style: TextStyle(
            color: ChatColors.headerTextOf(isDark),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          _SearchBox(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          Expanded(
            child: !_live
                ? const EmptyState(
                    icon: Icons.forum_rounded,
                    title: 'No device connected',
                    message: 'Connect a device to see chat messages.',
                  )
                : StreamBuilder<List<ChatSummary>>(
                    stream: ChatHistoryRepository.instance
                        .watchChats(widget.familyId!, widget.childId!,
            deviceId: widget.deviceId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return const EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Couldn’t load chats',
                          message:
                              'Check your connection and try again.',
                        );
                      }
                      var chats = snap.data ?? const <ChatSummary>[];
                      if (chats.isEmpty) {
                        return const EmptyState(
                          icon: Icons.forum_rounded,
                          title: 'No chats captured yet',
                          message:
                              'New incoming messages appear here.',
                        );
                      }
                      if (_query.isNotEmpty) {
                        chats = chats
                            .where((c) =>
                                c.sender.toLowerCase().contains(_query))
                            .toList();
                      }
                      if (chats.isEmpty) {
                        return const EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No chats match your search',
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                        itemCount: chats.length,
                        itemBuilder: (_, i) => _ChatListTile(
                          chat: chats[i],
                          familyId: widget.familyId!,
                          childId: widget.childId!,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Search field to filter the chat list by contact name.
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
          hintText: 'Search name or number',
          hintStyle:
              TextStyle(color: ChatColors.metaOf(isDark), fontSize: 15),
          prefixIcon: Icon(Icons.search,
              size: 20, color: ChatColors.metaOf(isDark)),
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

String _when(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  final time = '$h:${t.minute.toString().padLeft(2, '0')} $ampm';
  return sameDay ? time : '${t.day}/${t.month} · $time';
}

/// Prefers the chat's own displayed time; falls back to the capture time.
String _timeOf(ChatMessage m) =>
    m.timeLabel.isNotEmpty ? m.timeLabel : _when(m.at);

/// A collapsed WhatsApp-style row: avatar, contact name, last-message preview
/// and time. Tapping it opens the full conversation.
class _ChatListTile extends StatelessWidget {
  const _ChatListTile({
    required this.chat,
    required this.familyId,
    required this.childId,
  });
  final ChatSummary chat;
  final String familyId;
  final String childId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = ChatColors.textOf(isDark);
    final subtle = ChatColors.metaOf(isDark);
    final timeLabel = chat.lastTime.isNotEmpty ? chat.lastTime : _when(chat.at);
    final initial =
        chat.sender.isNotEmpty ? chat.sender.characters.first.toUpperCase() : '?';
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ChatThreadScreen(
            chat: chat,
            familyId: familyId,
            childId: childId,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.avatarFor(chat.sender),
              child: Text(
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
                          chat.sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: title,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeLabel,
                        style: TextStyle(color: subtle, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Sent messages lead with the double tick, the way the
                      // original chat list marks them — not a "You:" prefix.
                      if (chat.lastOutgoing) ...[
                        const Icon(Icons.done_all_rounded,
                            size: 16, color: ChatColors.tick),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          chat.lastText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtle, fontSize: 14),
                        ),
                      ),
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

/// The full conversation for one contact. Shows the most recent page live and
/// loads older messages on demand (pagination).
class _ChatThreadScreen extends StatefulWidget {
  const _ChatThreadScreen({
    required this.chat,
    required this.familyId,
    required this.childId,
  });
  final ChatSummary chat;
  final String familyId;
  final String childId;

  @override
  State<_ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<_ChatThreadScreen> {
  final _repo = ChatHistoryRepository.instance;
  // Older messages loaded via pagination (in addition to the live recent page).
  final List<ChatMessage> _older = [];
  bool _loadingOlder = false;
  bool _noMoreOlder = false;

  Future<void> _loadOlder(List<ChatMessage> current) async {
    if (_loadingOlder || _noMoreOlder || current.isEmpty) return;
    setState(() => _loadingOlder = true);
    final oldest = current.last; // current is newest-first
    final page = await _repo.fetchOlder(
      widget.familyId,
      widget.childId,
      widget.chat.senderKey,
      oldest.atMs,
    );
    if (!mounted) return;
    setState(() {
      _older.addAll(page);
      _loadingOlder = false;
      if (page.length < ChatHistoryRepository.pageSize) _noMoreOlder = true;
    });
  }

  /// Merges the live recent page with paged-older messages, newest-first.
  List<ChatMessage> _combine(List<ChatMessage> recent) {
    final byId = <String, ChatMessage>{};
    for (final m in recent) {
      byId[m.id] = m;
    }
    for (final m in _older) {
      byId[m.id] = m;
    }
    final list = byId.values.toList()..sort((a, b) => b.atMs.compareTo(a.atMs));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chat = widget.chat;
    final initial =
        chat.sender.isNotEmpty ? chat.sender.characters.first.toUpperCase() : '?';
    return Scaffold(
      backgroundColor: ChatColors.wallpaperOf(isDark),
      appBar: AppBar(
        backgroundColor: ChatColors.headerOf(isDark),
        foregroundColor: ChatColors.headerTextOf(isDark),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        // Back arrow flush against the avatar, the way the original app
        // clusters them.
        leadingWidth: 42,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.avatarFor(chat.sender),
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
                    chat.sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ChatColors.headerTextOf(isDark),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (chat.number.isNotEmpty)
                    Text(
                      chat.number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: ChatColors.metaOf(isDark),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ChatWallpaper(
        child: StreamBuilder<List<ChatMessage>>(
          stream: _repo.watchRecent(
              widget.familyId, widget.childId, widget.chat.senderKey),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                _older.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final recent = snap.data ?? const <ChatMessage>[];
            final combined = _combine(recent);
            if (combined.isEmpty) {
              return const EmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No messages in this chat yet',
              );
            }
            // A full recent page means there may be older messages to fetch.
            final canLoadMore = !_noMoreOlder &&
                (recent.length >= ChatHistoryRepository.pageSize ||
                    _older.isNotEmpty);
            final rows = _buildRows(combined);
            // Reversed list, so the last indexes render at the very top:
            // [messages] -> [load earlier] -> [pinned notice].
            final itemCount = rows.length + (canLoadMore ? 1 : 0) + 1;
            return ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              itemCount: itemCount,
              itemBuilder: (context, i) {
                if (i < rows.length) return rows[i];
                if (canLoadMore && i == rows.length) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Center(
                      child: _loadingOlder
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : DayChip(
                              label: 'Load earlier messages',
                              onTap: () => _loadOlder(combined),
                            ),
                    ),
                  );
                }
                return const ThreadNotice(
                  text:
                      'Messages are mirrored from the child’s device to keep them safe.',
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Builds the reversed (newest-first) row list: bubbles plus a day separator
  /// wherever the date changes, mirroring how the original app groups a
  /// conversation.
  List<Widget> _buildRows(List<ChatMessage> newestFirst) {
    final rows = <Widget>[];
    for (var i = 0; i < newestFirst.length; i++) {
      final m = newestFirst[i];
      // In a reversed list the *next* index is the older message.
      final older = i + 1 < newestFirst.length ? newestFirst[i + 1] : null;
      final newer = i > 0 ? newestFirst[i - 1] : null;

      // The bubble carries a tail only when it starts a run from one side,
      // which in a reversed list means the older neighbour is the other side.
      final startsRun = older == null || older.outgoing != m.outgoing;
      final sameRunAsNewer = newer != null && newer.outgoing == m.outgoing;

      rows.add(Padding(
        padding: EdgeInsets.only(
          top: sameRunAsNewer ? 1 : 2,
          bottom: startsRun ? 2 : 1,
        ),
        child: ChatBubble(
          text: m.text,
          time: _timeOf(m),
          outgoing: m.outgoing,
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
    return rows;
  }
}


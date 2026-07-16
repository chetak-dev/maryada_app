import 'package:flutter/material.dart';

import '../../data/chat_history_repository.dart';
import '../../data/db.dart';
import '../../theme/tokens.dart';

/// Shows chats captured from messaging apps (WhatsApp) on the child device,
/// as a WhatsApp-style contact list. Tapping a contact opens the full
/// conversation, which loads older messages page by page.
class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({
    super.key,
    required this.childName,
    this.familyId,
    this.childId,
  });

  final String childName;
  final String? familyId;
  final String? childId;

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
    return Scaffold(
      appBar: AppBar(title: Text('Chats · ${widget.childName}')),
      body: Column(
        children: [
          _SearchBox(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          Expanded(
            child: !_live
                ? const _Empty(text: 'Connect a device to see chat messages.')
                : StreamBuilder<List<ChatSummary>>(
                    stream: ChatHistoryRepository.instance
                        .watchChats(widget.familyId!, widget.childId!),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      var chats = snap.data ?? const <ChatSummary>[];
                      if (chats.isEmpty) {
                        return const _Empty(
                          text:
                              'No chats captured yet. New incoming messages appear here.',
                        );
                      }
                      if (_query.isNotEmpty) {
                        chats = chats
                            .where((c) =>
                                c.sender.toLowerCase().contains(_query))
                            .toList();
                      }
                      if (chats.isEmpty) {
                        return const _Empty(
                            text: 'No chats match your search.');
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                        itemCount: chats.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 72),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search a contact name',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
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
    final preview = chat.lastOutgoing ? 'You: ${chat.lastText}' : chat.lastText;
    final timeLabel = chat.lastTime.isNotEmpty ? chat.lastTime : _when(chat.at);
    final initial =
        chat.sender.isNotEmpty ? chat.sender.characters.first.toUpperCase() : '?';
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ChatThreadScreen(
            chat: chat,
            familyId: familyId,
            childId: childId,
          ),
        ),
      ),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primaryLight,
        child: Text(initial,
            style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.sender,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          Text(timeLabel,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chat.number.isNotEmpty)
              Text(
                chat.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
              ),
            Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chat.sender,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (widget.chat.number.isNotEmpty)
              Text(widget.chat.number,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w400))
            else if (widget.chat.app.isNotEmpty)
              Text(widget.chat.app,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: StreamBuilder<List<ChatMessage>>(
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
            return const _Empty(text: 'No messages in this chat yet.');
          }
          // A full recent page means there may be older messages to fetch.
          final canLoadMore = !_noMoreOlder &&
              (recent.length >= ChatHistoryRepository.pageSize ||
                  _older.isNotEmpty);
          final itemCount = combined.length + (canLoadMore ? 1 : 0);
          // reverse:true keeps the newest message pinned to the bottom; the
          // "Load earlier" control appears at the very top.
          return ListView.separated(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              if (i < combined.length) {
                final m = combined[i];
                return _Bubble(
                  text: m.text,
                  time: _timeOf(m),
                  outgoing: m.outgoing,
                );
              }
              // Load-earlier control (top of the reversed list).
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(
                  child: _loadingOlder
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton(
                          onPressed: () => _loadOlder(combined),
                          child: const Text('Load earlier messages'),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A single WhatsApp-style chat bubble: received messages sit on the left,
/// the child's own sent messages (right, green).
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.time,
    required this.outgoing,
  });

  final String text;
  final String time;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final bg = outgoing
        ? const Color(0xFFDCF8C6) // WhatsApp sent green
        : AppColors.surfaceMuted;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(outgoing ? 12 : 2),
      bottomRight: Radius.circular(outgoing ? 2 : 12),
    );
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 14)),
              if (time.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    time,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10),
                  ),
                ),
            ],
          ),
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

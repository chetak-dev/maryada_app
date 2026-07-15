import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// One captured chat message.
class ChatMessage {
  final String id;
  final String app;
  final String sender;
  final String text;
  final DateTime? at;
  final bool outgoing;
  final String timeLabel;

  const ChatMessage({
    required this.id,
    required this.app,
    required this.sender,
    required this.text,
    this.at,
    this.outgoing = false,
    this.timeLabel = '',
  });

  int get atMs => at?.millisecondsSinceEpoch ?? 0;

  static ChatMessage fromDoc(String id, Map<String, dynamic> m) => ChatMessage(
        id: id,
        app: (m['app'] ?? '').toString(),
        sender: (m['sender'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        at: (m['at'] is num)
            ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt())
            : null,
        outgoing: m['outgoing'] == true,
        timeLabel: (m['time'] ?? '').toString(),
      );
}

/// A one-line summary of a conversation, shown in the chat list.
class ChatSummary {
  final String senderKey;
  final String sender;
  final String app;
  final String number;
  final String lastText;
  final bool lastOutgoing;
  final String lastTime;
  final DateTime? at;

  const ChatSummary({
    required this.senderKey,
    required this.sender,
    required this.app,
    required this.number,
    required this.lastText,
    required this.lastOutgoing,
    required this.lastTime,
    this.at,
  });
}

/// Reads a child's captured chats. Conversations live under
/// `families/{familyId}/children/{childId}/chatThreads/{senderKey}` (one
/// summary doc each) with every message in a `messages` subcollection, so
/// history is unbounded and loaded page by page.
class ChatHistoryRepository {
  ChatHistoryRepository._();
  static final instance = ChatHistoryRepository._();

  static const int pageSize = 40;

  CollectionReference<Map<String, dynamic>> _threads(
          String familyId, String childId) =>
      Db.children(familyId).doc(childId).collection('chatThreads');

  /// Streams the chat list, sorted alphabetically by contact name.
  Stream<List<ChatSummary>> watchChats(String familyId, String childId) {
    return _threads(familyId, childId).snapshots().map((snap) {
      final chats = snap.docs.map((d) {
        final m = d.data();
        return ChatSummary(
          senderKey: d.id,
          sender: (m['sender'] ?? '').toString(),
          app: (m['app'] ?? '').toString(),
          number: (m['number'] ?? '').toString(),
          lastText: (m['lastText'] ?? '').toString(),
          lastOutgoing: m['lastOutgoing'] == true,
          lastTime: (m['lastTime'] ?? '').toString(),
          at: (m['at'] is num)
              ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt())
              : null,
        );
      }).toList();
      chats.sort((a, b) =>
          a.sender.toLowerCase().compareTo(b.sender.toLowerCase()));
      return chats;
    });
  }

  /// Streams the most recent [pageSize] messages of one conversation (live).
  Stream<List<ChatMessage>> watchRecent(
      String familyId, String childId, String senderKey) {
    return _threads(familyId, childId)
        .doc(senderKey)
        .collection('messages')
        .orderBy('at', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromDoc(d.id, d.data())).toList());
  }

  /// Fetches the page of messages older than [beforeAtMs] (for infinite scroll).
  Future<List<ChatMessage>> fetchOlder(
      String familyId, String childId, String senderKey, int beforeAtMs) async {
    final snap = await _threads(familyId, childId)
        .doc(senderKey)
        .collection('messages')
        .where('at', isLessThan: beforeAtMs)
        .orderBy('at', descending: true)
        .limit(pageSize)
        .get();
    return snap.docs.map((d) => ChatMessage.fromDoc(d.id, d.data())).toList();
  }
}


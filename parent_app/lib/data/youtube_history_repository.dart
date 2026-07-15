import 'db.dart';

/// A YouTube video the child watched, captured from the on-screen title.
class YoutubeVideo {
  final String title;
  final String channel;
  final DateTime? at;
  final int watchedSeconds;

  const YoutubeVideo({
    required this.title,
    this.channel = '',
    this.at,
    this.watchedSeconds = 0,
  });

  /// Opens YouTube searching for this exact video (we can't read the app's
  /// internal video id, so an exact-phrase title + channel search puts it on
  /// top of the results).
  String get searchUrl {
    final clean = title
        .replaceAll(RegExp(r'[|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final q = channel.isEmpty ? '"$clean"' : '"$clean" $channel';
    return 'https://www.youtube.com/results?search_query='
        '${Uri.encodeQueryComponent(q)}';
  }
}

/// Reads a child's YouTube watch history from
/// `families/{familyId}/children/{childId}/youtubeHistory/current`.
class YoutubeHistoryRepository {
  YoutubeHistoryRepository._();
  static final instance = YoutubeHistoryRepository._();

  Stream<List<YoutubeVideo>> watch(String familyId, String childId) {
    return Db.families
        .doc(familyId)
        .collection('children')
        .doc(childId)
        .collection('youtubeHistory')
        .doc('current')
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null) return const <YoutubeVideo>[];
      final raw = ((data['videos'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => YoutubeVideo(
                title: (m['title'] ?? '').toString(),
                channel: (m['channel'] ?? '').toString(),
                at: (m['at'] is num)
                    ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt())
                    : null,
                watchedSeconds: (m['watchedMs'] is num)
                    ? ((m['watchedMs'] as num).toInt() / 1000).round()
                    : 0,
              ))
          .where((v) => v.title.isNotEmpty)
          .toList();
      return _mergeByTitle(raw);
    });
  }

  /// Collapses duplicate videos (same title) into one, summing watch time and
  /// keeping the most recent timestamp — a safety net over the child's dedup.
  List<YoutubeVideo> _mergeByTitle(List<YoutubeVideo> videos) {
    String key(String t) => t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final byKey = <String, YoutubeVideo>{};
    for (final v in videos) {
      final k = key(v.title);
      final prev = byKey[k];
      if (prev == null) {
        byKey[k] = v;
      } else {
        final newer = (v.at?.millisecondsSinceEpoch ?? 0) >
                (prev.at?.millisecondsSinceEpoch ?? 0)
            ? v
            : prev;
        byKey[k] = YoutubeVideo(
          title: newer.title,
          channel: newer.channel.isNotEmpty ? newer.channel : prev.channel,
          at: newer.at,
          watchedSeconds: prev.watchedSeconds + v.watchedSeconds,
        );
      }
    }
    final list = byKey.values.toList()
      ..sort((a, b) => (b.at?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.at?.millisecondsSinceEpoch ?? 0));
    return list;
  }
}

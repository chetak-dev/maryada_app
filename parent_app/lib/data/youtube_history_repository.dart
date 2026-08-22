import 'db.dart';

/// A YouTube video the child watched, captured from the on-screen title.
class YoutubeVideo {
  final String title;
  final String channel;
  final DateTime? at;
  final int watchedSeconds;

  /// The video's full length, when the child device could read it. 0 when not
  /// known, which is why watch time is never shown as a fraction of it.
  final int durationSeconds;

  const YoutubeVideo({
    required this.title,
    this.channel = '',
    this.at,
    this.watchedSeconds = 0,
    this.durationSeconds = 0,
  });

  /// Opens YouTube searching for this video's title. Quoting it as an exact
  /// phrase found nothing whenever the captured title differed from the real
  /// one by a character, so the words are searched as they were read.
  String get searchUrl {
    final clean = title
        .replaceAll(RegExp(r'["|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final q = channel.isEmpty ? clean : '$clean $channel';
    return 'https://www.youtube.com/results?search_query='
        '${Uri.encodeQueryComponent(q)}';
  }
}

/// Reads a child's YouTube watch history from
/// `families/{familyId}/children/{childId}/youtubeHistory/current`.
class YoutubeHistoryRepository {
  YoutubeHistoryRepository._();
  static final instance = YoutubeHistoryRepository._();

  Stream<List<YoutubeVideo>> watch(String familyId, String childId,
      {String? deviceId}) {
    return Db.watchReportArray<YoutubeVideo>(
      deviceId: deviceId,
      familyId: familyId,
      childId: childId,
      collection: 'youtubeHistory',
      field: 'videos',
      parse: (m) {
        final title = (m['title'] ?? '').toString();
        if (title.isEmpty) return null;
        return YoutubeVideo(
          title: title,
          channel: (m['channel'] ?? '').toString(),
          at: Db.millis(m['at']),
          watchedSeconds: (m['watchedMs'] is num)
              ? ((m['watchedMs'] as num).toInt() / 1000).round()
              : 0,
          durationSeconds: (m['durationMs'] is num)
              ? ((m['durationMs'] as num).toInt() / 1000).round()
              : 0,
        );
      },
    ).map(_merge);
  }

  /// Collapses repeat entries for one video, summing watch time and keeping the
  /// most recent timestamp. Keyed on title *and* channel: two different videos
  /// can share a title, and merging on title alone hid one behind the other.
  List<YoutubeVideo> _merge(List<YoutubeVideo> videos) {
    String key(YoutubeVideo v) =>
        '${v.title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()}'
        '|${v.channel.toLowerCase().trim()}';
    final byKey = <String, YoutubeVideo>{};
    for (final v in videos) {
      final k = key(v);
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
          durationSeconds:
              newer.durationSeconds > 0 ? newer.durationSeconds : prev.durationSeconds,
        );
      }
    }
    final list = byKey.values.toList()
      ..sort((a, b) => (b.at?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.at?.millisecondsSinceEpoch ?? 0));
    return list;
  }
}

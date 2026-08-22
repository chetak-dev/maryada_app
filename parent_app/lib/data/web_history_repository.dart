import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// A single web lookup recorded by the child's DNS filter.
class WebVisit {
  final String domain;
  final DateTime? at;

  /// Approximate time spent on the site (visited list only).
  final Duration timeSpent;

  /// Number of visits (visited) or blocked attempts (blocked).
  final int count;

  /// Why it was blocked — a category id, `blocklist`, `youtube`, `keyword` or
  /// `content`. Empty for visited sites and for devices on older builds.
  final String reason;

  const WebVisit({
    required this.domain,
    this.at,
    this.timeSpent = Duration.zero,
    this.count = 0,
    this.reason = '',
  });
}

/// One submitted search-results navigation captured from a known search engine.
class WebSearch {
  final String query;
  final String engine;
  final DateTime? at;

  const WebSearch({required this.query, required this.engine, this.at});
}

/// Visited + blocked domains reported by a child device.
class WebHistory {
  final List<WebVisit> visited;
  final List<WebVisit> blocked;
  final List<WebSearch> searches;
  const WebHistory({
    this.visited = const [],
    this.blocked = const [],
    this.searches = const [],
  });

  bool get isEmpty => visited.isEmpty && blocked.isEmpty && searches.isEmpty;
}

/// Reads a child's web history from
/// `families/{familyId}/children/{childId}/webHistory/{deviceUid}`.
class WebHistoryRepository {
  WebHistoryRepository._();
  static final instance = WebHistoryRepository._();

  Stream<WebHistory> watch(String familyId, String childId,
      {String? deviceId}) {
    final reports = Db.childReports(familyId, childId, 'webHistory');
    // `current` is the shared document single-device builds wrote; it belongs
    // to whichever device existed then, so it stays visible until that device
    // migrates it onto its own document.
    final source = deviceId == null
        ? reports.snapshots()
        : reports
            .where(FieldPath.documentId, whereIn: [deviceId, 'current'])
            .snapshots();
    return source.map((snap) {
      final visited = <WebVisit>[];
      final blocked = <WebVisit>[];
      final searches = <WebSearch>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        List<WebVisit> parse(String key) {
          return ((data[key] as List?) ?? const [])
              .whereType<Map>()
              .map((m) => WebVisit(
                    domain: (m['domain'] ?? '').toString(),
                    at: Db.millis(m['at']),
                    timeSpent: m['milliseconds'] is num
                        ? Duration(
                            milliseconds: (m['milliseconds'] as num).toInt())
                        : Duration(
                            seconds: (m['seconds'] as num?)?.toInt() ?? 0),
                    count: (m['visits'] as num?)?.toInt() ??
                        (m['attempts'] as num?)?.toInt() ??
                        0,
                    reason: (m['reason'] ?? '').toString(),
                  ))
              .where((v) => v.domain.isNotEmpty)
              .toList();
        }

        visited.addAll(parse('visited'));
        blocked.addAll(parse('blocked'));
        searches.addAll(((data['searches'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => WebSearch(
                  query: (m['query'] ?? '').toString(),
                  engine: (m['engine'] ?? 'Search').toString(),
                  at: Db.millis(m['at']),
                ))
            .where((s) => s.query.trim().isNotEmpty));
      }

      searches.sort((a, b) => (b.at?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.at?.millisecondsSinceEpoch ?? 0));
      return WebHistory(
        visited: visited,
        blocked: blocked,
        searches: searches,
      );
    });
  }
}


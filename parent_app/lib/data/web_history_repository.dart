import 'db.dart';

/// A single web lookup recorded by the child's DNS filter.
class WebVisit {
  final String domain;
  final DateTime? at;

  /// Approximate time spent on the site (visited list only).
  final Duration timeSpent;

  /// Number of visits (visited) or blocked attempts (blocked).
  final int count;

  const WebVisit({
    required this.domain,
    this.at,
    this.timeSpent = Duration.zero,
    this.count = 0,
  });
}

/// Visited + blocked domains reported by a child device.
class WebHistory {
  final List<WebVisit> visited;
  final List<WebVisit> blocked;
  const WebHistory({this.visited = const [], this.blocked = const []});

  bool get isEmpty => visited.isEmpty && blocked.isEmpty;
}

/// Reads a child's web history from
/// `families/{familyId}/children/{childId}/webHistory/current`.
class WebHistoryRepository {
  WebHistoryRepository._();
  static final instance = WebHistoryRepository._();

  Stream<WebHistory> watch(String familyId, String childId) {
    return Db.families
        .doc(familyId)
        .collection('children')
        .doc(childId)
        .collection('webHistory')
        .doc('current')
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null) return const WebHistory();
      List<WebVisit> parse(String key) {
        return ((data[key] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => WebVisit(
                  domain: (m['domain'] ?? '').toString(),
                  at: (m['at'] is num)
                      ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt())
                      : null,
                  timeSpent: Duration(
                      seconds: (m['seconds'] as num?)?.toInt() ?? 0),
                  count: (m['visits'] as num?)?.toInt() ??
                      (m['attempts'] as num?)?.toInt() ??
                      0,
                ))
            .where((v) => v.domain.isNotEmpty)
            .toList();
      }

      return WebHistory(visited: parse('visited'), blocked: parse('blocked'));
    });
  }
}


import 'db.dart';

/// One day's total screen time.
class DayUsage {
  final String day;
  final int minutes;
  const DayUsage(this.day, this.minutes);
}

/// A single app's usage today.
class AppUsage {
  final String appName;
  final int minutes;
  const AppUsage(this.appName, this.minutes);
}

/// The child's reported usage summary.
class UsageSummary {
  final List<DayUsage> week;
  final List<AppUsage> topApps;
  final DateTime? updatedAt;
  const UsageSummary({
    required this.week,
    required this.topApps,
    this.updatedAt,
  });

  bool get isEmpty => week.isEmpty && topApps.isEmpty;
}

/// Reads the screen-time usage a child device reports to
/// `families/{familyId}/children/{childId}/usage/summary`.
class UsageRepository {
  UsageRepository._();
  static final instance = UsageRepository._();

  Future<UsageSummary?> load(String familyId, String childId) async {
    final doc = await Db.families
        .doc(familyId)
        .collection('children')
        .doc(childId)
        .collection('usage')
        .doc('summary')
        .get();
    final data = doc.data();
    if (data == null) return null;

    final week = ((data['week'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => DayUsage(
              (m['day'] ?? '').toString(),
              (m['minutes'] as num?)?.toInt() ?? 0,
            ))
        .toList();
    final topApps = ((data['topApps'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => AppUsage(
              (m['appName'] ?? m['packageName'] ?? '').toString(),
              (m['minutes'] as num?)?.toInt() ?? 0,
            ))
        .toList();

    return UsageSummary(week: week, topApps: topApps);
  }
}

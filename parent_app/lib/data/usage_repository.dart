import 'package:cloud_firestore/cloud_firestore.dart';

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

/// Reads the screen-time usage a child's devices report to
/// `families/{familyId}/children/{childId}/usage/{deviceUid}`.
class UsageRepository {
  UsageRepository._();
  static final instance = UsageRepository._();

  /// Loads usage for a profile, or for one device when [deviceId] is set.
  ///
  /// Every device writes its own document, so a phone and a PC are added
  /// together rather than overwriting each other. `summary` is the shared
  /// document single-device builds wrote; it still counts, unless the device
  /// that owns it has also written its own document and would be counted twice.
  Future<UsageSummary?> load(
    String familyId,
    String childId, {
    String? deviceId,
  }) async {
    final snap = await Db.families
        .doc(familyId)
        .collection('children')
        .doc(childId)
        .collection('usage')
        .get();
    return _summarise(snap.docs, deviceId);
  }

  /// The same reading, kept up to date. Screen time changes all day, so a
  /// figure fetched once when the screen opened was stale within minutes.
  Stream<UsageSummary?> watch(
    String familyId,
    String childId, {
    String? deviceId,
  }) {
    return Db.families
        .doc(familyId)
        .collection('children')
        .doc(childId)
        .collection('usage')
        .snapshots()
        .map((snap) => _summarise(snap.docs, deviceId));
  }

  UsageSummary? _summarise(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? deviceId,
  ) {
    if (docs.isEmpty) return null;

    final perDevice = docs.where((d) => d.id != 'summary').toList();
    final ownedIds = perDevice.map((d) => d.id).toSet();
    final sources = deviceId != null
        ? docs.where((d) => d.id == deviceId).toList()
        : [
            ...perDevice,
            ...docs.where((d) =>
                d.id == 'summary' &&
                !ownedIds.contains((d.data()['deviceUid'] ?? '').toString())),
          ];
    if (sources.isEmpty) return null;

    final minutesByDay = <String, int>{};
    final order = <String>[];
    final minutesByApp = <String, int>{};
    DateTime? updatedAt;

    for (final doc in sources) {
      final data = doc.data();
      for (final entry in ((data['week'] as List?) ?? const []).whereType<Map>()) {
        final day = (entry['day'] ?? '').toString();
        if (day.isEmpty) continue;
        if (!minutesByDay.containsKey(day)) order.add(day);
        minutesByDay[day] =
            (minutesByDay[day] ?? 0) + ((entry['minutes'] as num?)?.toInt() ?? 0);
      }
      for (final entry
          in ((data['topApps'] as List?) ?? const []).whereType<Map>()) {
        final name = (entry['appName'] ?? entry['packageName'] ?? '').toString();
        if (name.isEmpty) continue;
        minutesByApp[name] =
            (minutesByApp[name] ?? 0) + ((entry['minutes'] as num?)?.toInt() ?? 0);
      }
      final at = Db.millis(data['updatedAt']);
      if (at != null && (updatedAt == null || at.isAfter(updatedAt))) {
        updatedAt = at;
      }
    }

    final topApps = minutesByApp.entries
        .map((e) => AppUsage(e.key, e.value))
        .toList()
      ..sort((a, b) => b.minutes.compareTo(a.minutes));

    return UsageSummary(
      week: [for (final day in order) DayUsage(day, minutesByDay[day] ?? 0)],
      topApps: topApps.take(6).toList(),
      updatedAt: updatedAt,
    );
  }
}

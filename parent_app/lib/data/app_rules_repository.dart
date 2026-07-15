import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// The persisted per-app rule (keyed by package name).
class AppRuleData {
  final bool blocked;
  final int dailyLimitMinutes;
  const AppRuleData({this.blocked = false, this.dailyLimitMinutes = 0});
}

/// A real installed app reported by a child device.
class InstalledAppInfo {
  final String packageName;
  final String appName;

  /// Names of the children who have this app installed (family view).
  final List<String> owners;
  const InstalledAppInfo({
    required this.packageName,
    required this.appName,
    this.owners = const [],
  });
}

/// Reads/writes family-wide app rules. Firestore:
/// `families/{familyId}/appRules/{packageName}` -> { appName, blocked, dailyLimitMinutes }.
/// The child device reads this collection and enforces blocks locally.
class AppRulesRepository {
  AppRulesRepository._();
  static final instance = AppRulesRepository._();

  CollectionReference<Map<String, dynamic>> _col(String familyId) =>
      Db.families.doc(familyId).collection('appRules');

  /// One-shot load of saved rules, keyed by package name.
  Future<Map<String, AppRuleData>> load(String familyId) async {
    final snap = await _col(familyId).get();
    return {
      for (final d in snap.docs)
        d.id: AppRuleData(
          blocked: d.data()['blocked'] == true,
          dailyLimitMinutes:
              (d.data()['dailyLimitMinutes'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  Future<void> setRule(
    String familyId, {
    required String packageName,
    required String appName,
    required bool blocked,
    required int dailyLimitMinutes,
  }) {
    return _col(familyId).doc(packageName).set({
      'appName': appName,
      'blocked': blocked,
      'dailyLimitMinutes': dailyLimitMinutes,
    }, SetOptions(merge: true));
  }

  /// Loads the real installed apps reported by the family's child devices,
  /// unioned by package name, each tagged with which children have it. Empty if
  /// no device has reported yet.
  Future<List<InstalledAppInfo>> loadInstalledApps(String familyId) async {
    final kids = await Db.families.doc(familyId).collection('children').get();
    final names = <String, String>{};
    final owners = <String, List<String>>{};
    for (final kid in kids.docs) {
      final raw = (kid.data()['name'] as String?)?.trim();
      final label = (raw == null || raw.isEmpty) ? 'Child' : raw;
      for (final a in await _childApps(kid.reference)) {
        if (a is! Map) continue;
        final pkg = a['packageName'] as String?;
        final name = a['appName'] as String?;
        if (pkg == null || pkg.isEmpty) continue;
        names[pkg] = (name == null || name.isEmpty) ? pkg : name;
        (owners[pkg] ??= <String>[]).add(label);
      }
    }
    final list = names.entries
        .map((e) => InstalledAppInfo(
              packageName: e.key,
              appName: e.value,
              owners: owners[e.key] ?? const [],
            ))
        .toList()
      ..sort((a, b) =>
          a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
    return list;
  }

  /// Loads the installed apps reported by a single child device.
  Future<List<InstalledAppInfo>> loadInstalledAppsForChild(
    String familyId,
    String childId,
  ) async {
    final ref = Db.families.doc(familyId).collection('children').doc(childId);
    final byPackage = <String, String>{};
    _mergeReport(await _childApps(ref), byPackage);
    return _sorted(byPackage);
  }

  Future<List<dynamic>> _childApps(
    DocumentReference<Map<String, dynamic>> childRef,
  ) async {
    final report =
        await childRef.collection('reports').doc('installedApps').get();
    return (report.data()?['apps'] as List?) ?? const [];
  }

  void _mergeReport(List<dynamic> apps, Map<String, String> into) {
    for (final a in apps) {
      if (a is Map) {
        final pkg = a['packageName'] as String?;
        final name = a['appName'] as String?;
        if (pkg != null && pkg.isNotEmpty) {
          into[pkg] = (name == null || name.isEmpty) ? pkg : name;
        }
      }
    }
  }

  List<InstalledAppInfo> _sorted(Map<String, String> byPackage) {
    final list = byPackage.entries
        .map((e) => InstalledAppInfo(packageName: e.key, appName: e.value))
        .toList()
      ..sort((a, b) =>
          a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
    return list;
  }
}

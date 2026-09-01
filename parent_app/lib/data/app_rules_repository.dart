import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';
import 'family_repository.dart';

/// The persisted per-app rule (keyed by package name).
class AppRuleData {
  final bool blocked;
  final int dailyLimitMinutes;
  final bool bankingAllowed;
  const AppRuleData({
    this.blocked = false,
    this.dailyLimitMinutes = 0,
    this.bankingAllowed = false,
  });
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

  CollectionReference<Map<String, dynamic>> _col(
    String familyId, [
    String? childId,
  ]) => (childId == null || childId.isEmpty)
      ? Db.families.doc(familyId).collection('appRules')
      : Db.families
            .doc(familyId)
            .collection('children')
            .doc(childId)
            .collection('appRules');

  /// One-shot load of saved rules, keyed by package name. When [childId] is set,
  /// loads that child's own rules; otherwise the family-wide ("common") rules.
  Future<Map<String, AppRuleData>> load(
    String familyId, {
    String? childId,
  }) async {
    final snap = await _col(familyId, childId).get();
    return {
      for (final d in snap.docs)
        d.id: AppRuleData(
          blocked: d.data()['blocked'] == true,
          dailyLimitMinutes:
              (d.data()['dailyLimitMinutes'] as num?)?.toInt() ?? 0,
          bankingAllowed: d.data()['bankingAllowed'] == true,
        ),
    };
  }

  /// Saves a rule. When [childId] is set, it applies only to that child;
  /// otherwise it's a family-wide ("common") rule that applies to all children.
  Future<void> setRule(
    String familyId, {
    required String packageName,
    required String appName,
    required bool blocked,
    required int dailyLimitMinutes,
    required bool bankingAllowed,
    String? childId,
  }) {
    return _col(familyId, childId).doc(packageName).set({
      'appName': appName,
      'blocked': blocked,
      'dailyLimitMinutes': dailyLimitMinutes,
      'bankingAllowed': bankingAllowed,
    }, SetOptions(merge: true));
  }

  /// Loads the real installed apps reported by the family's child devices,
  /// unioned by package name, each tagged with which children have it. Empty if
  /// no device has reported yet.
  Future<List<InstalledAppInfo>> loadInstalledApps(String familyId) async {
    // Scoped: a parent limited to one group must not see the apps of profiles
    // their grant excluded.
    final kids = await FamilyRepository.instance.scopedChildren(familyId);
    final names = <String, String>{};
    // A set, not a list: each of a child's devices reports its own inventory,
    // so a shared app used to name that child once per device.
    final owners = <String, Set<String>>{};
    for (final kid in kids.docs) {
      // A profile whose devices were all removed keeps its old report doc;
      // its apps must vanish from this list the moment it unpairs.
      if (kid.data()['paired'] != true) continue;
      final raw = (kid.data()['name'] as String?)?.trim();
      final label = (raw == null || raw.isEmpty) ? 'Child' : raw;
      for (final a in await _childApps(kid.reference)) {
        if (a is! Map) continue;
        final pkg = a['packageName'] as String?;
        final name = a['appName'] as String?;
        if (pkg == null || pkg.isEmpty) continue;
        names[pkg] = (name == null || name.isEmpty) ? pkg : name;
        (owners[pkg] ??= <String>{}).add(label);
      }
    }
    final list =
        names.entries
            .map(
              (e) => InstalledAppInfo(
                packageName: e.key,
                appName: e.value,
                owners: owners[e.key]?.toList() ?? const [],
              ),
            )
            .toList()
          ..sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );
    return list;
  }

  /// Loads the installed apps reported by a single child device. Empty once
  /// the profile has no linked device — stale reports don't show.
  Future<List<InstalledAppInfo>> loadInstalledAppsForChild(
    String familyId,
    String childId, {
    String? deviceId,
    String? platform,
  }) async {
    final ref = Db.families.doc(familyId).collection('children').doc(childId);
    final childDoc = await ref.get();
    if (childDoc.data()?['paired'] != true) return const [];
    final byPackage = <String, String>{};
    _mergeReport(
      await _childApps(ref, deviceId: deviceId, platform: platform),
      byPackage,
    );
    return _sorted(byPackage);
  }

  /// Every device reports its own installed-apps document. A phone and a PC on
  /// one profile hold different apps, so they are merged rather than the last
  /// writer winning; `installedApps` is the shared document single-device
  /// builds wrote.
  Future<List<dynamic>> _childApps(
    DocumentReference<Map<String, dynamic>> childRef, {
    String? deviceId,
    String? platform,
  }) async {
    final reports = await childRef.collection('reports').get();
    final apps = <dynamic>[];
    for (final doc in reports.docs) {
      if (!acceptsInstalledAppsReport(
        doc.id,
        deviceId: deviceId,
        platform: platform,
      )) {
        continue;
      }
      apps.addAll((doc.data()['apps'] as List?) ?? const []);
    }
    return apps;
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
    final list =
        byPackage.entries
            .map((e) => InstalledAppInfo(packageName: e.key, appName: e.value))
            .toList()
          ..sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );
    return list;
  }
}

/// Whether one report document belongs in the current app-rules view.
bool acceptsInstalledAppsReport(
  String reportId, {
  String? deviceId,
  String? platform,
}) {
  if (!reportId.startsWith('installedApps')) return false;
  if (deviceId == null) return true;
  if (reportId == 'installedApps-$deviceId') return true;
  // Current Android builds still write one shared legacy report. Windows has
  // a per-device report and must never inherit this document.
  return platform == 'android' && reportId == 'installedApps';
}

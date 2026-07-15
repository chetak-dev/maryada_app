import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// Persisted web-filter settings for the family.
class WebFilterSettings {
  final bool enabled;
  final Set<String> blockedCategories;
  final List<String> blockedSites;

  const WebFilterSettings({
    this.enabled = true,
    this.blockedCategories = const {},
    this.blockedSites = const [],
  });
}

/// Reads/writes the family web filter. Firestore:
/// `families/{familyId}/rules/webFilter` -> { enabled, blockedCategories[], blockedSites[] }.
class WebFilterRepository {
  WebFilterRepository._();
  static final instance = WebFilterRepository._();

  DocumentReference<Map<String, dynamic>> _doc(String familyId) =>
      Db.families.doc(familyId).collection('rules').doc('webFilter');

  Future<WebFilterSettings> load(String familyId) async {
    final doc = await _doc(familyId).get();
    if (!doc.exists) return const WebFilterSettings();
    final d = doc.data()!;
    return WebFilterSettings(
      enabled: d['enabled'] != false,
      blockedCategories: (d['blockedCategories'] is List)
          ? Set<String>.from((d['blockedCategories'] as List).map((e) => '$e'))
          : const {},
      blockedSites: (d['blockedSites'] is List)
          ? List<String>.from((d['blockedSites'] as List).map((e) => '$e'))
          : const [],
    );
  }

  Future<void> save(String familyId, WebFilterSettings s) {
    return _doc(familyId).set({
      'enabled': s.enabled,
      'blockedCategories': s.blockedCategories.toList(),
      'blockedSites': s.blockedSites,
    }, SetOptions(merge: true));
  }

  Stream<WebFilterSettings> watch(String familyId) {
    return _doc(familyId).snapshots().map((doc) {
      final d = doc.data();
      if (d == null) return const WebFilterSettings(enabled: false);
      return WebFilterSettings(
        enabled: d['enabled'] != false,
        blockedCategories: (d['blockedCategories'] is List)
            ? Set<String>.from((d['blockedCategories'] as List).map((e) => '$e'))
            : const {},
        blockedSites: (d['blockedSites'] is List)
            ? List<String>.from((d['blockedSites'] as List).map((e) => '$e'))
            : const [],
      );
    });
  }
}

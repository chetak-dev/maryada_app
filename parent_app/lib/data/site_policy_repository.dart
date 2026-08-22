import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// Categories blocked by default until the site admin customises them.
const Set<String> kDefaultBlockedCategories = {
  'adult',
  'gambling',
  'drugs',
  'weapons',
  'violence',
};

/// The site admin's global browser / safe-browsing policy (`appConfig/webPolicy`).
class WebPolicy {
  final bool safeBrowsingEnabled;
  final bool blockOtherBrowsers;
  final bool allowIncognito;
  final Set<String> blockedCategories;

  const WebPolicy({
    this.safeBrowsingEnabled = true,
    this.blockOtherBrowsers = false,
    this.allowIncognito = false,
    this.blockedCategories = kDefaultBlockedCategories,
  });

  factory WebPolicy.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const WebPolicy();
    final cats = m['blockedCategories'];
    return WebPolicy(
      safeBrowsingEnabled: m['safeBrowsingEnabled'] != false,
      blockOtherBrowsers: m['blockOtherBrowsers'] == true,
      allowIncognito: m['allowIncognito'] == true,
      blockedCategories: cats is List
          ? cats.map((e) => '$e').toSet()
          : kDefaultBlockedCategories,
    );
  }
}

/// Site-admin-only global web controls stored under `appConfig/*` (writable only
/// by the site admin per the security rules): per-category content keywords
/// (`appConfig/contentFilter`) and browser/safe-browsing policy
/// (`appConfig/webPolicy`). Read by every signed-in account and by child devices.
class SitePolicyRepository {
  SitePolicyRepository._();
  static final instance = SitePolicyRepository._();

  DocumentReference<Map<String, dynamic>> get _contentDoc =>
      Db.instance.collection('appConfig').doc('contentFilter');
  DocumentReference<Map<String, dynamic>> get _policyDoc =>
      Db.instance.collection('appConfig').doc('webPolicy');

  // ---- Content keywords, grouped by category ----------------------------

  Map<String, List<String>> _readCategories(Map<String, dynamic>? d) {
    final cats = d?['categories'];
    if (cats is! Map) return {};
    return {
      for (final e in cats.entries)
        e.key.toString(): (e.value is List)
            ? List<String>.from((e.value as List).map((x) => '$x'))
            : <String>[],
    };
  }

  Stream<Map<String, List<String>>> watchCategoryKeywords() =>
      _contentDoc.snapshots().map((d) => _readCategories(d.data()));

  /// Replaces the keyword list for one category. Other categories are untouched.
  Future<void> setCategoryKeywords(String category, List<String> keywords) {
    return _contentDoc.set(
      {
        'categories': {category: keywords},
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ---- Browser / safe-browsing policy -----------------------------------

  Stream<WebPolicy> watchPolicy() =>
      _policyDoc.snapshots().map((d) => WebPolicy.fromMap(d.data()));

  Future<void> setPolicy({
    bool? safeBrowsingEnabled,
    bool? blockOtherBrowsers,
    bool? allowIncognito,
    Set<String>? blockedCategories,
  }) {
    return _policyDoc.set(
      {
        'safeBrowsingEnabled': ?safeBrowsingEnabled,
        'blockOtherBrowsers': ?blockOtherBrowsers,
        'allowIncognito': ?allowIncognito,
        'blockedCategories': ?blockedCategories?.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ---- Retention ---------------------------------------------------------

  DocumentReference<Map<String, dynamic>> get _retentionDoc =>
      Db.instance.collection('appConfig').doc('retention');

  Stream<RetentionPolicy> watchRetention() =>
      _retentionDoc.snapshots().map((d) => RetentionPolicy.fromMap(d.data()));

  Future<RetentionPolicy> loadRetention() async {
    final snap = await _retentionDoc.get();
    return RetentionPolicy.fromMap(snap.data());
  }

  /// [days] of 0 keeps activity forever.
  Future<void> setRetentionDays(int days) => _retentionDoc.set(
        {'days': days, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  Future<void> markRetentionRun() => _retentionDoc.set(
        {'lastRunAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
}

/// How long children's activity is kept before it is deleted automatically
/// (`appConfig/retention`). Site-admin only, and global to every family.
class RetentionPolicy {
  const RetentionPolicy({this.days = 0, this.lastRunAt});

  /// 0 means "keep everything" — nothing is deleted automatically.
  final int days;
  final DateTime? lastRunAt;

  bool get enabled => days > 0;

  factory RetentionPolicy.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const RetentionPolicy();
    final at = m['lastRunAt'];
    return RetentionPolicy(
      days: (m['days'] is num) ? (m['days'] as num).toInt() : 0,
      lastRunAt: at is Timestamp ? at.toDate() : null,
    );
  }
}

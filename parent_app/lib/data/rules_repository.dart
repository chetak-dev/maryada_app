import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/screen_time_rule.dart';
import 'db.dart';

/// Reads/writes family-wide rules (screen time to start; app rules & web filter
/// to follow). Firestore: `families/{familyId}/rules/{doc}`.
class RulesRepository {
  RulesRepository._();
  static final instance = RulesRepository._();

  DocumentReference<Map<String, dynamic>> _screenTimeDoc(String familyId) =>
      Db.families.doc(familyId).collection('rules').doc('screenTime');

  Stream<ScreenTimeRule> watchScreenTime(String familyId) {
    return _screenTimeDoc(familyId).snapshots().map(
          (doc) => doc.exists
              ? ScreenTimeRule.fromMap(doc.data()!)
              : ScreenTimeRule(),
        );
  }

  Future<void> setScreenTime(String familyId, ScreenTimeRule rule) {
    return _screenTimeDoc(familyId).set(rule.toMap(), SetOptions(merge: true));
  }

  /// Pauses/unpauses the device now without touching the other rule fields.
  Future<void> setPaused(String familyId, bool paused) {
    return _screenTimeDoc(familyId)
        .set({'paused': paused}, SetOptions(merge: true));
  }
}

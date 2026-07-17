import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activity.dart';
import 'db.dart';

/// Reads the family's alert feed from `families/{familyId}/alerts`, newest
/// first. Alerts are written by the child device (blocked apps/sites, tamper,
/// Secure App Mode changes, new installs).
class AlertsRepository {
  AlertsRepository._();
  static final instance = AlertsRepository._();

  Stream<List<Alert>> watch(String familyId, {int limit = 50}) {
    return Db.families
        .doc(familyId)
        .collection('alerts')
        .orderBy('at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              final at = (m['at'] as Timestamp?)?.toDate();
              return Alert(
                alertTypeFromId(m['type'] as String?),
                (m['detail'] ?? '').toString(),
                at != null ? timeAgo(at) : 'just now',
              );
            }).toList());
  }
}

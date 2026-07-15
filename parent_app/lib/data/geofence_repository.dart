import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/geofence.dart';
import 'db.dart';

/// Reads/writes family places (geofences). Firestore:
/// `families/{familyId}/geofences/{id}`.
class GeofenceRepository {
  GeofenceRepository._();
  static final instance = GeofenceRepository._();

  CollectionReference<Map<String, dynamic>> _col(String familyId) =>
      Db.families.doc(familyId).collection('geofences');

  Stream<List<Geofence>> watch(String familyId) {
    return _col(familyId).snapshots().map(
          (s) => s.docs.map((d) => Geofence.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<void> add(String familyId, String name) {
    return _col(familyId).add({
      'name': name,
      'address': 'Tap to set location',
      'radiusMeters': 150,
      'notifyOnArrive': true,
      'notifyOnLeave': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> remove(String familyId, String id) {
    return _col(familyId).doc(id).delete();
  }
}

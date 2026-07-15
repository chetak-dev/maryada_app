import 'package:cloud_firestore/cloud_firestore.dart';

import 'db.dart';

/// One recorded location point in a child's history.
class LocationPoint {
  final double lat;
  final double lng;
  final double? accuracy;
  final String? address;
  final DateTime? at;

  const LocationPoint({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.address,
    this.at,
  });
}

/// Reads a child's location history from
/// `families/{familyId}/children/{childId}/locationHistory`.
class LocationRepository {
  LocationRepository._();
  static final instance = LocationRepository._();

  Stream<List<LocationPoint>> watchHistory(
    String familyId,
    String childId, {
    int limit = 30,
  }) {
    return Db.families
        .doc(familyId)
        .collection('children')
        .doc(childId)
        .collection('locationHistory')
        .orderBy('at', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(_fromDoc).toList());
  }

  LocationPoint _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    double? toD(dynamic v) => v is num ? v.toDouble() : null;
    return LocationPoint(
      lat: toD(m['lat']) ?? 0,
      lng: toD(m['lng']) ?? 0,
      accuracy: toD(m['locationAccuracy']),
      address: m['address'] as String?,
      at: (m['at'] as Timestamp?)?.toDate(),
    );
  }
}

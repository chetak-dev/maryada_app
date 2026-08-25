import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firebase_bootstrap.dart';

/// Guarded access to Firestore. Only touch these when
/// [FirebaseBootstrap.isReady] is true (a project is connected).
class Db {
  Db._();

  static FirebaseFirestore get instance => FirebaseFirestore.instance;
  static bool get ready => FirebaseBootstrap.isReady;

  static CollectionReference<Map<String, dynamic>> get families =>
      instance.collection('families');

  static CollectionReference<Map<String, dynamic>> children(String familyId) =>
      families.doc(familyId).collection('children');

  static CollectionReference<Map<String, dynamic>> get pairingCodes =>
      instance.collection('pairingCodes');

  /// A single child document.
  static DocumentReference<Map<String, dynamic>> child(
    String familyId,
    String childId,
  ) => children(familyId).doc(childId);

  /// The child device reports each activity feed as one document per device
  /// holding an array (web, call, SMS and YouTube history all share this
  /// shape). Builds before per-device reporting wrote a single shared
  /// `current` document, which each device overwrote.
  static CollectionReference<Map<String, dynamic>> childReports(
    String familyId,
    String childId,
    String collection,
  ) => child(familyId, childId).collection(collection);

  /// Watches those report documents and maps the array under [field] through
  /// [parse]. Entries that [parse] returns null for are dropped, so a single
  /// malformed record can't break the whole list. With [deviceId] set only
  /// that device's document is read; otherwise every device is merged.
  static Stream<List<T>> watchReportArray<T>({
    required String familyId,
    required String childId,
    required String collection,
    required String field,
    required T? Function(Map<dynamic, dynamic> entry) parse,
    String? deviceId,
    bool includeLegacyCurrent = true,
  }) {
    final reports = childReports(familyId, childId, collection);
    // `current` is the shared document single-device builds wrote; it belongs
    // to whichever device existed then, so it stays visible until that device
    // migrates it onto its own document.
    final source = deviceId == null
        ? reports.snapshots()
        : includeLegacyCurrent
        ? reports
              .where(FieldPath.documentId, whereIn: [deviceId, 'current'])
              .snapshots()
        : reports.where(FieldPath.documentId, isEqualTo: deviceId).snapshots();
    return source.map((snap) {
      final out = <T>[];
      for (final doc in snap.docs) {
        out.addAll(
          ((doc.data()[field] as List?) ?? const [])
              .whereType<Map>()
              .map(parse)
              .whereType<T>(),
        );
      }
      return out;
    });
  }

  /// Reads epoch-millis timestamps as written by the child device.
  static DateTime? millis(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
}

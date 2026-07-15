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
}

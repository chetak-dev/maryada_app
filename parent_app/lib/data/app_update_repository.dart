import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads/writes the OTA update manifest the child devices poll.
/// Firestore: `appConfig/kid` -> { enabled, versionCode, url, updatedAt }.
class AppUpdateConfig {
  final bool enabled;
  final int versionCode;
  final String url;

  const AppUpdateConfig({
    this.enabled = false,
    this.versionCode = 0,
    this.url = '',
  });
}

class AppUpdateRepository {
  AppUpdateRepository._();
  static final instance = AppUpdateRepository._();

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('appConfig').doc('kid');

  Stream<AppUpdateConfig> watch() {
    return _doc.snapshots().map((d) {
      final m = d.data();
      if (m == null) return const AppUpdateConfig();
      return AppUpdateConfig(
        enabled: m['enabled'] == true,
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        url: (m['url'] as String?) ?? '',
      );
    });
  }

  Future<void> publish(AppUpdateConfig c) {
    return _doc.set({
      'enabled': c.enabled,
      'versionCode': c.versionCode,
      'url': c.url,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

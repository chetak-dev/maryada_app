import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads/writes the OTA update manifest the child devices poll.
/// Firestore: `appConfig/{kid|parent|win}` ->
/// { enabled, versionCode, url, sha256, updatedAt }.
class AppUpdateConfig {
  final bool enabled;
  final int versionCode;
  final String url;

  /// SHA-256 of the installer. Windows PCs refuse an update without it, since
  /// a checksum is the only thing standing between the fleet and whatever the
  /// URL happens to serve.
  final String sha256;

  const AppUpdateConfig({
    this.enabled = false,
    this.versionCode = 0,
    this.url = '',
    this.sha256 = '',
  });
}

class AppUpdateRepository {
  AppUpdateRepository._();
  static final instance = AppUpdateRepository._();

  /// The child fleet's manifest.
  static const kidDoc = 'kid';

  /// The parent app's own manifest. Kept separate so publishing one can never
  /// push the wrong APK to the other.
  static const parentDoc = 'parent';

  /// The Windows child agent's manifest.
  static const windowsDoc = 'win';

  DocumentReference<Map<String, dynamic>> _ref(String id) =>
      FirebaseFirestore.instance.collection('appConfig').doc(id);

  AppUpdateConfig _parse(Map<String, dynamic>? m) {
    if (m == null) return const AppUpdateConfig();
    return AppUpdateConfig(
      enabled: m['enabled'] == true,
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      url: (m['url'] as String?) ?? '',
      sha256: (m['sha256'] as String?) ?? '',
    );
  }

  Stream<AppUpdateConfig> watch([String id = kidDoc]) =>
      _ref(id).snapshots().map((d) => _parse(d.data()));

  Future<AppUpdateConfig> load(String id) async =>
      _parse((await _ref(id).get()).data());

  Future<void> publish(AppUpdateConfig c, [String id = kidDoc]) {
    return _ref(id).set({
      'enabled': c.enabled,
      'versionCode': c.versionCode,
      'url': c.url,
      'sha256': c.sha256,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

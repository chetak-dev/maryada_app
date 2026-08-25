import 'package:package_info_plus/package_info_plus.dart';

/// The running build's own version, read from the installed package rather
/// than a constant — a hand-maintained copy drifts, and the whole point is to
/// know exactly which build a device is on.
class AppVersion {
  AppVersion._();

  /// "v1.0.0(1000)": the name people read plus the real build number.
  static String label = '';

  /// The build number Android compares when deciding whether an APK is newer.
  static int build = 0;

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      label = 'v${info.version}(${info.buildNumber})';
      build = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      label = '';
      build = 0;
    }
  }
}

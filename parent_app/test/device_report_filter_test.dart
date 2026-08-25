import 'package:flutter_test/flutter_test.dart';
import 'package:guardnest_parent/data/app_rules_repository.dart';

void main() {
  group('installed app report filtering', () {
    test('selected Windows PC sees only its own report', () {
      expect(
        acceptsInstalledAppsReport(
          'installedApps-pc123',
          deviceId: 'pc123',
          platform: 'windows',
        ),
        isTrue,
      );
      expect(
        acceptsInstalledAppsReport(
          'installedApps',
          deviceId: 'pc123',
          platform: 'windows',
        ),
        isFalse,
      );
      expect(
        acceptsInstalledAppsReport(
          'installedApps-phone456',
          deviceId: 'pc123',
          platform: 'windows',
        ),
        isFalse,
      );
    });

    test('selected Android device retains its legacy shared report', () {
      expect(
        acceptsInstalledAppsReport(
          'installedApps',
          deviceId: 'phone456',
          platform: 'android',
        ),
        isTrue,
      );
    });

    test('family view merges every installed-app report', () {
      expect(acceptsInstalledAppsReport('installedApps'), isTrue);
      expect(acceptsInstalledAppsReport('installedApps-pc123'), isTrue);
      expect(acceptsInstalledAppsReport('otherReport'), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:guardnest_parent/models/device.dart';

Device deviceWith({
  String id = 'd1',
  String platform = 'android',
  Map<String, bool> protections = const {'accessibility': true},
  Duration? silentFor,
  bool adminActive = true,
  String? lastError,
  Duration? errorAgo,
}) {
  final now = DateTime.now();
  return Device(
    id: id,
    deviceModel: 'Test $id',
    platform: platform,
    protections: protections,
    adminActive: adminActive,
    lastSeenAt: silentFor == null ? now : now.subtract(silentFor),
    lastError: lastError,
    lastErrorAt: errorAgo == null ? null : now.subtract(errorAgo),
  );
}

void main() {
  group('status wording', () {
    test('a missing permission outranks silence', () {
      // Two devices in the very same state used to read as two different
      // problems purely because one had also gone quiet.
      final quiet = deviceWith(
        protections: const {'accessibility': false},
        silentFor: const Duration(hours: 5),
      );
      final chatty = deviceWith(protections: const {'accessibility': false});

      expect(quiet.statusLabel, 'Permission missing');
      expect(chatty.statusLabel, 'Permission missing');
    });

    test('a healthy phone quiet for two hours is not reporting', () {
      expect(
        deviceWith(silentFor: const Duration(hours: 2)).statusLabel,
        'Not reporting',
      );
    });

    test('a PC switched off overnight is not an alarm', () {
      // A PC is switched off every night; an hour of quiet says nothing.
      expect(
        deviceWith(platform: 'windows', silentFor: const Duration(hours: 3))
            .statusLabel,
        'Protected',
      );
      expect(
        deviceWith(platform: 'windows', silentFor: const Duration(hours: 20))
            .statusLabel,
        'Not reporting',
      );
    });

    test('device admin off still wins', () {
      final device = deviceWith(
        adminActive: false,
        protections: const {'accessibility': false},
      );
      expect(device.statusLabel, startsWith('Protection turned off'));
    });

    test('missing protections are named', () {
      final device = deviceWith(
        protections: const {'accessibility': false, 'monitoring': true},
      );
      expect(device.missingProtectionLabels, ['App blocking']);
    });
  });

  group('profile status across devices', () {
    test('the worst device decides what the profile shows', () {
      final devices = [
        deviceWith(id: 'phone'),
        deviceWith(id: 'pc', protections: const {'service': false}),
      ];
      expect(ProfileStatus.worst(devices)?.id, 'pc');
      expect(ProfileStatus.faulty(devices)?.id, 'pc');
    });

    test('a healthy profile has nothing to act on', () {
      final devices = [deviceWith(id: 'phone'), deviceWith(id: 'pc')];
      expect(ProfileStatus.faulty(devices), isNull);
    });

    test('no devices means no status', () {
      expect(ProfileStatus.worst(const []), isNull);
    });
  });

  group('device error breadcrumb', () {
    test('a heartbeat after the failure clears it', () {
      final device = deviceWith(
        lastError: 'heartbeat: UNAVAILABLE',
        errorAgo: const Duration(hours: 3),
      );
      expect(device.hasRecentError, isFalse);
    });

    test('an unresolved recent failure is shown', () {
      final device = deviceWith(
        lastError: 'heartbeat: UNAVAILABLE',
        errorAgo: const Duration(minutes: 5),
        silentFor: const Duration(minutes: 30),
      );
      expect(device.hasRecentError, isTrue);
    });
  });
}

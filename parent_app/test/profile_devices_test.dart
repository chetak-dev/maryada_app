import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardnest_parent/data/family_repository.dart';

/// A device entry as it sits in the profile's `devices` map.
Map<String, dynamic> entry({
  required String model,
  DateTime? seenAt,
  bool revoked = false,
}) => {
  'deviceModel': model,
  'platform': 'android',
  'adminActive': true,
  'protections': {'accessibility': true},
  if (seenAt != null) 'lastSeenAt': Timestamp.fromDate(seenAt),
  if (revoked) 'revoked': true,
};

void main() {
  final now = DateTime.now();
  final stale = now.subtract(const Duration(days: 2));
  final fresh = now.subtract(const Duration(minutes: 3));

  group('devices from the profile map', () {
    test('revoked installations are left out', () {
      final devices = FamilyRepository.devicesFromMap({
        'a': entry(model: 'Pixel', seenAt: fresh),
        'b': entry(model: 'Old phone', seenAt: fresh, revoked: true),
      });
      expect(devices.map((d) => d.id), ['a']);
    });

    test('a lone device inherits the profile heartbeat when it is newer', () {
      // What a phone on a pre-devices-map build looks like: its own entry was
      // frozen when it was backfilled, but the profile is still being stamped.
      final devices = FamilyRepository.devicesFromMap({
        'a': entry(model: 'vivo I2011', seenAt: stale),
      }, fresh);
      expect(devices.single.lastSeenAt, fresh);
      expect(devices.single.isSilent, isFalse,
          reason: 'a healthy phone must not read as "not reporting"');
    });

    test('a lone device keeps its own heartbeat when that is newer', () {
      final devices = FamilyRepository.devicesFromMap({
        'a': entry(model: 'Pixel', seenAt: fresh),
      }, stale);
      expect(devices.single.lastSeenAt, fresh);
    });

    test('the profile heartbeat is ignored once there are two devices', () {
      // It only tells us *something* reported, not which — crediting both
      // would hide a device that really has gone quiet.
      final devices = FamilyRepository.devicesFromMap({
        'a': entry(model: 'Pixel', seenAt: stale),
        'b': entry(model: 'ZBook', seenAt: stale),
      }, fresh);
      expect(devices.every((d) => d.lastSeenAt == stale), isTrue);
    });

    test('a revoked sibling still counts as a single live device', () {
      final devices = FamilyRepository.devicesFromMap({
        'a': entry(model: 'vivo I2011', seenAt: stale),
        'b': entry(model: 'Old PC', seenAt: stale, revoked: true),
      }, fresh);
      expect(devices.single.lastSeenAt, fresh);
    });

    test('no map at all means no devices', () {
      expect(FamilyRepository.devicesFromMap(null), isEmpty);
      expect(FamilyRepository.devicesFromMap('nonsense'), isEmpty);
    });
  });
}

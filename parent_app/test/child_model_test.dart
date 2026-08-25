// Unit tests for the parent app's pure model logic — the parts that decide what
// a guardian is told about a device without going near Firestore.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardnest_parent/models/child.dart';

Child childWith({
  ChildStatus status = ChildStatus.online,
  DateTime? lastSeenAt,
  String? lastError,
  DateTime? lastErrorAt,
  Map<String, bool> protections = const {},
}) {
  return Child(
    id: 'c1',
    name: 'Aarav',
    deviceModel: 'Test device',
    avatarColor: const Color(0xFF4F46E5),
    status: status,
    lastSeenAt: lastSeenAt,
    lastError: lastError,
    lastErrorAt: lastErrorAt,
    protections: protections,
  );
}

void main() {
  group('heartbeat freshness', () {
    test('a device that never reported is stale', () {
      expect(childWith().isStale, isTrue);
    });

    test('a recent heartbeat is fresh', () {
      final child = childWith(
        lastSeenAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(child.isStale, isFalse);
      expect(child.effectiveStatus, ChildStatus.online);
    });

    test('a silent device is still shown by its permissions', () {
      // Phones kill background services, so a missed heartbeat used to flip a
      // perfectly protected child to "offline". Silence is surfaced as a "last
      // seen" line instead; only a missing permission changes the status.
      final child = childWith(
        status: ChildStatus.online,
        lastSeenAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(child.isStale, isTrue);
      expect(child.effectiveStatus, ChildStatus.online);
    });

    test('an unpaired device stays offline', () {
      final child = childWith(
        status: ChildStatus.offline,
        lastSeenAt: DateTime.now(),
      );
      expect(child.effectiveStatus, ChildStatus.offline);
    });
  });

  group('device error breadcrumb', () {
    test('no error means nothing to show', () {
      expect(childWith().hasRecentError, isFalse);
      expect(
        childWith(lastError: '', lastErrorAt: DateTime.now()).hasRecentError,
        isFalse,
      );
    });

    test('an error without a timestamp is not shown', () {
      expect(childWith(lastError: 'tick: boom').hasRecentError, isFalse);
    });

    test('a fresh error is shown', () {
      final child = childWith(
        lastError: 'heartbeat: PERMISSION_DENIED',
        lastErrorAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(child.hasRecentError, isTrue);
    });

    test('a day-old error is no longer shown', () {
      final child = childWith(
        lastError: 'heartbeat: PERMISSION_DENIED',
        lastErrorAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(child.hasRecentError, isFalse);
    });
  });

  group('protections', () {
    test('lists only the ones that are off', () {
      final child = childWith(protections: const {
        'accessibility': true,
        'usage': false,
        'notifications': false,
      });
      expect(child.offProtections, containsAll(['usage', 'notifications']));
      expect(child.offProtections, isNot(contains('accessibility')));
    });
  });

  group('initials', () {
    test('uses the first letter, uppercased', () {
      expect(childWith().initials, 'A');
    });

    test('falls back when the name is blank', () {
      final child = Child(
        id: 'c1',
        name: '   ',
        deviceModel: '',
        avatarColor: const Color(0xFF4F46E5),
        status: ChildStatus.offline,
      );
      expect(child.initials, '?');
    });
  });
}

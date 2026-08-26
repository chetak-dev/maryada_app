import 'package:flutter_test/flutter_test.dart';
import 'package:guardnest_parent/data/reporting_cadence.dart';

void main() {
  group('heartbeat cadence', () {
    test('a small household reports at the fastest allowed rate', () {
      expect(ReportingCadence.forChildCount(1), ReportingCadence.floor);
      expect(ReportingCadence.forChildCount(6), ReportingCadence.floor);
      expect(ReportingCadence.forChildCount(20), ReportingCadence.floor);
    });

    test('the interval grows with the number of profiles', () {
      final at25 = ReportingCadence.forChildCount(25);
      final at50 = ReportingCadence.forChildCount(50);
      expect(at25, greaterThan(ReportingCadence.floor));
      expect(at50, greaterThan(at25));
      expect(at50, lessThanOrEqualTo(ReportingCadence.ceiling));
    });

    test('a big family is still inside the free tier', () {
      final interval = ReportingCadence.forChildCount(50);
      final perDevice = Duration.millisecondsPerDay / interval.inMilliseconds;
      expect((perDevice * 50).round(),
          lessThanOrEqualTo(ReportingCadence.dailyWriteBudget));
    });

    test('never slower than the ceiling, however many profiles', () {
      expect(ReportingCadence.forChildCount(500), ReportingCadence.ceiling);
    });

    test('an empty or unknown count falls back to the safest rate', () {
      expect(ReportingCadence.forChildCount(0), ReportingCadence.ceiling);
      expect(ReportingCadence.forChildCount(-3), ReportingCadence.ceiling);
    });
  });
}

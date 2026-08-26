/// How often each child device should report that it is alive.
///
/// Firestore's free tier allows 20,000 writes a day for the whole project, and
/// every heartbeat is one write. The more devices share that allowance, the
/// less often each one may speak — so the cadence is derived from the number of
/// profiles rather than fixed, and a small household gets a much fresher screen
/// than a large one without anybody having to tune it.
class ReportingCadence {
  ReportingCadence._();

  /// Heartbeat writes a day for the whole family. The rest of the allowance is
  /// left for activity (web, calls, messages), which only writes when there is
  /// something new to say.
  static const dailyWriteBudget = 6000;

  /// Never faster than this: the gain in freshness stops being visible to a
  /// parent well before the cost in battery and radio wake-ups does.
  static const floor = Duration(minutes: 5);

  /// Never slower than this. A device is called "not reporting" after an hour
  /// of silence, so the slowest cadence still leaves room for three missed
  /// beats before a healthy phone would be accused of being offline.
  static const ceiling = Duration(minutes: 20);

  /// The interval for a family of [childCount] profiles, clamped to
  /// [floor]..[ceiling].
  static Duration forChildCount(int childCount) {
    if (childCount <= 0) return ceiling;
    final perDevicePerDay = dailyWriteBudget / childCount;
    final ms = Duration.millisecondsPerDay / perDevicePerDay;
    if (ms <= floor.inMilliseconds) return floor;
    if (ms >= ceiling.inMilliseconds) return ceiling;
    return Duration(milliseconds: ms.round());
  }
}

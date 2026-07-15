/// Screen-time rule for a child (UI model). Times are "minutes from midnight"
/// (0..1439) so they're timezone-agnostic and easy to compare on-device later.
class ScreenTimeRule {
  int dailyLimitMinutes;
  bool bedtimeEnabled;
  int bedtimeStart; // minutes from midnight
  int bedtimeEnd;
  bool paused;

  ScreenTimeRule({
    this.dailyLimitMinutes = 120,
    this.bedtimeEnabled = false,
    this.bedtimeStart = 21 * 60, // 21:00
    this.bedtimeEnd = 7 * 60, // 07:00
    this.paused = false,
  });

  ScreenTimeRule copy() => ScreenTimeRule(
        dailyLimitMinutes: dailyLimitMinutes,
        bedtimeEnabled: bedtimeEnabled,
        bedtimeStart: bedtimeStart,
        bedtimeEnd: bedtimeEnd,
        paused: paused,
      );

  factory ScreenTimeRule.fromMap(Map<String, dynamic> map) => ScreenTimeRule(
        dailyLimitMinutes:
            (map['dailyLimitMinutes'] is int) ? map['dailyLimitMinutes'] : 120,
        bedtimeEnabled: map['bedtimeEnabled'] == true,
        bedtimeStart: (map['bedtimeStart'] is int) ? map['bedtimeStart'] : 21 * 60,
        bedtimeEnd: (map['bedtimeEnd'] is int) ? map['bedtimeEnd'] : 7 * 60,
        paused: map['paused'] == true,
      );

  Map<String, dynamic> toMap() => {
        'dailyLimitMinutes': dailyLimitMinutes,
        'bedtimeEnabled': bedtimeEnabled,
        'bedtimeStart': bedtimeStart,
        'bedtimeEnd': bedtimeEnd,
        'paused': paused,
      };
}

namespace GuardNest.Core.Rules;

/// <summary>
/// Screen-time enforcement, ported from ScreenGuard.kt so both platforms lock at
/// exactly the same moments. Pure decisions, evaluated against the local clock so
/// they hold with no network.
/// </summary>
public static class ScreenGuard
{
    /// <summary>True when <paramref name="now"/> falls in [start, end), handling
    /// overnight windows like 21:00 -> 07:00.</summary>
    public static bool IsWithinWindow(int now, int start, int end)
    {
        if (start == end) return false;
        return start < end ? now >= start && now < end : now >= start || now < end;
    }

    public static int NowMinutes() => DateTime.Now.Hour * 60 + DateTime.Now.Minute;

    public static bool ShouldLock(ScreenTimeRule rule, int usedMinutesToday, int? now = null)
    {
        if (rule.Paused) return true;
        if (rule.DailyLimitMinutes > 0 && usedMinutesToday >= rule.DailyLimitMinutes) return true;
        if (!rule.BedtimeEnabled) return false;
        return IsWithinWindow(now ?? NowMinutes(), rule.BedtimeStart, rule.BedtimeEnd);
    }

    /// <summary>The two lines the lock screen shows, so every surface agrees.</summary>
    public static (string Title, string Subtitle) LockText(ScreenTimeRule rule, int usedMinutesToday)
    {
        if (rule.Paused)
        {
            return ("Paused", "Your device is paused by your parent.");
        }
        if (rule.DailyLimitMinutes > 0 && usedMinutesToday >= rule.DailyLimitMinutes)
        {
            return ("Screen time is up",
                $"You have used your {Describe(rule.DailyLimitMinutes)} for today.");
        }
        return ("Bedtime", $"Your device rests from {Clock(rule.BedtimeStart)} to {Clock(rule.BedtimeEnd)}.");
    }

    private static string Clock(int minutes) =>
        DateTime.Today.AddMinutes(minutes).ToString("h:mm tt");

    private static string Describe(int minutes) => minutes switch
    {
        < 60 => $"{minutes} minutes",
        60 => "1 hour",
        _ when minutes % 60 == 0 => $"{minutes / 60} hours",
        _ => $"{minutes / 60}h {minutes % 60}m",
    };
}

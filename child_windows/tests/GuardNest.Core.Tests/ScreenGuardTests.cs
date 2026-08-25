using GuardNest.Core.Apps;
using GuardNest.Core.Rules;

namespace GuardNest.Core.Tests;

public class ScreenGuardTests
{
    [Theory]
    [InlineData(600, 540, 660, true)]   // inside a daytime window
    [InlineData(700, 540, 660, false)]  // after it
    [InlineData(500, 540, 660, false)]  // before it
    [InlineData(1380, 1260, 420, true)] // 23:00 inside 21:00 -> 07:00
    [InlineData(120, 1260, 420, true)]  // 02:00 inside the same overnight window
    [InlineData(600, 1260, 420, false)] // 10:00 outside it
    public void IsWithinWindow_handles_overnight(int now, int start, int end, bool expected) =>
        Assert.Equal(expected, ScreenGuard.IsWithinWindow(now, start, end));

    [Fact]
    public void A_window_of_zero_length_never_matches() =>
        Assert.False(ScreenGuard.IsWithinWindow(600, 600, 600));

    [Fact]
    public void Pause_locks_regardless_of_the_clock()
    {
        var rule = new ScreenTimeRule(Paused: true);
        Assert.True(ScreenGuard.ShouldLock(rule, usedMinutesToday: 0, now: 600));
    }

    [Fact]
    public void Reaching_the_daily_limit_locks()
    {
        var rule = new ScreenTimeRule(DailyLimitMinutes: 60);
        Assert.False(ScreenGuard.ShouldLock(rule, usedMinutesToday: 59, now: 600));
        Assert.True(ScreenGuard.ShouldLock(rule, usedMinutesToday: 60, now: 600));
    }

    [Fact]
    public void A_daily_limit_of_zero_means_no_limit()
    {
        var rule = new ScreenTimeRule(DailyLimitMinutes: 0);
        Assert.False(ScreenGuard.ShouldLock(rule, usedMinutesToday: 900, now: 600));
    }

    [Fact]
    public void Bedtime_only_applies_when_enabled()
    {
        var off = new ScreenTimeRule(BedtimeEnabled: false, BedtimeStart: 1260, BedtimeEnd: 420);
        var on = off with { BedtimeEnabled = true };
        Assert.False(ScreenGuard.ShouldLock(off, 0, now: 1380));
        Assert.True(ScreenGuard.ShouldLock(on, 0, now: 1380));
    }
}

public class AppRuleTests
{
    [Theory]
    [InlineData("chrome", "chrome.exe")]
    [InlineData("Chrome.EXE", "chrome.exe")]
    [InlineData(@"C:\Program Files\Google\Chrome\Application\chrome.exe", "chrome.exe")]
    public void Executable_keys_are_normalised(string input, string expected) =>
        Assert.Equal(expected, InstalledApps.ExecutableKey(input));

    [Fact]
    public void Blocked_lookup_ignores_case()
    {
        var rules = new AppRules(new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "chrome.exe" });
        Assert.True(rules.IsBlocked("CHROME.EXE"));
        Assert.False(rules.IsBlocked("firefox.exe"));
    }

    [Fact]
    public void Critical_windows_processes_are_never_blockable()
    {
        Assert.True(ProcessGuard.IsProtected("explorer.exe"));
        Assert.True(ProcessGuard.IsProtected("winlogon.exe"));
        Assert.True(ProcessGuard.IsProtected("guardnest.agent.exe"));
        Assert.False(ProcessGuard.IsProtected("chrome.exe"));
    }

    [Fact]
    public void Enforcing_an_empty_rule_set_stops_nothing() =>
        Assert.Empty(AppBlocker.Enforce(AppRules.Empty));

    [Fact]
    public void Pc_browsers_are_removed_from_block_rules()
    {
        var blocked = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "chrome.exe", "firefox.exe", "game.exe",
        };

        var effective = Browsers.RemoveFrom(blocked);

        Assert.DoesNotContain("chrome.exe", effective);
        Assert.DoesNotContain("firefox.exe", effective);
        Assert.Contains("game.exe", effective);
    }
}

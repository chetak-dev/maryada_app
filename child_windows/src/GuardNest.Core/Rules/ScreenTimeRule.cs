namespace GuardNest.Core.Rules;

/// <summary>
/// The family's screen-time rule. Minutes-from-midnight matches the parent app's
/// model, so both sides speak the same language.
/// </summary>
public sealed record ScreenTimeRule(
    int DailyLimitMinutes = 120,
    bool BedtimeEnabled = false,
    int BedtimeStart = 21 * 60,
    int BedtimeEnd = 7 * 60,
    bool Paused = false);

/// <summary>Blocked executables, merged from the family-wide and per-child rules.</summary>
public sealed record AppRules(IReadOnlySet<string> Blocked)
{
    public static readonly AppRules Empty =
        new(new HashSet<string>(StringComparer.OrdinalIgnoreCase));

    public bool IsBlocked(string executable) => Blocked.Contains(executable);
}

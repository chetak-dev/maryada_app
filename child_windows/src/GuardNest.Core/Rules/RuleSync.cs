using GuardNest.Core.Firebase;

namespace GuardNest.Core.Rules;

/// <summary>
/// Pulls the family's rules from Firestore. Blocks are the union of the
/// family-wide rules and this child's own, matching applyMergedAppRules() on
/// Android: an app is blocked when either says so.
/// </summary>
public sealed class RuleSync
{
    private readonly FirestoreClient _firestore;

    public RuleSync(FirestoreClient firestore)
    {
        _firestore = firestore;
    }

    public ScreenTimeRule ScreenTime { get; private set; } = new();
    public AppRules Apps { get; private set; } = AppRules.Empty;
    public DateTimeOffset? LastSyncedAt { get; private set; }

    public async Task RefreshAsync(DeviceState state, CancellationToken ct)
    {
        var rule = await _firestore.GetAsync($"families/{state.FamilyId}/rules/screenTime", ct);
        if (rule is not null)
        {
            ScreenTime = new ScreenTimeRule(
                DailyLimitMinutes: rule.GetInt("dailyLimitMinutes", 120),
                BedtimeEnabled: rule.GetBool("bedtimeEnabled"),
                BedtimeStart: rule.GetInt("bedtimeStart", 21 * 60),
                BedtimeEnd: rule.GetInt("bedtimeEnd", 7 * 60),
                Paused: rule.GetBool("paused"));
        }

        var blocked = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var document in await _firestore.ListAsync($"families/{state.FamilyId}/appRules", ct))
        {
            if (document.GetBool("blocked")) blocked.Add(document.Id);
        }
        foreach (var document in await _firestore.ListAsync(
                     $"families/{state.FamilyId}/children/{state.ChildId}/appRules", ct))
        {
            if (document.GetBool("blocked")) blocked.Add(document.Id);
        }

        Apps = new AppRules(blocked);
        LastSyncedAt = DateTimeOffset.UtcNow;
    }
}

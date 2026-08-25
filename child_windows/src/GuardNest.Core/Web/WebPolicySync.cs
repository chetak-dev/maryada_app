using GuardNest.Core.Firebase;

namespace GuardNest.Core.Web;

/// <summary>
/// Keeps the filter in step with Firestore: the family's own blocked sites, and
/// the site admin's global browser policy and keyword lists. Safe browsing and
/// the protective categories are deliberately not configurable — they are the
/// reason the app is installed.
/// </summary>
public sealed class WebPolicySync
{
    private readonly FirestoreClient _firestore;
    private readonly WebFilter _filter;
    private readonly CategoryFeed _categories;

    public WebPolicySync(FirestoreClient firestore, WebFilter filter, CategoryFeed categories)
    {
        _firestore = firestore;
        _filter = filter;
        _categories = categories;
    }

    public async Task RefreshAsync(DeviceState state, CancellationToken ct)
    {
        var sites = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var rule = await _firestore.GetAsync($"families/{state.FamilyId}/rules/webFilter", ct);
        if (rule is not null)
        {
            foreach (var entry in rule.GetList("blockedSites"))
            {
                var domain = Domains.Normalize(entry as string ?? "");
                if (domain.Length > 0) sites.Add(domain);
            }
        }

        var policyDoc = await _firestore.GetAsync("appConfig/webPolicy", ct);
        _filter.Apply(new WebPolicy(
            BlockedSites: sites,
            BlockedCategories: WebFilter.ProtectiveCategories,
            // PC policy: every browser stays available; the agent observes
            // supported address bars and records their browsing history.
            BlockOtherBrowsers: false,
            AllowIncognito: policyDoc?.GetBool("allowIncognito") ?? false,
            ApprovedBrowser: NormaliseBrowser(policyDoc?.GetString("approvedBrowserWindows")),
            BlockYoutubeWeb: false));

        _filter.ApplyKeywords(await LoadKeywordsAsync(ct));

        // Fire and forget: the seeds already block the obvious cases, so a slow
        // feed must not delay the enforcement loop.
        _ = _categories.EnsureAsync(WebFilter.ProtectiveCategories, ct);
    }

    private async Task<IReadOnlySet<string>> LoadKeywordsAsync(CancellationToken ct)
    {
        var words = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var content = await _firestore.GetAsync("appConfig/contentFilter", ct);
        if (content is null) return words;

        void Collect(IReadOnlyList<object?> list)
        {
            foreach (var item in list)
            {
                var word = (item as string)?.Trim();
                // Anything shorter is a fragment that would match half the web.
                if (word is { Length: >= 3 }) words.Add(word.ToLowerInvariant());
            }
        }

        Collect(content.GetList("keywords"));
        if (content.Fields.GetValueOrDefault("categories") is IReadOnlyDictionary<string, object?> categories)
        {
            foreach (var entry in categories.Values)
            {
                if (entry is IReadOnlyList<object?> list) Collect(list);
            }
        }
        return words;
    }

    private static string NormaliseBrowser(string? configured) =>
        string.IsNullOrWhiteSpace(configured)
            ? WebPolicy.Default.ApprovedBrowser
            : Apps.InstalledApps.ExecutableKey(configured);
}

namespace GuardNest.Core.Web;

/// <summary>Why a page was refused, mirroring the reasons the parent app labels.</summary>
public static class BlockReason
{
    public const string Blocklist = "blocklist";
    public const string Keyword = "keyword";
    public const string Youtube = "youtube";
}

/// <summary>One consistent view of the filter, replaced wholesale rather than mutated.</summary>
public sealed record WebPolicy(
    IReadOnlySet<string> BlockedSites,
    IReadOnlySet<string> BlockedCategories,
    bool BlockOtherBrowsers,
    bool AllowIncognito,
    string ApprovedBrowser,
    bool BlockYoutubeWeb)
{
    /// <summary>
    /// YouTube in a browser is blocked on Android so the child uses the app,
    /// where the parent can see what was watched. Windows has no such app, so
    /// the same rule would ban YouTube outright instead of redirecting it; the
    /// default here is to allow it and capture the watch history from the
    /// window title. A site admin can still switch the ban on.
    /// </summary>
    public static readonly WebPolicy Default = new(
        new HashSet<string>(StringComparer.OrdinalIgnoreCase),
        WebFilter.ProtectiveCategories,
        BlockOtherBrowsers: false,
        AllowIncognito: false,
        ApprovedBrowser: "msedge.exe",
        BlockYoutubeWeb: false);
}

/// <summary>
/// The blocking decision, ported from WebFilter.kt. Reading one immutable
/// snapshot per decision means a policy update can never be observed half
/// applied — new categories with the old site list, say.
/// </summary>
public sealed class WebFilter
{
    /// Blocked for everyone, always; not even the site admin can turn these off.
    public static readonly IReadOnlySet<string> ProtectiveCategories =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "adult", "gambling", "drugs", "weapons", "violence",
        };

    /// Blocking the canonical domain has to block the alias too.
    private static readonly Dictionary<string, string> Aliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["youtu.be"] = "youtube.com",
    };

    private static readonly HashSet<string> YoutubeWeb = new(StringComparer.OrdinalIgnoreCase)
    {
        "youtube.com", "youtu.be", "youtube-nocookie.com", "youtubekids.com",
    };

    private static readonly HashSet<string> SearchEngines = new(StringComparer.OrdinalIgnoreCase)
    {
        "bing.com", "duckduckgo.com", "search.yahoo.com", "ecosia.org",
        "startpage.com", "qwant.com", "baidu.com", "ask.com",
        "search.brave.com", "searx.be", "swisscows.com", "mojeek.com",
    };

    private readonly CategoryFeed _categories;
    private volatile WebPolicy _policy = WebPolicy.Default;
    private volatile IReadOnlySet<string> _keywords =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    public WebFilter(CategoryFeed categories)
    {
        _categories = categories;
    }

    public WebPolicy Policy => _policy;

    public void Apply(WebPolicy policy) => _policy = policy;

    public void ApplyKeywords(IReadOnlySet<string> keywords) => _keywords = keywords;

    /// <summary>True for a results page, whose link snippets must not be keyword-matched.</summary>
    public static bool IsSearchEngine(string host)
    {
        var value = Domains.Normalize(host);
        if (value == "google.com" || value.StartsWith("google.") || value.Contains(".google.")) return true;
        if (value.StartsWith("yandex.")) return true;
        return SearchEngines.Any(engine => Domains.Covers(engine, value));
    }

    public static bool IsYoutube(string host)
    {
        var value = Domains.Normalize(host);
        return YoutubeWeb.Any(domain => Domains.Covers(domain, value));
    }

    public string? ReasonFor(string address) => ReasonFor(address, "");

    /// <summary>
    /// Why this address is refused, or null when it is allowed. Keywords are
    /// looked for in the page itself, not just the address: the words that make
    /// a page unsafe are usually in its text and its title and nowhere in the
    /// URL. Reading the rendered page is also what makes this work over HTTPS.
    /// </summary>
    public string? ReasonFor(string address, string pageTitle, string pageText = "")
    {
        var host = Domains.HostOf(address);
        if (host.Length == 0) return null;

        // Windows has no separate YouTube app to redirect into. Always allow
        // browser YouTube and capture its searches/watch history instead.
        if (IsYoutube(host)) return null;

        var policy = _policy;
        if (Domains.MatchesAny(host, policy.BlockedSites)) return BlockReason.Blocklist;
        if (Aliases.TryGetValue(host, out var canonical) &&
            Domains.MatchesAny(canonical, policy.BlockedSites))
        {
            return BlockReason.Blocklist;
        }

        var category = _categories.CategoryOf(host, policy.BlockedCategories);
        if (category is not null) return category;

        // A results page lists other people's words; matching keywords there
        // would block the search itself rather than anything the child opened.
        if (IsSearchEngine(host)) return null;
        return KeywordIn(Unescape(address)) ?? KeywordIn(pageTitle) ?? KeywordIn(pageText);
    }

    private string? KeywordIn(string content)
    {
        var keywords = _keywords;
        if (keywords.Count == 0 || content.Length == 0) return null;
        var text = content.ToLowerInvariant();
        return keywords.Any(word => ContainsWord(text, word)) ? BlockReason.Keyword : null;
    }

    private static string Unescape(string address)
    {
        // A percent sign that is not a valid escape is ordinary text here.
        try { return Uri.UnescapeDataString(address); }
        catch (UriFormatException) { return address; }
    }

    /// <summary>
    /// Whole-word match only. A plain substring test blocks essex.gov.uk for
    /// "sex", and a parental control that blocks a council website is one the
    /// family switches off.
    /// </summary>
    internal static bool ContainsWord(string text, string word)
    {
        if (word.Length == 0) return false;
        var index = text.IndexOf(word, StringComparison.Ordinal);
        while (index >= 0)
        {
            var beforeOk = index == 0 || !char.IsLetterOrDigit(text[index - 1]);
            var end = index + word.Length;
            var afterOk = end >= text.Length || !char.IsLetterOrDigit(text[end]);
            if (beforeOk && afterOk) return true;
            index = text.IndexOf(word, index + 1, StringComparison.Ordinal);
        }
        return false;
    }

    /// <summary>A label for the parent's activity list, even for a manually listed site.</summary>
    public string? CategoryHint(string host) =>
        _categories.CategoryOfAny(Domains.Normalize(host));
}

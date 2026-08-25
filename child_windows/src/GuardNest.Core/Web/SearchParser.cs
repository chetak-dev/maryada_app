using System.Collections.Specialized;
using System.Text.RegularExpressions;
using System.Web;

namespace GuardNest.Core.Web;

/// <summary>One submitted search, as the parent's activity list shows it.</summary>
public sealed record WebSearch(string Query, string Engine);

/// <summary>
/// Recognises a search-results address. Only a submitted results page counts —
/// omnibox suggestions would otherwise report every keystroke as a search.
/// </summary>
public static class SearchParser
{
    private static readonly (string Host, string Engine, string[] Keys)[] Engines =
    {
        ("google.", "Google", new[] { "q" }),
        ("bing.com", "Bing", new[] { "q" }),
        ("duckduckgo.com", "DuckDuckGo", new[] { "q" }),
        ("search.yahoo.com", "Yahoo", new[] { "p", "q" }),
        ("ecosia.org", "Ecosia", new[] { "q" }),
        ("search.brave.com", "Brave", new[] { "q" }),
        ("startpage.com", "Startpage", new[] { "query", "q" }),
        ("qwant.com", "Qwant", new[] { "q" }),
        ("yandex.", "Yandex", new[] { "text" }),
        ("youtube.com", "YouTube", new[] { "search_query", "q" }),
    };

    public static WebSearch? Parse(string address)
    {
        var value = address.Trim();
        if (value.Length == 0) return null;
        if (!value.Contains("://")) value = "https://" + value;
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return null;

        var host = Domains.Normalize(uri.Host);
        var match = Engines.FirstOrDefault(engine =>
            engine.Host.EndsWith('.')
                ? host.StartsWith(engine.Host, StringComparison.Ordinal) || host.Contains("." + engine.Host, StringComparison.Ordinal)
                : Domains.Covers(engine.Host, host));
        if (match.Engine is null) return null;

        NameValueCollection query;
        try { query = HttpUtility.ParseQueryString(uri.Query); }
        catch (Exception e) when (e is ArgumentException or UriFormatException) { return null; }

        foreach (var key in match.Keys)
        {
            var term = query[key]?.Trim();
            // Long strings here are pasted URLs or tracking blobs, not searches.
            if (term is { Length: >= 2 and <= 300 }) return new WebSearch(term, match.Engine);
        }
        return null;
    }

    /// Chrome and Firefox replace the address with the search terms once a
    /// results page loads, so the URL is gone and the title is all that is left.
    private static readonly (Regex Pattern, string Engine)[] TitlePatterns =
    {
        (new Regex(@"^(?<q>.+?)\s+-\s+Google\s+Search$", RegexOptions.IgnoreCase | RegexOptions.Compiled), "Google"),
        (new Regex(@"^(?<q>.+?)\s+-\s+(Bing|Bing\s+Search)$", RegexOptions.IgnoreCase | RegexOptions.Compiled), "Bing"),
        (new Regex(@"^(?<q>.+?)\s+at\s+DuckDuckGo$", RegexOptions.IgnoreCase | RegexOptions.Compiled), "DuckDuckGo"),
        (new Regex(@"^(?<q>.+?)\s+-\s+Yahoo\s+Search\s+Results$", RegexOptions.IgnoreCase | RegexOptions.Compiled), "Yahoo"),
        (new Regex(@"^(?<q>.+?)\s+-\s+Ecosia$", RegexOptions.IgnoreCase | RegexOptions.Compiled), "Ecosia"),
        (new Regex(@"^(?<q>.+?)\s+-\s+Brave\s+Search$", RegexOptions.IgnoreCase | RegexOptions.Compiled), "Brave"),
        (new Regex(@"^(?<q>.+?)\s+-\s+Startpage\s+Search\s+Results$", RegexOptions.IgnoreCase | RegexOptions.Compiled), "Startpage"),
        (new Regex(@"^(?<q>.+?)\s+—\s+Yandex", RegexOptions.IgnoreCase | RegexOptions.Compiled), "Yandex"),
    };

    private static readonly Regex BrowserSuffix = new(
        @"\s+[-\u2014]\s+(Google Chrome|Microsoft.?\s*Edge|Mozilla Firefox|Brave|Opera|Vivaldi)\s*$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex EdgeExtras = new(
        @"\s+and\s+\d+\s+more\s+pages?.*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex LeadingCount = new(@"^\(\d+\)\s*", RegexOptions.Compiled);

    /// <summary>
    /// The search a browser window title describes, or null. YouTube is left out
    /// deliberately: a video page title ends the same way as a search page, so
    /// only its URL can tell them apart.
    /// </summary>
    public static WebSearch? FromTitle(string windowTitle)
    {
        if (string.IsNullOrWhiteSpace(windowTitle)) return null;
        var value = BrowserSuffix.Replace(windowTitle.Trim(), "");
        value = EdgeExtras.Replace(value, "").Trim();
        value = LeadingCount.Replace(value, "").Trim();
        if (value.Length == 0) return null;

        foreach (var (pattern, engine) in TitlePatterns)
        {
            var match = pattern.Match(value);
            if (!match.Success) continue;
            var query = match.Groups["q"].Value.Trim();
            if (query.Length is >= 2 and <= 300) return new WebSearch(query, engine);
        }
        return null;
    }
}

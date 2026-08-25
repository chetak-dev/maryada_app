using GuardNest.Core.Web;

namespace GuardNest.Core.Tests;

public class DomainTests
{
    [Theory]
    [InlineData("WWW.Example.COM", "example.com")]
    [InlineData("m.example.com", "example.com")]
    [InlineData("example.com.", "example.com")]
    [InlineData("news.example.com", "news.example.com")]
    public void Normalise_strips_prefixes(string input, string expected) =>
        Assert.Equal(expected, Domains.Normalize(input));

    [Theory]
    [InlineData("https://example.com/path?q=1", "example.com")]
    [InlineData("example.com/?x=1", "example.com")]
    [InlineData("http://www.example.com", "example.com")]
    [InlineData("not a url", "")]
    public void Host_is_read_with_or_without_a_scheme(string address, string expected) =>
        Assert.Equal(expected, Domains.HostOf(address));

    [Fact]
    public void A_domain_covers_its_subdomains()
    {
        var list = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "example.com" };
        Assert.True(Domains.MatchesAny("ads.example.com", list));
        Assert.True(Domains.MatchesAny("example.com", list));
        Assert.False(Domains.MatchesAny("notexample.com", list));
        Assert.False(Domains.MatchesAny("example.com.evil.net", list));
    }
}

public class WebFilterTests
{
    private static WebFilter Build(
        IEnumerable<string>? sites = null, IEnumerable<string>? keywords = null)
    {
        var filter = new WebFilter(new CategoryFeed(new HttpClient()));
        filter.Apply(WebPolicy.Default with
        {
            BlockedSites = new HashSet<string>(
                sites ?? Array.Empty<string>(), StringComparer.OrdinalIgnoreCase),
        });
        filter.ApplyKeywords(new HashSet<string>(
            keywords ?? Array.Empty<string>(), StringComparer.OrdinalIgnoreCase));
        return filter;
    }

    [Fact]
    public void A_listed_site_and_its_subdomains_are_blocked()
    {
        var filter = Build(sites: new[] { "example.com" });
        Assert.Equal(BlockReason.Blocklist, filter.ReasonFor("https://example.com/page"));
        Assert.Equal(BlockReason.Blocklist, filter.ReasonFor("https://news.example.com"));
        Assert.Null(filter.ReasonFor("https://other.com"));
    }

    [Fact]
    public void Youtube_is_allowed_by_default_so_watch_history_can_be_captured()
    {
        var filter = Build();
        Assert.Null(filter.ReasonFor("https://www.youtube.com/watch?v=abc"));
    }

    [Fact]
    public void Youtube_cannot_be_blocked_on_pc()
    {
        var filter = Build(sites: new[] { "youtube.com", "youtu.be" });
        filter.Apply(filter.Policy with { BlockYoutubeWeb = true });
        Assert.Null(filter.ReasonFor("https://www.youtube.com/watch?v=abc"));
        Assert.Null(filter.ReasonFor("https://youtu.be/abc"));
    }

    [Fact]
    public void Seeded_categories_block_before_any_feed_downloads()
    {
        var filter = Build();
        Assert.Equal("adult", filter.ReasonFor("https://pornhub.com"));
        Assert.Equal("gambling", filter.ReasonFor("https://bet365.com/live"));
    }

    [Fact]
    public void Keywords_match_whole_words_only()
    {
        var filter = Build(keywords: new[] { "sex" });
        Assert.Equal(BlockReason.Keyword, filter.ReasonFor("https://site.com/sex-guide"));
        // The reason whole-word matching exists: a council website must not be
        // blocked because its name contains the word.
        Assert.Null(filter.ReasonFor("https://essex.gov.uk/schools"));
    }

    [Fact]
    public void Keywords_are_ignored_on_a_results_page()
    {
        var filter = Build(keywords: new[] { "sex" });
        Assert.Null(filter.ReasonFor("https://www.google.com/search?q=sex+education"));
        Assert.Equal(BlockReason.Keyword, filter.ReasonFor("https://blog.com/sex"));
    }

    [Fact]
    public void A_keyword_in_the_page_title_blocks_an_innocent_looking_address()
    {
        var filter = Build(keywords: new[] { "gambling" });
        // The address gives nothing away; the title is the only thing on
        // Windows that says what the page actually is.
        Assert.Equal(
            BlockReason.Keyword,
            filter.ReasonFor("https://site.com/a/1234", "Online gambling tips - Site"));
        Assert.Null(filter.ReasonFor("https://site.com/a/1234", "Cricket scores - Site"));
    }

    [Fact]
    public void A_title_keyword_is_still_ignored_on_a_results_page()
    {
        var filter = Build(keywords: new[] { "gambling" });
        Assert.Null(filter.ReasonFor(
            "https://www.google.com/search?q=a", "gambling - Google Search"));
    }

    [Fact]
    public void A_keyword_in_the_page_text_blocks_the_page()
    {
        var filter = Build(keywords: new[] { "gambling" });
        Assert.Equal(
            BlockReason.Keyword,
            filter.ReasonFor("https://site.com/a/1234", "Welcome", "Sign up today for gambling offers"));
    }

    [Fact]
    public void Page_text_is_not_read_from_a_results_page()
    {
        var filter = Build(keywords: new[] { "gambling" });
        // The child searched for something else; the results list is full of
        // other people's words and blocking it would block the search itself.
        Assert.Null(filter.ReasonFor(
            "https://duckduckgo.com/?q=cricket", "cricket", "gambling sites and betting odds"));
    }

    [Theory]
    [InlineData("https://www.google.co.uk/search?q=a", true)]
    [InlineData("bing.com", true)]
    [InlineData("duckduckgo.com", true)]
    [InlineData("example.com", false)]
    public void Search_engines_are_recognised(string host, bool expected) =>
        Assert.Equal(expected, WebFilter.IsSearchEngine(Domains.HostOf(host)));
}

public class SearchParserTests
{
    [Theory]
    [InlineData("https://www.google.com/search?q=puppy+pictures", "Google", "puppy pictures")]
    [InlineData("https://www.bing.com/search?q=weather", "Bing", "weather")]
    [InlineData("https://duckduckgo.com/?q=maths+help", "DuckDuckGo", "maths help")]
    [InlineData("https://www.youtube.com/results?search_query=songs", "YouTube", "songs")]
    public void Known_engines_are_parsed(string address, string engine, string query)
    {
        var search = SearchParser.Parse(address);
        Assert.NotNull(search);
        Assert.Equal(engine, search!.Engine);
        Assert.Equal(query, search.Query);
    }

    [Theory]
    [InlineData("https://www.google.com")]
    [InlineData("https://example.com/search?q=test")]
    [InlineData("not a url")]
    public void Anything_else_is_not_a_search(string address) =>
        Assert.Null(SearchParser.Parse(address));

    [Theory]
    [InlineData("school project - Google Search - Google Chrome", "Google", "school project")]
    [InlineData("weather tomorrow - Bing - Microsoft Edge", "Bing", "weather tomorrow")]
    [InlineData("maths help at DuckDuckGo — Mozilla Firefox", "DuckDuckGo", "maths help")]
    [InlineData("healthy recipes - Brave Search - Brave", "Brave", "healthy recipes")]
    public void Search_is_parsed_from_browser_title_when_url_is_hidden(
        string title,
        string engine,
        string query)
    {
        var search = SearchParser.FromTitle(title);
        Assert.NotNull(search);
        Assert.Equal(engine, search!.Engine);
        Assert.Equal(query, search.Query);
    }

    [Theory]
    [InlineData("Example Domain - Google Chrome")]
    [InlineData("Never Gonna Give You Up - YouTube - Google Chrome")]
    public void Ordinary_and_youtube_titles_are_not_web_searches(string title) =>
        Assert.Null(SearchParser.FromTitle(title));
}

public class WebActivityTests
{
    [Fact]
    public void Title_only_search_records_query_and_engine_website()
    {
        var activity = new WebActivity();
        activity.ClearAll();
        var now = new DateTimeOffset(2026, 8, 25, 12, 0, 0, TimeSpan.Zero);

        activity.RecordVisit("", "school project - Google Search - Google Chrome", now);

        var snapshot = activity.Snapshot(now);
        var searches = (List<object?>)snapshot["searches"]!;
        var search = (Dictionary<string, object?>)Assert.Single(searches)!;
        Assert.Equal("school project", search["query"]);
        Assert.Equal("Google", search["engine"]);

        var visited = (List<object?>)snapshot["visited"]!;
        var visit = (Dictionary<string, object?>)Assert.Single(visited)!;
        Assert.Equal("google.com", visit["domain"]);
    }
}

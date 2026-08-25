namespace GuardNest.Core.Web;

/// <summary>
/// Per-category domain lists. A category cannot be told from encrypted traffic,
/// so the only way to block "gambling" is to know the domains — seeds work
/// offline from the first minute, community feeds fill in the long tail.
/// </summary>
public sealed class CategoryFeed
{
    private const int MaxDomainsPerCategory = 40_000;
    private const string ListBase = "https://raw.githubusercontent.com/blocklistproject/Lists/master";

    private static readonly IReadOnlyDictionary<string, string[]> FeedUrls =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["adult"] = new[] { $"{ListBase}/porn.txt" },
            ["gambling"] = new[] { $"{ListBase}/gambling.txt" },
            ["drugs"] = new[] { $"{ListBase}/drugs.txt" },
            ["social"] = new[] { $"{ListBase}/facebook.txt", $"{ListBase}/tiktok.txt", $"{ListBase}/twitter.txt" },
            ["malware"] = new[] { $"{ListBase}/malware.txt" },
            ["phishing"] = new[] { $"{ListBase}/phishing.txt" },
        };

    /// Curated starters so a brand-new install blocks the obvious cases before
    /// any feed has downloaded.
    private static readonly IReadOnlyDictionary<string, string[]> Seeds =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["adult"] = new[] { "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com", "youporn.com" },
            ["gambling"] = new[] { "bet365.com", "pokerstars.com", "williamhill.com", "888casino.com" },
            ["social"] = new[] { "facebook.com", "instagram.com", "twitter.com", "x.com", "tiktok.com", "snapchat.com" },
            ["drugs"] = new[] { "leafly.com", "weedmaps.com" },
            ["weapons"] = new[] { "armslist.com" },
            ["violence"] = new[] { "liveleak.com" },
        };

    private static readonly TimeSpan RefreshInterval = TimeSpan.FromDays(7);

    private readonly HttpClient _http;
    private readonly object _gate = new();
    private Dictionary<string, HashSet<string>> _sets = new(StringComparer.OrdinalIgnoreCase);
    private bool _refreshing;

    public CategoryFeed(HttpClient http)
    {
        _http = http;
        LoadSeeds();
        LoadCache();
    }

    /// <summary>The category blocking <paramref name="host"/>, considering only enabled ones.</summary>
    public string? CategoryOf(string host, IReadOnlyCollection<string> enabled)
    {
        if (host.Length == 0 || enabled.Count == 0) return null;
        var sets = _sets;
        foreach (var category in enabled)
        {
            if (sets.TryGetValue(category, out var domains) && Domains.MatchesAny(host, domains))
            {
                return category;
            }
        }
        return null;
    }

    /// <summary>The category a host falls in whether or not it is enabled — for labelling only.</summary>
    public string? CategoryOfAny(string host)
    {
        if (host.Length == 0) return null;
        var sets = _sets;
        foreach (var (category, domains) in sets)
        {
            if (Domains.MatchesAny(host, domains)) return category;
        }
        return null;
    }

    /// <summary>
    /// Downloads any enabled category that has no fresh cache. Runs in the
    /// background: filtering already works from the seeds, so a slow or blocked
    /// feed must never hold up enforcement.
    /// </summary>
    public async Task EnsureAsync(IReadOnlyCollection<string> enabled, CancellationToken ct)
    {
        lock (_gate)
        {
            if (_refreshing) return;
            _refreshing = true;
        }

        try
        {
            foreach (var category in enabled)
            {
                if (!FeedUrls.TryGetValue(category, out var urls)) continue;
                var cache = CachePath(category);
                if (File.Exists(cache) &&
                    DateTime.UtcNow - File.GetLastWriteTimeUtc(cache) < RefreshInterval)
                {
                    continue;
                }

                var domains = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var url in urls)
                {
                    var text = await DownloadAsync(url, ct);
                    if (text is null) continue;
                    ParseInto(text, domains);
                    if (domains.Count >= MaxDomainsPerCategory) break;
                }
                if (domains.Count == 0) continue;

                Merge(category, domains);
                TrySaveCache(cache, domains);
            }
        }
        finally
        {
            lock (_gate) _refreshing = false;
        }
    }

    private async Task<string?> DownloadAsync(string url, CancellationToken ct)
    {
        try
        {
            using var response = await _http.GetAsync(url, ct);
            return response.IsSuccessStatusCode ? await response.Content.ReadAsStringAsync(ct) : null;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            Diag.Warn("categoryFeed.download", e);
            return null;
        }
    }

    private void LoadSeeds()
    {
        var sets = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var (category, domains) in Seeds)
        {
            sets[category] = new HashSet<string>(domains, StringComparer.OrdinalIgnoreCase);
        }
        _sets = sets;
    }

    private void LoadCache()
    {
        foreach (var category in FeedUrls.Keys)
        {
            var path = CachePath(category);
            try
            {
                if (!File.Exists(path)) continue;
                var domains = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                ParseInto(File.ReadAllText(path), domains);
                if (domains.Count > 0) Merge(category, domains);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                Diag.Warn("categoryFeed.cache", e);
            }
        }
    }

    private void Merge(string category, HashSet<string> domains)
    {
        lock (_gate)
        {
            var sets = new Dictionary<string, HashSet<string>>(_sets, StringComparer.OrdinalIgnoreCase);
            if (sets.TryGetValue(category, out var existing))
            {
                domains.UnionWith(existing);
            }
            sets[category] = domains;
            _sets = sets;
        }
    }

    private static void TrySaveCache(string path, IEnumerable<string> domains)
    {
        try { File.WriteAllLines(path, domains); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Diag.Warn("categoryFeed.save", e);
        }
    }

    private static string CachePath(string category) =>
        DataFolder.Path($"feed-{category.ToLowerInvariant()}.txt");

    /// <summary>Reads hosts-file or plain-domain lists, ignoring comments.</summary>
    private static void ParseInto(string text, HashSet<string> domains)
    {
        foreach (var raw in text.Split('\n'))
        {
            if (domains.Count >= MaxDomainsPerCategory) return;
            var line = raw.Trim();
            if (line.Length == 0 || line[0] == '#') continue;

            // "0.0.0.0 example.com" or just "example.com".
            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            var domain = parts.Length switch
            {
                0 => "",
                1 => parts[0],
                _ => parts[1],
            };
            domain = Domains.Normalize(domain);
            if (domain.Length < 3 || !domain.Contains('.') || domain == "localhost") continue;
            domains.Add(domain);
        }
    }
}

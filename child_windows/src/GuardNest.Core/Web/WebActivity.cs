namespace GuardNest.Core.Web;

/// <summary>
/// The single place browsing is recorded, fed by both halves of the filter: the
/// DNS resolver (which sees every lookup) and the address-bar watcher (which
/// sees the actual page, path and search terms).
/// </summary>
public sealed class WebActivity
{
    /// A refused lookup repeats many times per page, so alerts are throttled per
    /// host rather than fired per query.
    private static readonly TimeSpan AlertThrottle = TimeSpan.FromMinutes(10);

    private readonly WebHistoryStore _history = new();
    private readonly Dictionary<string, DateTimeOffset> _alerted = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();

    /// <summary>Raised the first time a host is refused, with (host, reason).</summary>
    public event Action<string, string>? Blocked;

    public bool HasChanges => _history.HasChanges;

    /// <summary>Records what the browser is showing: the page, and any search on it.</summary>
    public void RecordVisit(string address, DateTimeOffset now) => RecordVisit(address, "", now);

    /// <summary>
    /// Records the page and any search on it. The title matters: Chrome and
    /// Firefox replace the address with the search terms once a results page
    /// loads, so the URL alone reports neither the site nor the search.
    /// </summary>
    public void RecordVisit(string address, string title, DateTimeOffset now)
    {
        var search = SearchParser.Parse(address) ?? SearchParser.FromTitle(title);

        var host = Domains.HostOf(address);
        if (host.Length == 0)
        {
            // A results page whose address bar shows only the query still
            // belongs to the engine the title names.
            if (search is not null)
            {
                _history.RecordSearch(search, now);
                var engineHost = HostForEngine(search.Engine);
                if (engineHost.Length > 0) _history.RecordVisit(engineHost, now);
            }
            return;
        }

        _history.RecordVisit(host, now);
        if (search is not null) _history.RecordSearch(search, now);
    }

    private static string HostForEngine(string engine) => engine.ToLowerInvariant() switch
    {
        "google" => "google.com",
        "bing" => "bing.com",
        "duckduckgo" => "duckduckgo.com",
        "yahoo" => "search.yahoo.com",
        "ecosia" => "ecosia.org",
        "brave" => "search.brave.com",
        "startpage" => "startpage.com",
        "yandex" => "yandex.com",
        "youtube" => "youtube.com",
        _ => "",
    };

    public void RecordBlocked(string hostOrAddress, string reason) =>
        RecordBlocked(hostOrAddress, reason, DateTimeOffset.UtcNow);

    public void RecordBlocked(string hostOrAddress, string reason, DateTimeOffset now)
    {
        var host = hostOrAddress.Contains('/') ? Domains.HostOf(hostOrAddress) : Domains.Normalize(hostOrAddress);
        if (host.Length == 0) return;
        _history.RecordBlocked(host, reason, now);

        bool announce;
        lock (_gate)
        {
            announce = !_alerted.TryGetValue(host, out var last) || now - last > AlertThrottle;
            if (announce) _alerted[host] = now;
        }
        if (announce) Blocked?.Invoke(host, reason);
    }

    public void EndVisit(DateTimeOffset now) => _history.EndVisit(now);

    /// <summary>
    /// Saves without reporting. Browsing is only uploaded every few minutes, and
    /// a service restart in between must not lose it.
    /// </summary>
    public void Flush() => _history.Persist();

    public IReadOnlyDictionary<string, object?> Snapshot(DateTimeOffset now) => _history.Snapshot(now);

    public void ClearAll() => _history.ClearAll();
}

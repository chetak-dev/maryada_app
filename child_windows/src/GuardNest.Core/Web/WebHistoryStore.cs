using System.Text.Json;

namespace GuardNest.Core.Web;

/// <summary>
/// The child's browsing, in the shape the parent app already reads. Visits come
/// from the address bar, so they are real navigations — not the dozens of ad and
/// analytics domains a page pulls in behind the scenes.
/// </summary>
public sealed class WebHistoryStore
{
    private const int MaxDomains = 200;
    private const int MaxSearches = 300;
    private static readonly TimeSpan ActiveGap = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan SearchDedupe = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan Retain = TimeSpan.FromDays(31);

    private readonly object _gate = new();
    private Dictionary<string, Stat> _visited = new(StringComparer.OrdinalIgnoreCase);
    private Dictionary<string, Stat> _blocked = new(StringComparer.OrdinalIgnoreCase);
    private List<SearchEntry> _searches = new();

    private string? _activeDomain;
    private DateTimeOffset _activeSince;
    private string _activeSearchKey = "";
    private string _lastSearchKey = "";
    private DateTimeOffset _lastSearchAt;

    public WebHistoryStore()
    {
        Load();
    }

    public bool HasChanges { get; private set; }

    public void RecordVisit(string host, DateTimeOffset now)
    {
        var domain = Domains.Normalize(host);
        if (domain.Length == 0) return;
        lock (_gate)
        {
            if (domain == _activeDomain)
            {
                AddActiveTime(now);
                return;
            }
            FinishActive(now);

            if (!_visited.TryGetValue(domain, out var stat))
            {
                stat = new Stat();
                _visited[domain] = stat;
            }
            stat.LastAt = now;
            stat.Count++;
            _activeDomain = domain;
            _activeSince = now;
            Trim(_visited, now);
            HasChanges = true;
        }
    }

    public void RecordBlocked(string host, string reason, DateTimeOffset now)
    {
        var domain = Domains.Normalize(host);
        if (domain.Length == 0) return;
        lock (_gate)
        {
            if (!_blocked.TryGetValue(domain, out var stat))
            {
                stat = new Stat();
                _blocked[domain] = stat;
            }
            stat.LastAt = now;
            stat.Count++;
            if (reason.Length > 0) stat.Reason = reason;
            Trim(_blocked, now);
            HasChanges = true;
        }
    }

    public void RecordSearch(WebSearch search, DateTimeOffset now)
    {
        var key = search.Engine.ToLowerInvariant() + "\u0000" + search.Query.ToLowerInvariant();
        lock (_gate)
        {
            // The same results page stays on screen while the child reads it;
            // only a change of search counts as a new one.
            if (key == _activeSearchKey) return;
            _activeSearchKey = key;
            if (key == _lastSearchKey && now - _lastSearchAt < SearchDedupe) return;

            _searches.Add(new SearchEntry(search.Query, search.Engine, now));
            if (_searches.Count > MaxSearches) _searches.RemoveRange(0, _searches.Count - MaxSearches);
            _lastSearchKey = key;
            _lastSearchAt = now;
            HasChanges = true;
        }
    }

    /// <summary>Stops timing when the browser is no longer in front.</summary>
    public void EndVisit(DateTimeOffset now)
    {
        lock (_gate)
        {
            if (_activeDomain is null) return;
            FinishActive(now);
            _activeSearchKey = "";
        }
    }

    /// <summary>The `webHistory/{deviceUid}` payload, rolling in the open page's time.</summary>
    public IReadOnlyDictionary<string, object?> Snapshot(DateTimeOffset now)
    {
        lock (_gate)
        {
            if (_activeDomain is not null) AddActiveTime(now);
            Trim(_visited, now);
            Trim(_blocked, now);

            var visited = _visited
                .OrderByDescending(entry => entry.Value.LastAt)
                .Select(entry => (object?)new Dictionary<string, object?>
                {
                    ["domain"] = entry.Key,
                    ["at"] = entry.Value.LastAt.ToUnixTimeMilliseconds(),
                    ["milliseconds"] = (long)entry.Value.Total.TotalMilliseconds,
                    ["seconds"] = (long)entry.Value.Total.TotalSeconds,
                    ["visits"] = entry.Value.Count,
                })
                .ToList();

            var blocked = _blocked
                .OrderByDescending(entry => entry.Value.LastAt)
                .Select(entry => (object?)new Dictionary<string, object?>
                {
                    ["domain"] = entry.Key,
                    ["at"] = entry.Value.LastAt.ToUnixTimeMilliseconds(),
                    ["attempts"] = entry.Value.Count,
                    ["reason"] = entry.Value.Reason,
                })
                .ToList();

            var searches = _searches
                .AsEnumerable()
                .Reverse()
                .Select(entry => (object?)new Dictionary<string, object?>
                {
                    ["query"] = entry.Query,
                    ["engine"] = entry.Engine,
                    ["at"] = entry.At.ToUnixTimeMilliseconds(),
                })
                .ToList();

            HasChanges = false;
            Save();
            return new Dictionary<string, object?>
            {
                ["visited"] = visited,
                ["blocked"] = blocked,
                ["searches"] = searches,
                ["platform"] = AppConfig.Platform,
            };
        }
    }

    /// <summary>Writes the current state to disk without building a report.</summary>
    public void Persist()
    {
        lock (_gate) Save();
    }

    /// <summary>Empties everything after a server-side wipe, so a flush cannot resurrect it.</summary>
    public void ClearAll()
    {
        lock (_gate)
        {
            _visited.Clear();
            _blocked.Clear();
            _searches.Clear();
            _activeDomain = null;
            _activeSearchKey = "";
            _lastSearchKey = "";
            HasChanges = false;
            Save();
        }
    }

    private void AddActiveTime(DateTimeOffset now)
    {
        if (_activeDomain is null) return;
        var delta = now - _activeSince;
        _activeSince = now;
        // A longer gap means the PC slept or the browser was left alone; that is
        // not time spent on the page.
        if (delta <= TimeSpan.Zero || delta > ActiveGap) return;
        if (!_visited.TryGetValue(_activeDomain, out var stat)) return;
        stat.Total += delta;
        stat.LastAt = now;
        HasChanges = true;
    }

    private void FinishActive(DateTimeOffset now)
    {
        AddActiveTime(now);
        _activeDomain = null;
        Trim(_visited, now);
    }

    private static void Trim(Dictionary<string, Stat> map, DateTimeOffset now)
    {
        var cutoff = now - Retain;
        foreach (var key in map.Where(e => e.Value.LastAt < cutoff).Select(e => e.Key).ToList())
        {
            map.Remove(key);
        }
        if (map.Count <= MaxDomains) return;
        foreach (var key in map.OrderBy(e => e.Value.LastAt).Take(map.Count - MaxDomains)
                     .Select(e => e.Key).ToList())
        {
            map.Remove(key);
        }
    }

    private static string Path => DataFolder.Path("web-history.json");

    private void Save()
    {
        try
        {
            var state = new Persisted(
                _visited.ToDictionary(e => e.Key, e => e.Value),
                _blocked.ToDictionary(e => e.Key, e => e.Value),
                _searches);
            File.WriteAllText(Path, JsonSerializer.Serialize(state));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Diag.Warn("webHistory.save", e);
        }
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(Path)) return;
            var state = JsonSerializer.Deserialize<Persisted>(File.ReadAllText(Path));
            if (state is null) return;
            var cutoff = DateTimeOffset.UtcNow - Retain;
            _visited = state.Visited
                .Where(e => e.Value.LastAt >= cutoff)
                .ToDictionary(e => e.Key, e => e.Value, StringComparer.OrdinalIgnoreCase);
            _blocked = state.Blocked
                .Where(e => e.Value.LastAt >= cutoff)
                .ToDictionary(e => e.Key, e => e.Value, StringComparer.OrdinalIgnoreCase);
            _searches = state.Searches.Where(s => s.At >= cutoff).ToList();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            Diag.Warn("webHistory.load", e);
        }
    }

    public sealed class Stat
    {
        public DateTimeOffset LastAt { get; set; }
        public TimeSpan Total { get; set; }
        public int Count { get; set; }
        public string Reason { get; set; } = "";
    }

    private sealed record SearchEntry(string Query, string Engine, DateTimeOffset At);

    private sealed record Persisted(
        Dictionary<string, Stat> Visited,
        Dictionary<string, Stat> Blocked,
        List<SearchEntry> Searches);
}

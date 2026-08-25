using System.Text.Json;
using System.Text.RegularExpressions;

namespace GuardNest.Core.Media;

/// <summary>
/// YouTube watched in a browser. There is no YouTube app on Windows, so the
/// window title is the only place the video's name appears — the URL carries
/// nothing but an id.
/// </summary>
public sealed class YoutubeStore
{
    private const int MaxVideos = 200;
    private static readonly TimeSpan Retain = TimeSpan.FromDays(31);

    /// Longer than the sampling gap, so a hiccup does not break a watch into
    /// pieces, but short enough that a tab left open overnight stops counting.
    private static readonly TimeSpan MaxTick = TimeSpan.FromSeconds(15);

    /// A video only counts as watched after this much play time, matching the
    /// phone: opening one and backing straight out is not something the parent
    /// needs to see. Matches YoutubeStore.kt MIN_WATCHED_MS.
    private static readonly TimeSpan MinWatched = TimeSpan.FromSeconds(20);

    private static readonly Regex BrowserSuffix = new(
        @"\s+[-\u2014]\s+(Google Chrome|Microsoft.?\s*Edge|Mozilla Firefox|Brave|Opera|Vivaldi)\s*$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Edge appends the tab count and the profile name to every title.
    private static readonly Regex EdgeExtras = new(
        @"\s+and\s+\d+\s+more\s+pages?.*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex YoutubeSuffix = new(
        @"\s+[-\u2014]\s+YouTube\s*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// Unread-message counts change every few seconds and would otherwise make
    /// every sample look like a different video.
    private static readonly Regex LeadingCount = new(@"^\(\d+\)\s*", RegexOptions.Compiled);

    private readonly object _gate = new();
    private Dictionary<string, Entry> _videos = new(StringComparer.OrdinalIgnoreCase);

    public YoutubeStore()
    {
        Load();
    }

    public bool HasChanges { get; private set; }

    /// <summary>
    /// The video name inside a browser window title, or null when the title is
    /// not a YouTube video page.
    /// </summary>
    public static string? TitleFrom(string windowTitle)
    {
        if (string.IsNullOrWhiteSpace(windowTitle)) return null;
        var value = BrowserSuffix.Replace(windowTitle.Trim(), "");
        value = EdgeExtras.Replace(value, "").Trim();
        value = LeadingCount.Replace(value, "");
        if (!YoutubeSuffix.IsMatch(value)) return null;

        value = YoutubeSuffix.Replace(value, "").Trim();
        // "YouTube" alone is the home page, and a search results page is not a
        // video either.
        return value.Length == 0 ? null : value;
    }

    public void Record(string title, TimeSpan watched, DateTimeOffset now)
    {
        var name = title.Trim();
        if (name.Length == 0) return;
        var addition = watched > MaxTick ? MaxTick : watched;

        lock (_gate)
        {
            if (!_videos.TryGetValue(name, out var entry))
            {
                entry = new Entry { Title = name };
                _videos[name] = entry;
            }
            entry.LastAt = now;
            if (addition > TimeSpan.Zero) entry.Watched += addition;
            Trim(now);
            HasChanges = true;
        }
    }

    /// <summary>The `youtubeHistory/{deviceUid}` payload.</summary>
    public IReadOnlyDictionary<string, object?> Snapshot(DateTimeOffset now)
    {
        lock (_gate)
        {
            Trim(now);
            var videos = _videos.Values
                .Where(entry => entry.Watched >= MinWatched)
                .OrderByDescending(entry => entry.LastAt)
                .Select(entry => (object?)new Dictionary<string, object?>
                {
                    ["title"] = entry.Title,
                    ["channel"] = entry.Channel,
                    ["at"] = entry.LastAt.ToUnixTimeMilliseconds(),
                    ["watchedMs"] = (long)entry.Watched.TotalMilliseconds,
                })
                .ToList();

            HasChanges = false;
            Save();
            return new Dictionary<string, object?>
            {
                ["videos"] = videos,
                ["platform"] = AppConfig.Platform,
            };
        }
    }

    public void Persist()
    {
        lock (_gate) Save();
    }

    public void ClearAll()
    {
        lock (_gate)
        {
            _videos.Clear();
            HasChanges = false;
            Save();
        }
    }

    private void Trim(DateTimeOffset now)
    {
        var cutoff = now - Retain;
        foreach (var key in _videos.Where(e => e.Value.LastAt < cutoff).Select(e => e.Key).ToList())
        {
            _videos.Remove(key);
        }
        if (_videos.Count <= MaxVideos) return;
        foreach (var key in _videos.OrderBy(e => e.Value.LastAt)
                     .Take(_videos.Count - MaxVideos).Select(e => e.Key).ToList())
        {
            _videos.Remove(key);
        }
    }

    private static string Path => DataFolder.Path("youtube.json");

    private void Save()
    {
        try { File.WriteAllText(Path, JsonSerializer.Serialize(_videos.Values.ToList())); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Diag.Warn("youtube.save", e);
        }
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(Path)) return;
            var entries = JsonSerializer.Deserialize<List<Entry>>(File.ReadAllText(Path));
            if (entries is null) return;
            var cutoff = DateTimeOffset.UtcNow - Retain;
            _videos = entries
                .Where(entry => entry.LastAt >= cutoff)
                .ToDictionary(entry => entry.Title, entry => entry, StringComparer.OrdinalIgnoreCase);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            Diag.Warn("youtube.load", e);
        }
    }

    public sealed class Entry
    {
        public string Title { get; set; } = "";
        public string Channel { get; set; } = "";
        public TimeSpan Watched { get; set; }
        public DateTimeOffset LastAt { get; set; }
    }
}

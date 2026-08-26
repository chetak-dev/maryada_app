using System.Text.Json;

namespace GuardNest.Core.Reporting;

/// <summary>
/// Per-day, per-app foreground time. Only time the child was actually at the
/// machine counts: an idle window left on top would otherwise report a whole
/// day of "use", which is the same over-reporting the Android app had to move
/// away from totalTimeInForeground to avoid.
/// </summary>
public sealed class UsageTracker
{
    private const int RetainedDays = 14;

    private readonly object _gate = new();
    private Store _store = Store.Load();

    public void Record(string executable, string displayName, TimeSpan foreground)
    {
        if (foreground <= TimeSpan.Zero || executable.Length == 0) return;
        lock (_gate)
        {
            var day = Today();
            if (!_store.Days.TryGetValue(day, out var apps))
            {
                apps = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
                _store.Days[day] = apps;
            }
            apps[executable] = apps.GetValueOrDefault(executable) + foreground.TotalSeconds;
            if (displayName.Length > 0) _store.Names[executable] = displayName;
        }
    }

    public int MinutesToday()
    {
        lock (_gate)
        {
            return _store.Days.TryGetValue(Today(), out var apps)
                ? (int)(apps.Values.Sum() / 60)
                : 0;
        }
    }

    public void Flush()
    {
        lock (_gate)
        {
            Prune();
            _store.Save();
        }
    }

    private void Prune()
    {
        var cutoff = DateTime.Today.AddDays(-RetainedDays).ToString("yyyy-MM-dd");
        foreach (var key in _store.Days.Keys.Where(k => string.CompareOrdinal(k, cutoff) < 0).ToList())
        {
            _store.Days.Remove(key);
        }
    }

    private static string Today() => DateTime.Today.ToString("yyyy-MM-dd");

    private sealed class Store
    {
        public Dictionary<string, Dictionary<string, double>> Days { get; set; } = new();
        public Dictionary<string, string> Names { get; set; } = new();

        private static string Path => DataFolder.Path("usage.json");

        public static Store Load()
        {
            try
            {
                return File.Exists(Path)
                    ? JsonSerializer.Deserialize<Store>(File.ReadAllText(Path)) ?? new Store()
                    : new Store();
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
            {
                return new Store();
            }
        }

        public void Save()
        {
            try { File.WriteAllText(Path, JsonSerializer.Serialize(this)); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                Diag.Warn("usage.save", e);
            }
        }
    }
}

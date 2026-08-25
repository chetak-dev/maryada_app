using System.Text.Json;

namespace GuardNest.Core;

/// <summary>
/// The last internal failure, surfaced to the parent on the heartbeat. A device
/// that has quietly stopped working otherwise looks identical to a healthy one.
/// </summary>
public static class Diag
{
    private static readonly object Gate = new();
    private static readonly Dictionary<string, DateTimeOffset> LastLogged = new();

    private static string Path => DataFolder.Path("diag.json");

    public static void Warn(string where, Exception error)
    {
        var message = $"{where}: {error.GetType().Name}: {error.Message}";
        lock (Gate)
        {
            // One report per site per minute; a failing loop must not turn into
            // a write storm against Firestore or the disk.
            if (LastLogged.TryGetValue(where, out var last) &&
                DateTimeOffset.UtcNow - last < TimeSpan.FromMinutes(1))
            {
                return;
            }
            LastLogged[where] = DateTimeOffset.UtcNow;
            Save(new Record(message, DateTimeOffset.UtcNow));
        }
        Console.Error.WriteLine($"[warn] {message}");
    }

    public static (string Message, DateTimeOffset At)? Last()
    {
        var record = Load();
        return record is null ? null : (record.Message, record.At);
    }

    /// <summary>
    /// Drops an error that a later successful write has disproved. Without this
    /// one transient failure stays on the parent's screen forever.
    /// </summary>
    public static void ClearResolved(DateTimeOffset asOf)
    {
        lock (Gate)
        {
            var record = Load();
            if (record is null || record.At > asOf) return;
            try { File.Delete(Path); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
    }

    private static void Save(Record record)
    {
        // Diagnostics must never be the thing that breaks the caller.
        try { File.WriteAllText(Path, JsonSerializer.Serialize(record)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    private static Record? Load()
    {
        try
        {
            return File.Exists(Path)
                ? JsonSerializer.Deserialize<Record>(File.ReadAllText(Path))
                : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }

    private sealed record Record(string Message, DateTimeOffset At);
}

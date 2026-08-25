using System.Globalization;

namespace GuardNest.Core.Firebase;

/// <summary>One Firestore document, flattened to plain CLR values.</summary>
public sealed class FirestoreDocument
{
    public FirestoreDocument(string id, IReadOnlyDictionary<string, object?> fields)
    {
        Id = id;
        Fields = fields;
    }

    public string Id { get; }
    public IReadOnlyDictionary<string, object?> Fields { get; }

    public string? GetString(string key) => Fields.GetValueOrDefault(key) as string;

    public bool GetBool(string key, bool fallback = false) =>
        Fields.GetValueOrDefault(key) is bool value ? value : fallback;

    public int GetInt(string key, int fallback = 0) => Fields.GetValueOrDefault(key) switch
    {
        long value => (int)value,
        double value => (int)value,
        string text when int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) => parsed,
        _ => fallback,
    };

    public DateTimeOffset? GetTimestamp(string key) =>
        Fields.GetValueOrDefault(key) as DateTimeOffset?;

    public IReadOnlyList<object?> GetList(string key) =>
        Fields.GetValueOrDefault(key) as IReadOnlyList<object?> ?? Array.Empty<object?>();
}

/// <summary>A single document write in a commit.</summary>
public sealed record FirestoreWrite(
    string Path,
    IReadOnlyDictionary<string, object?> Fields,
    IReadOnlyCollection<string>? ServerTimestamps = null);

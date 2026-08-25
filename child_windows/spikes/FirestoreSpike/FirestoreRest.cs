using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace GuardNest.Windows.Spikes.Firestore;

/// <summary>
/// Minimal Firestore access over the REST API, authenticated with the device's
/// anonymous ID token. This is the transport the Windows agent will use for
/// reads and writes; realtime updates need gRPC (see <see cref="FirestoreListen"/>).
/// </summary>
internal sealed class FirestoreRest
{
    private readonly HttpClient _http;
    private readonly AnonymousAuth _auth;
    private readonly string _documents;
    private readonly string _commitUrl;

    public FirestoreRest(HttpClient http, AnonymousAuth auth, string projectId)
    {
        _http = http;
        _auth = auth;
        _documents = $"projects/{projectId}/databases/(default)/documents";
        _commitUrl = $"https://firestore.googleapis.com/v1/{_documents}:commit";
    }

    /// The document's Firestore resource name, which is what a commit payload
    /// must carry — a full https URL there is rejected as INVALID_ARGUMENT.
    public string DocumentName(string path) => $"{_documents}/{path.Trim('/')}";

    public string DocumentUrl(string path) =>
        "https://firestore.googleapis.com/v1/" + DocumentName(path);

    public async Task<(HttpStatusCode Status, string Body)> GetAsync(
        string path, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, DocumentUrl(path));
        return await SendAsync(req, ct);
    }

    /// <summary>
    /// Merge-writes the given fields (the REST equivalent of SetOptions.merge:
    /// an updateMask means untouched fields survive).
    /// </summary>
    public async Task<(HttpStatusCode Status, string Body)> MergeAsync(
        string path, IReadOnlyDictionary<string, object?> fields, CancellationToken ct)
    {
        var query = string.Join("&", fields.Keys.Select(
            k => "updateMask.fieldPaths=" + Uri.EscapeDataString(k)));
        var url = $"{DocumentUrl(path)}?{query}";
        var body = new JsonObject { ["fields"] = EncodeFields(fields) };
        using var req = new HttpRequestMessage(HttpMethod.Patch, url)
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        return await SendAsync(req, ct);
    }

    /// <summary>
    /// Merge-write plus server-side timestamps. PATCH cannot express
    /// FieldValue.serverTimestamp(); only a commit with `updateTransforms` can,
    /// which is what the heartbeat's `lastSeenAt` needs.
    /// </summary>
    public async Task<(HttpStatusCode Status, string Body)> CommitAsync(
        string path,
        IReadOnlyDictionary<string, object?> fields,
        IEnumerable<string> serverTimestampFields,
        CancellationToken ct)
    {
        var transforms = new JsonArray();
        foreach (var field in serverTimestampFields)
        {
            transforms.Add(new JsonObject
            {
                ["fieldPath"] = field,
                ["setToServerValue"] = "REQUEST_TIME",
            });
        }

        var mask = new JsonArray();
        foreach (var key in fields.Keys) mask.Add(key);

        var write = new JsonObject
        {
            ["update"] = new JsonObject
            {
                ["name"] = DocumentName(path),
                ["fields"] = EncodeFields(fields),
            },
            ["updateMask"] = new JsonObject { ["fieldPaths"] = mask },
        };
        if (transforms.Count > 0) write["updateTransforms"] = transforms;

        var body = new JsonObject { ["writes"] = new JsonArray { write } };
        using var req = new HttpRequestMessage(HttpMethod.Post, _commitUrl)
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        return await SendAsync(req, ct);
    }

    private async Task<(HttpStatusCode, string)> SendAsync(
        HttpRequestMessage req, CancellationToken ct)
    {
        req.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue(
            "Bearer", await _auth.GetIdTokenAsync(ct));
        using var res = await _http.SendAsync(req, ct);
        return (res.StatusCode, await res.Content.ReadAsStringAsync(ct));
    }

    private static JsonObject EncodeFields(IReadOnlyDictionary<string, object?> fields)
    {
        var obj = new JsonObject();
        foreach (var (key, value) in fields) obj[key] = Encode(value);
        return obj;
    }

    private static JsonNode Encode(object? value) => value switch
    {
        null => new JsonObject { ["nullValue"] = null },
        bool b => new JsonObject { ["booleanValue"] = b },
        string s => new JsonObject { ["stringValue"] = s },
        int or long => new JsonObject
        {
            ["integerValue"] = Convert.ToInt64(value).ToString(),
        },
        double or float => new JsonObject
        {
            ["doubleValue"] = Convert.ToDouble(value),
        },
        DateTimeOffset t => new JsonObject
        {
            ["timestampValue"] = t.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"),
        },
        IReadOnlyDictionary<string, object?> map => new JsonObject
        {
            ["mapValue"] = new JsonObject { ["fields"] = EncodeFields(map) },
        },
        System.Collections.IEnumerable list => EncodeList(list),
        _ => new JsonObject { ["stringValue"] = value.ToString() ?? "" },
    };

    private static JsonNode EncodeList(System.Collections.IEnumerable list)
    {
        var values = new JsonArray();
        foreach (var item in list) values.Add(Encode(item));
        return new JsonObject
        {
            ["arrayValue"] = new JsonObject { ["values"] = values },
        };
    }

    /// <summary>Flattens a REST document's typed values into plain CLR objects.</summary>
    public static Dictionary<string, object?> DecodeFields(JsonElement document)
    {
        var result = new Dictionary<string, object?>();
        if (!document.TryGetProperty("fields", out var fields)) return result;
        foreach (var field in fields.EnumerateObject())
        {
            result[field.Name] = DecodeValue(field.Value);
        }
        return result;
    }

    private static object? DecodeValue(JsonElement value)
    {
        foreach (var prop in value.EnumerateObject())
        {
            switch (prop.Name)
            {
                case "nullValue": return null;
                case "booleanValue": return prop.Value.GetBoolean();
                case "stringValue": return prop.Value.GetString();
                case "integerValue": return long.Parse(prop.Value.GetString() ?? "0");
                case "doubleValue": return prop.Value.GetDouble();
                case "timestampValue": return prop.Value.GetDateTimeOffset();
                case "mapValue": return DecodeFields(prop.Value);
                case "arrayValue":
                    var items = new List<object?>();
                    if (prop.Value.TryGetProperty("values", out var values))
                    {
                        foreach (var item in values.EnumerateArray())
                        {
                            items.Add(DecodeValue(item));
                        }
                    }
                    return items;
            }
        }
        return null;
    }
}

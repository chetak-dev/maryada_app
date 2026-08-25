using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace GuardNest.Core.Firebase;

/// <summary>
/// Firestore over the REST API, authenticated with the device's anonymous ID
/// token. Rules are polled rather than streamed: realtime needs gRPC, which any
/// HTTP proxy on the network breaks, and a rule change taking a few seconds is
/// not worth that failure mode.
/// </summary>
public sealed class FirestoreClient
{
    private const string Root = "https://firestore.googleapis.com/v1/";

    private readonly HttpClient _http;
    private readonly AnonymousAuth _auth;
    private readonly string _documents;

    public FirestoreClient(HttpClient http, AnonymousAuth auth, string projectId)
    {
        _http = http;
        _auth = auth;
        _documents = $"projects/{projectId}/databases/(default)/documents";
    }

    /// The resource name a commit payload needs; a full URL there is rejected.
    private string ResourceName(string path) => $"{_documents}/{path.Trim('/')}";

    private string Url(string path) => Root + ResourceName(path);

    /// <summary>Reads one document, or null when it does not exist.</summary>
    public async Task<FirestoreDocument?> GetAsync(string path, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, Url(path));
        var (status, body) = await SendAsync(req, ct);
        if (status == HttpStatusCode.NotFound) return null;
        if (status != HttpStatusCode.OK) throw new FirestoreException(status, $"get {path}", body);

        var root = JsonDocument.Parse(body).RootElement;
        return new FirestoreDocument(LastSegment(path), FirestoreValues.DecodeFields(root));
    }

    /// <summary>Reads every document in a collection, following pagination.</summary>
    public async Task<IReadOnlyList<FirestoreDocument>> ListAsync(string collection, CancellationToken ct)
    {
        var results = new List<FirestoreDocument>();
        string? pageToken = null;
        do
        {
            var url = $"{Url(collection)}?pageSize=300";
            if (pageToken is not null) url += "&pageToken=" + Uri.EscapeDataString(pageToken);

            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            var (status, body) = await SendAsync(req, ct);
            if (status == HttpStatusCode.NotFound) return results;
            if (status != HttpStatusCode.OK) throw new FirestoreException(status, $"list {collection}", body);

            var root = JsonDocument.Parse(body).RootElement;
            if (root.TryGetProperty("documents", out var documents))
            {
                foreach (var document in documents.EnumerateArray())
                {
                    var name = document.GetProperty("name").GetString() ?? "";
                    results.Add(new FirestoreDocument(
                        LastSegment(name), FirestoreValues.DecodeFields(document)));
                }
            }
            pageToken = root.TryGetProperty("nextPageToken", out var token) ? token.GetString() : null;
        }
        while (!string.IsNullOrEmpty(pageToken));

        return results;
    }

    public Task MergeAsync(
        string path,
        IReadOnlyDictionary<string, object?> fields,
        CancellationToken ct,
        IReadOnlyCollection<string>? serverTimestamps = null) =>
        CommitAsync(new[] { new FirestoreWrite(path, fields, serverTimestamps) }, ct);

    /// <summary>
    /// Applies writes atomically. Everything goes through commit because a plain
    /// PATCH cannot express serverTimestamp(), which the heartbeat needs so the
    /// parent's "last seen" does not depend on the child's clock.
    /// </summary>
    public async Task CommitAsync(
        IReadOnlyCollection<FirestoreWrite> writes,
        CancellationToken ct,
        IReadOnlyCollection<string>? deletes = null)
    {
        if (writes.Count == 0 && (deletes is null || deletes.Count == 0)) return;

        var payload = new JsonArray();
        foreach (var path in deletes ?? Array.Empty<string>())
        {
            payload.Add(new JsonObject { ["delete"] = ResourceName(path) });
        }

        foreach (var write in writes)
        {
            var mask = new JsonArray();
            foreach (var key in write.Fields.Keys) mask.Add(key);

            var entry = new JsonObject
            {
                ["update"] = new JsonObject
                {
                    ["name"] = ResourceName(write.Path),
                    ["fields"] = FirestoreValues.EncodeFields(write.Fields),
                },
                ["updateMask"] = new JsonObject { ["fieldPaths"] = mask },
            };

            if (write.ServerTimestamps is { Count: > 0 })
            {
                var transforms = new JsonArray();
                foreach (var field in write.ServerTimestamps)
                {
                    transforms.Add(new JsonObject
                    {
                        ["fieldPath"] = field,
                        ["setToServerValue"] = "REQUEST_TIME",
                    });
                }
                entry["updateTransforms"] = transforms;
            }

            payload.Add(entry);
        }

        var body = new JsonObject { ["writes"] = payload }.ToJsonString();
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{Root}{_documents}:commit")
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        var (status, response) = await SendAsync(req, ct);
        if (status != HttpStatusCode.OK)
        {
            var subject = writes.Count > 0 ? writes.First().Path : "deletes";
            throw new FirestoreException(status, $"commit {subject}", response);
        }
    }

    public async Task DeleteAsync(string path, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Delete, Url(path));
        var (status, body) = await SendAsync(req, ct);
        if (status is not (HttpStatusCode.OK or HttpStatusCode.NotFound))
        {
            throw new FirestoreException(status, $"delete {path}", body);
        }
    }

    private async Task<(HttpStatusCode, string)> SendAsync(HttpRequestMessage req, CancellationToken ct)
    {
        req.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", await _auth.GetIdTokenAsync(ct));
        using var res = await _http.SendAsync(req, ct);
        return (res.StatusCode, await res.Content.ReadAsStringAsync(ct));
    }

    private static string LastSegment(string path)
    {
        var trimmed = path.TrimEnd('/');
        var slash = trimmed.LastIndexOf('/');
        return slash < 0 ? trimmed : trimmed[(slash + 1)..];
    }
}

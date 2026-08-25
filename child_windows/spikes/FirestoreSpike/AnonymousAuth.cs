using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GuardNest.Windows.Spikes.Firestore;

/// <summary>
/// Anonymous Firebase sign-in over the Identity Toolkit REST API — the .NET
/// stand-in for FirebaseAuth.signInAnonymously() in the Android child app.
/// There is no Firebase client SDK for .NET, so the agent speaks REST directly.
/// </summary>
internal sealed class AnonymousAuth
{
    private const string SignUpUrl =
        "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=";
    private const string RefreshUrl =
        "https://securetoken.googleapis.com/v1/token?key=";

    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly SemaphoreSlim _gate = new(1, 1);

    private string _idToken = "";
    private string _refreshToken = "";
    private DateTimeOffset _expiresAt = DateTimeOffset.MinValue;

    public AnonymousAuth(HttpClient http, string apiKey)
    {
        _http = http;
        _apiKey = apiKey;
        var saved = TokenStore.Load();
        if (saved is null) return;
        try
        {
            var state = JsonSerializer.Deserialize<Persisted>(saved);
            if (state is null) return;
            Uid = state.Uid;
            _refreshToken = state.RefreshToken;
        }
        catch (JsonException) { }
    }

    public string Uid { get; private set; } = "";

    /// True when this run reused the stored identity instead of minting a new one.
    public bool RestoredFromDisk { get; private set; }

    public DateTimeOffset ExpiresAt => _expiresAt;

    /// <summary>
    /// A valid ID token, refreshed when it is close to expiry. Every Firestore
    /// call goes through here; tokens last an hour, so a long-lived agent must
    /// refresh rather than sign in again (signing in again would mint a NEW uid
    /// and orphan the pairing).
    /// </summary>
    public async Task<string> GetIdTokenAsync(CancellationToken ct)
    {
        await _gate.WaitAsync(ct);
        try
        {
            if (_idToken.Length > 0 &&
                DateTimeOffset.UtcNow < _expiresAt - TimeSpan.FromMinutes(5))
            {
                return _idToken;
            }

            if (_refreshToken.Length > 0)
            {
                try
                {
                    await RefreshAsync(ct);
                    RestoredFromDisk = true;
                    return _idToken;
                }
                catch (HttpRequestException)
                {
                    // A revoked or corrupt refresh token must not strand the
                    // device offline forever; fall through to a fresh sign-in.
                    _refreshToken = "";
                    TokenStore.Clear();
                }
            }

            await SignUpAsync(ct);
            return _idToken;
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task SignUpAsync(CancellationToken ct)
    {
        using var res = await _http.PostAsJsonAsync(
            SignUpUrl + _apiKey, new { returnSecureToken = true }, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (!res.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"signUp {(int)res.StatusCode}: {body}");
        }

        var doc = JsonSerializer.Deserialize<SignUpResponse>(body)
                  ?? throw new HttpRequestException("signUp returned no body");
        Uid = doc.LocalId;
        _idToken = doc.IdToken;
        _refreshToken = doc.RefreshToken;
        _expiresAt = DateTimeOffset.UtcNow.AddSeconds(ParseSeconds(doc.ExpiresIn));
        Persist();
    }

    private async Task RefreshAsync(CancellationToken ct)
    {
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = _refreshToken,
        });
        using var res = await _http.PostAsync(RefreshUrl + _apiKey, form, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (!res.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"refresh {(int)res.StatusCode}: {body}");
        }

        var doc = JsonSerializer.Deserialize<RefreshResponse>(body)
                  ?? throw new HttpRequestException("refresh returned no body");
        Uid = doc.UserId;
        _idToken = doc.IdToken;
        _refreshToken = doc.RefreshToken;
        _expiresAt = DateTimeOffset.UtcNow.AddSeconds(ParseSeconds(doc.ExpiresIn));
        Persist();
    }

    private void Persist() =>
        TokenStore.Save(JsonSerializer.Serialize(new Persisted(Uid, _refreshToken)));

    private static int ParseSeconds(string? value) =>
        int.TryParse(value, out var seconds) ? seconds : 3600;

    private sealed record Persisted(string Uid, string RefreshToken);

    private sealed class SignUpResponse
    {
        [JsonPropertyName("idToken")] public string IdToken { get; set; } = "";
        [JsonPropertyName("refreshToken")] public string RefreshToken { get; set; } = "";
        [JsonPropertyName("expiresIn")] public string ExpiresIn { get; set; } = "";
        [JsonPropertyName("localId")] public string LocalId { get; set; } = "";
    }

    private sealed class RefreshResponse
    {
        [JsonPropertyName("id_token")] public string IdToken { get; set; } = "";
        [JsonPropertyName("refresh_token")] public string RefreshToken { get; set; } = "";
        [JsonPropertyName("expires_in")] public string ExpiresIn { get; set; } = "";
        [JsonPropertyName("user_id")] public string UserId { get; set; } = "";
    }
}

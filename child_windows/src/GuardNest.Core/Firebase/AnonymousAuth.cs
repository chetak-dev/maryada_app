using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GuardNest.Core.Firebase;

/// <summary>
/// Anonymous Firebase sign-in over the Identity Toolkit REST API — the .NET
/// stand-in for FirebaseAuth.signInAnonymously(). There is no Firebase client
/// SDK for .NET, so the agent speaks REST directly.
/// </summary>
public sealed class AnonymousAuth
{
    private const string SignUpUrl = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=";
    private const string RefreshUrl = "https://securetoken.googleapis.com/v1/token?key=";

    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly bool _persistIdentity;
    private readonly SemaphoreSlim _gate = new(1, 1);

    private string _idToken = "";
    private string _refreshToken = "";
    private DateTimeOffset _expiresAt = DateTimeOffset.MinValue;

    public AnonymousAuth(HttpClient http, string apiKey, bool persistIdentity = true)
    {
        _http = http;
        _apiKey = apiKey;
        _persistIdentity = persistIdentity;
        if (!persistIdentity) return;

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

    public DateTimeOffset ExpiresAt => _expiresAt;

    /// <summary>
    /// A valid ID token, refreshed shortly before expiry. Signing in again
    /// instead of refreshing would mint a NEW uid and orphan the pairing, so
    /// sign-up only ever happens when there is no usable refresh token.
    /// </summary>
    public async Task<string> GetIdTokenAsync(CancellationToken ct)
    {
        await _gate.WaitAsync(ct);
        try
        {
            if (_idToken.Length > 0 && DateTimeOffset.UtcNow < _expiresAt - TimeSpan.FromMinutes(5))
            {
                return _idToken;
            }

            if (_refreshToken.Length > 0)
            {
                try
                {
                    await RefreshAsync(ct);
                    return _idToken;
                }
                catch (HttpRequestException)
                {
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

    /// <summary>Forgets this device's identity — used when the parent unpairs it.</summary>
    public void Forget()
    {
        _idToken = "";
        _refreshToken = "";
        _expiresAt = DateTimeOffset.MinValue;
        Uid = "";
        if (_persistIdentity) TokenStore.Clear();
    }

    private async Task SignUpAsync(CancellationToken ct)
    {
        using var res = await _http.PostAsJsonAsync(SignUpUrl + _apiKey, new { returnSecureToken = true }, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (!res.IsSuccessStatusCode) throw new HttpRequestException($"signUp {(int)res.StatusCode}: {body}");

        var doc = JsonSerializer.Deserialize<SignUpResponse>(body)
                  ?? throw new HttpRequestException("signUp returned no body");
        Uid = doc.LocalId;
        _idToken = doc.IdToken;
        _refreshToken = doc.RefreshToken;
        _expiresAt = DateTimeOffset.UtcNow.AddSeconds(ParseSeconds(doc.ExpiresIn));
        if (_persistIdentity) Persist();
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
        if (!res.IsSuccessStatusCode) throw new HttpRequestException($"refresh {(int)res.StatusCode}: {body}");

        var doc = JsonSerializer.Deserialize<RefreshResponse>(body)
                  ?? throw new HttpRequestException("refresh returned no body");
        Uid = doc.UserId;
        _idToken = doc.IdToken;
        _refreshToken = doc.RefreshToken;
        _expiresAt = DateTimeOffset.UtcNow.AddSeconds(ParseSeconds(doc.ExpiresIn));
        if (_persistIdentity) Persist();
    }

    private void Persist() => TokenStore.Save(JsonSerializer.Serialize(new Persisted(Uid, _refreshToken)));

    private static int ParseSeconds(string? value) => int.TryParse(value, out var seconds) ? seconds : 3600;

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

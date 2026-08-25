using System.Diagnostics;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using GuardNest.Core.Firebase;

namespace GuardNest.Core.Update;

/// <summary>What the site admin published for this platform.</summary>
public sealed record UpdateManifest(
    bool Enabled,
    int VersionCode,
    string Url,
    string Sha256,
    string SilentArgs)
{
    /// <summary>
    /// Plain HTTP would let anyone on the network hand the fleet an executable,
    /// and without a digest there is nothing to check the download against.
    /// </summary>
    public bool IsAcceptable =>
        Url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) && Sha256.Length == 64;

    public bool ShouldApply(int installedVersionCode) =>
        Enabled && VersionCode > installedVersionCode && IsAcceptable;
}

/// <summary>
/// Self-update from `appConfig/win`. The fleet is unreachable after the first
/// install, so this is the only way a fix ever lands — which is also why it
/// refuses anything it cannot verify.
/// </summary>
public sealed class AppUpdater
{
    private static readonly TimeSpan CheckInterval = TimeSpan.FromHours(3);

    private readonly HttpClient _http;
    private readonly FirestoreClient _firestore;
    private DateTimeOffset _lastCheck = DateTimeOffset.MinValue;

    public AppUpdater(HttpClient http, FirestoreClient firestore)
    {
        _http = http;
        _firestore = firestore;
    }

    public async Task<bool> CheckAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        if (now - _lastCheck < CheckInterval) return false;
        _lastCheck = now;

        var manifest = await LoadAsync(ct);
        if (manifest is null) return false;
        if (!manifest.ShouldApply(AppConfig.VersionCode))
        {
            if (manifest.Enabled && manifest.VersionCode > AppConfig.VersionCode && !manifest.IsAcceptable)
            {
                Diag.Warn("update.manifest",
                    new InvalidOperationException("Update needs an https url and a sha256"));
            }
            return false;
        }

        var installer = await DownloadAsync(manifest, ct);
        if (installer is null) return false;

        return Install(installer, manifest);
    }

    private async Task<UpdateManifest?> LoadAsync(CancellationToken ct)
    {
        try
        {
            var doc = await _firestore.GetAsync(AppConfig.UpdateDocument, ct);
            if (doc is null) return null;
            return new UpdateManifest(
                Enabled: doc.GetBool("enabled"),
                VersionCode: doc.GetInt("versionCode"),
                Url: doc.GetString("url") ?? "",
                Sha256: (doc.GetString("sha256") ?? "").Replace("-", "").Trim(),
                SilentArgs: doc.GetString("silentArgs") ?? "");
        }
        catch (FirestoreException e)
        {
            Diag.Warn("update.manifest", e);
            return null;
        }
    }

    private async Task<string?> DownloadAsync(UpdateManifest manifest, CancellationToken ct)
    {
        var extension = manifest.Url.EndsWith(".msi", StringComparison.OrdinalIgnoreCase) ? ".msi" : ".exe";
        var path = Path.Combine(Path.GetTempPath(), $"GuardNest-{manifest.VersionCode}{extension}");
        try
        {
            using (var response = await _http.GetAsync(manifest.Url, HttpCompletionOption.ResponseHeadersRead, ct))
            {
                response.EnsureSuccessStatusCode();
                await using var file = File.Create(path);
                await response.Content.CopyToAsync(file, ct);
            }

            if (!DigestMatches(path, manifest.Sha256))
            {
                Diag.Warn("update.digest", new InvalidOperationException("Downloaded file failed its checksum"));
                TryDelete(path);
                return null;
            }

            if (!IsTrusted(path))
            {
                Diag.Warn("update.signature", new InvalidOperationException("Downloaded file is not signed by us"));
                TryDelete(path);
                return null;
            }

            return path;
        }
        catch (Exception e) when (e is HttpRequestException or IOException or TaskCanceledException)
        {
            Diag.Warn("update.download", e);
            TryDelete(path);
            return null;
        }
    }

    private static bool DigestMatches(string path, string expected)
    {
        using var stream = File.OpenRead(path);
        var digest = Convert.ToHexString(SHA256.HashData(stream));
        return digest.Equals(expected, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The checksum only proves the bytes match the manifest; anyone who can
    /// write the manifest could point it at their own file. The signature is
    /// what proves the installer is ours.
    /// </summary>
    private static bool IsTrusted(string path)
    {
        try
        {
            using var certificate = new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
            using var chain = new X509Chain();
            chain.ChainPolicy.RevocationMode = X509RevocationMode.Online;
            chain.ChainPolicy.RevocationFlag = X509RevocationFlag.ExcludeRoot;
            if (!chain.Build(certificate)) return false;

            var expected = AppConfig.PublisherThumbprint;
            // No pinned thumbprint yet (before the signing certificate exists),
            // so a valid chain is the most that can be required.
            return expected.Length == 0
                || certificate.Thumbprint.Equals(expected, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception e) when (e is CryptographicException or PlatformNotSupportedException)
        {
            return false;
        }
    }

    private static bool Install(string installer, UpdateManifest manifest)
    {
        try
        {
            var isMsi = installer.EndsWith(".msi", StringComparison.OrdinalIgnoreCase);
            var startInfo = isMsi
                ? new ProcessStartInfo("msiexec", $"/i \"{installer}\" /qn /norestart")
                : new ProcessStartInfo(installer, manifest.SilentArgs.Length > 0 ? manifest.SilentArgs : "--quiet");
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;

            using var process = Process.Start(startInfo);
            // The installer stops and replaces this service, so waiting for it
            // to finish here would be waiting for our own shutdown.
            return process is not null;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            Diag.Warn("update.install", e);
            return false;
        }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}

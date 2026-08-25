using GuardNest.Core.Update;

namespace GuardNest.Core.Tests;

public class UpdateManifestTests
{
    private static UpdateManifest Manifest(
        bool enabled = true,
        int version = 2,
        string url = "https://example.com/Maryada.msi",
        string sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") =>
        new(enabled, version, url, sha, "");

    [Fact]
    public void A_newer_published_build_is_applied() =>
        Assert.True(Manifest().ShouldApply(installedVersionCode: 1));

    [Fact]
    public void The_installed_version_is_never_reinstalled()
    {
        Assert.False(Manifest(version: 1).ShouldApply(1));
        Assert.False(Manifest(version: 1).ShouldApply(2));
    }

    [Fact]
    public void A_disabled_manifest_is_ignored() =>
        Assert.False(Manifest(enabled: false).ShouldApply(1));

    [Fact]
    public void Plain_http_is_refused() =>
        Assert.False(Manifest(url: "http://example.com/Maryada.msi").ShouldApply(1));

    [Theory]
    [InlineData("")]
    [InlineData("abc123")]
    public void A_missing_or_short_digest_is_refused(string sha) =>
        Assert.False(Manifest(sha: sha).ShouldApply(1));
}

public class RunMarkerTests
{
    [Fact]
    public void A_released_marker_means_the_last_run_was_clean()
    {
        RunMarker.Release();
        Assert.False(RunMarker.Claim());
        RunMarker.Release();
    }

    [Fact]
    public void A_marker_left_behind_means_the_last_run_was_killed()
    {
        RunMarker.Release();
        RunMarker.Claim();
        // No Release: the service was killed rather than stopped.
        Assert.True(RunMarker.Claim());
        RunMarker.Release();
    }
}

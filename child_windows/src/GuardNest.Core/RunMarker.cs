namespace GuardNest.Core;

/// <summary>
/// A marker held while the service is running. Finding one at startup means the
/// last run did not stop cleanly — killed, force-stopped or the machine cut off
/// — which on a parental control is worth telling the parent about.
/// </summary>
public static class RunMarker
{
    private static string Path => DataFolder.Path("running.marker");

    /// <summary>Claims the marker; true when the previous run ended abruptly.</summary>
    public static bool Claim()
    {
        var unclean = File.Exists(Path);
        try { File.WriteAllText(Path, DateTimeOffset.UtcNow.ToString("O")); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Diag.Warn("runMarker.claim", e);
        }
        return unclean;
    }

    public static void Release()
    {
        try { File.Delete(Path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}

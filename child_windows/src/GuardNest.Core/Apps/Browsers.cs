namespace GuardNest.Core.Apps;

/// <summary>
/// Browsers whose address bars the Windows agent can observe. They are always
/// allowed on PC; this list is for history capture, never browser restriction.
/// </summary>
public static class Browsers
{
    public static readonly IReadOnlySet<string> Known = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe",
        "opera.exe", "opera_gx.exe", "vivaldi.exe", "iexplore.exe",
        "chromium.exe", "waterfox.exe", "librewolf.exe", "floorp.exe",
        "zen.exe", "arc.exe", "duckduckgo.exe", "avastbrowser.exe",
        "avgsecurebrowser.exe", "thorium.exe",
    };

    private static readonly IReadOnlySet<string> Gecko = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "firefox.exe", "waterfox.exe", "librewolf.exe", "floorp.exe", "zen.exe",
    };

    public static bool IsBrowser(string executableKey) => Known.Contains(executableKey);

    public static bool IsGecko(string executableKey) => Gecko.Contains(executableKey);

    public static IReadOnlySet<string> RemoveFrom(IReadOnlySet<string> blocked) =>
        new HashSet<string>(
            blocked.Where(executable => !IsBrowser(executable)),
            StringComparer.OrdinalIgnoreCase);
}

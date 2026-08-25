namespace GuardNest.Core;

/// <summary>
/// The Firebase project shared with the Android child app and the parent app.
/// These are public client identifiers; firestore.rules is what actually
/// controls access.
/// </summary>
public static class AppConfig
{
    public const string ProjectId = "guardnest-1ec2c";
    public const string ApiKey = "AIzaSyASJIA4PM0kQHy2MWEnaQdhejTqdQuRMw4";

    /// Matches `platform` on the device record, which the parent app already
    /// renders with a Windows icon.
    public const string Platform = "windows";

    /// The OTA manifest for this platform (`appConfig/kid` is the Android one).
    public const string UpdateDocument = "appConfig/win";

    public const int VersionCode = 8;
    public const string VersionName = "1.0.7";
    public static string VersionLabel => $"v{VersionName}({VersionCode})";

    /// <summary>
    /// Thumbprint of the code-signing certificate updates must carry. Empty
    /// until that certificate exists, which downgrades the OTA check to "signed
    /// by someone with a valid chain" — fill this in before shipping.
    /// </summary>
    public const string PublisherThumbprint = "";

    /// Machine-wide so the service (LocalSystem) and the installer agree.
    public static string DataDirectory { get; } = ResolveDataDirectory();

    /// True when a developer redirected storage; such a folder is left alone
    /// instead of being locked to SYSTEM, which would make it unwritable.
    public static bool UsingCustomDataDirectory { get; private set; }

    public static string PipeName => "GuardNest.Agent";

    /// <summary>
    /// The real folder is locked to SYSTEM and administrators, which a developer
    /// running the service in a console cannot write to. The override is ignored
    /// under the service itself (services are not user-interactive), so a child
    /// cannot point the agent at a folder they control.
    /// </summary>
    private static string ResolveDataDirectory()
    {
        var custom = Environment.GetEnvironmentVariable("GUARDNEST_DATA");
        if (Environment.UserInteractive && !string.IsNullOrWhiteSpace(custom))
        {
            UsingCustomDataDirectory = true;
            return custom;
        }
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "GuardNest");
    }
}

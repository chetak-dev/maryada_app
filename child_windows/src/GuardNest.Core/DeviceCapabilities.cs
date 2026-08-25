namespace GuardNest.Core;

/// <summary>
/// What this platform can actually report. The parent app hides a feed that no
/// device supports, so a PC-only profile stops showing an empty Calls screen
/// that will never fill.
/// </summary>
public static class DeviceCapabilities
{
    public static IReadOnlyDictionary<string, object?> AsMap() => new Dictionary<string, object?>
    {
        ["screenTime"] = true,
        ["appBlocking"] = true,
        ["usage"] = true,
        ["webFilter"] = true,
        ["webHistory"] = true,
        ["youtube"] = true,
        ["chats"] = true,
        ["calls"] = false,
        ["sms"] = false,
        ["location"] = false,
    };
}

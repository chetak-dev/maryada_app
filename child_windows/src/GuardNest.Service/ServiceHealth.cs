using Microsoft.Win32;

namespace GuardNest.Service;

/// <summary>
/// The Windows equivalent of Android's permission grants: the things that must
/// stay true for monitoring to survive a reboot. Deliberately excludes whether
/// the session agent is connected — nobody is logged in at the sign-in screen,
/// and that is not a fault the parent should be alerted about.
/// </summary>
public static class ServiceHealth
{
    public const string ServiceName = "GuardNest";

    public static IReadOnlyDictionary<string, bool> Protections(bool runningAsService)
    {
        var protections = new Dictionary<string, bool> { ["service"] = true };
        if (runningAsService) protections["startup"] = AutoStartEnabled();
        return protections;
    }

    /// <summary>Start type 2 is "Automatic"; anything else means a reboot ends monitoring.</summary>
    public static bool AutoStartEnabled()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(
                $@"SYSTEM\CurrentControlSet\Services\{ServiceName}");
            return key?.GetValue("Start") is int start && start == 2;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}

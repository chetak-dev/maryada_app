using System.Security.AccessControl;
using System.Security.Principal;

namespace GuardNest.Core;

/// <summary>
/// The machine-wide folder both halves of the agent read. It holds the device
/// identity, so it is locked down to SYSTEM and administrators: a standard user
/// must not be able to read the refresh token or edit the pairing out of it.
/// </summary>
public static class DataFolder
{
    private static bool _prepared;

    public static string Path(string fileName)
    {
        Prepare();
        return System.IO.Path.Combine(AppConfig.DataDirectory, fileName);
    }

    public static void Prepare()
    {
        if (_prepared) return;
        var directory = new DirectoryInfo(AppConfig.DataDirectory);
        if (!directory.Exists) directory.Create();
        if (!AppConfig.UsingCustomDataDirectory) TryRestrictAccess(directory);
        _prepared = true;
    }

    private static void TryRestrictAccess(DirectoryInfo directory)
    {
        try
        {
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
            foreach (var sid in new[] { WellKnownSidType.LocalSystemSid, WellKnownSidType.BuiltinAdministratorsSid })
            {
                security.AddAccessRule(new FileSystemAccessRule(
                    new SecurityIdentifier(sid, null),
                    FileSystemRights.FullControl,
                    InheritanceFlags.ObjectInherit | InheritanceFlags.ContainerInherit,
                    PropagationFlags.None,
                    AccessControlType.Allow));
            }
            directory.SetAccessControl(security);
        }
        catch (Exception e) when (e is UnauthorizedAccessException or InvalidOperationException)
        {
            // Running unelevated during development: the folder still works, it
            // is just not hardened. The installer applies this properly.
        }
    }
}

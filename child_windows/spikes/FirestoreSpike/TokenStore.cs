using System.Security.Cryptography;
using System.Text;

namespace GuardNest.Windows.Spikes.Firestore;

/// <summary>
/// Persists the refresh token so the device keeps ONE anonymous uid for its
/// whole life — the uid is the device's identity in `devices/{uid}`, so losing
/// it means losing the pairing.
///
/// Spike scope: DPAPI under the current user. The real service runs as
/// LocalSystem and must use <see cref="DataProtectionScope.LocalMachine"/> with
/// the file under ProgramData, ACL'd to SYSTEM + Administrators only —
/// LocalMachine scope alone lets any local user decrypt it.
/// </summary>
internal static class TokenStore
{
    private static readonly byte[] Entropy =
        Encoding.UTF8.GetBytes("GuardNest.Windows.spike.v1");

    private static string Path => System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "GuardNest",
        "spike-auth.dat");

    public static void Save(string json)
    {
        var dir = System.IO.Path.GetDirectoryName(Path)!;
        Directory.CreateDirectory(dir);
        var blob = ProtectedData.Protect(
            Encoding.UTF8.GetBytes(json), Entropy, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(Path, blob);
    }

    public static string? Load()
    {
        try
        {
            if (!File.Exists(Path)) return null;
            var plain = ProtectedData.Unprotect(
                File.ReadAllBytes(Path), Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plain);
        }
        catch (CryptographicException)
        {
            // Copied to another machine or another user: start over rather than
            // leaving the agent permanently unable to sign in.
            return null;
        }
    }

    public static void Clear()
    {
        try { File.Delete(Path); } catch (IOException) { }
    }
}

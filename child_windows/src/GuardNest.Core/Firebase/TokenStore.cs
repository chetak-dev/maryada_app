using System.Security.Cryptography;
using System.Text;

namespace GuardNest.Core.Firebase;

/// <summary>
/// Keeps the refresh token, and therefore the device's anonymous uid, across
/// restarts. The uid is this installation's identity in `devices/{uid}`: minting
/// a new one silently orphans the pairing, so losing this file is losing the
/// device.
/// </summary>
public static class TokenStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("GuardNest.Windows.identity.v1");

    private static string Path => DataFolder.Path("identity.dat");

    public static void Save(string json)
    {
        try
        {
            var blob = ProtectedData.Protect(
                Encoding.UTF8.GetBytes(json), Entropy, DataProtectionScope.LocalMachine);
            File.WriteAllBytes(Path, blob);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // The device keeps working this session but will come back as a new
            // uid after a restart, so this must be visible to the parent.
            Diag.Warn("tokenStore.save", e);
        }
    }

    public static string? Load()
    {
        try
        {
            if (!File.Exists(Path)) return null;
            var plain = ProtectedData.Unprotect(
                File.ReadAllBytes(Path), Entropy, DataProtectionScope.LocalMachine);
            return Encoding.UTF8.GetString(plain);
        }
        catch (CryptographicException)
        {
            // Copied from another machine: start over rather than leaving the
            // device permanently unable to sign in.
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static void Clear()
    {
        try { File.Delete(Path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}

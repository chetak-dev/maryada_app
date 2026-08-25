using Microsoft.Win32;

namespace GuardNest.Core;

/// <summary>Machine identity and Windows edition facts the parent app displays.</summary>
public static class SystemInfo
{
    private const string BiosKey = @"HARDWARE\DESCRIPTION\System\BIOS";
    private const string CurrentVersionKey = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion";

    public static string Manufacturer() => ReadLocalMachine(BiosKey, "SystemManufacturer");

    public static string Model() => ReadLocalMachine(BiosKey, "SystemProductName");

    /// <summary>e.g. "Windows 11 Home 23H2" — decides which enforcement tier applies.</summary>
    public static string WindowsEdition()
    {
        var product = ReadLocalMachine(CurrentVersionKey, "ProductName");
        var display = ReadLocalMachine(CurrentVersionKey, "DisplayVersion");
        // Windows 11 still reports "Windows 10 ..." here; the build number is
        // the only reliable discriminator.
        if (product.StartsWith("Windows 10", StringComparison.OrdinalIgnoreCase) &&
            Environment.OSVersion.Version.Build >= 22000)
        {
            product = "Windows 11" + product["Windows 10".Length..];
        }
        return display.Length > 0 ? $"{product} {display}" : product;
    }

    /// <summary>
    /// True on editions without AppLocker/WDAC, where app blocking falls back to
    /// terminating the process rather than refusing to start it.
    /// </summary>
    public static bool IsHomeEdition() =>
        WindowsEdition().Contains("Home", StringComparison.OrdinalIgnoreCase);

    private static string ReadLocalMachine(string key, string value)
    {
        try
        {
            using var subKey = Registry.LocalMachine.OpenSubKey(key);
            return subKey?.GetValue(value)?.ToString()?.Trim() ?? "";
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return "";
        }
    }
}

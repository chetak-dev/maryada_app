using GuardNest.Core;
using Microsoft.Extensions.Logging;
using Microsoft.Win32;

namespace GuardNest.Service;

/// <summary>
/// Turns DNS-over-HTTPS off by policy. Without this the whole DNS filter is
/// decorative: a browser resolving names inside its own TLS session never asks
/// Windows, so it never reaches the local resolver.
/// </summary>
public static class DohPolicy
{
    private sealed record Setting(string Key, string Name, object Value, RegistryValueKind Kind);

    private static readonly Setting[] Settings =
    {
        new(@"SOFTWARE\Policies\Google\Chrome", "DnsOverHttpsMode", "off", RegistryValueKind.String),
        new(@"SOFTWARE\Policies\Microsoft\Edge", "DnsOverHttpsMode", "off", RegistryValueKind.String),
        new(@"SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS", "Enabled", 0, RegistryValueKind.DWord),
        new(@"SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS", "Locked", 1, RegistryValueKind.DWord),
        new(@"SYSTEM\CurrentControlSet\Services\Dnscache\Parameters", "EnableAutoDoh", 0, RegistryValueKind.DWord),
    };

    /// <summary>Applies every policy it can; returns true when all of them held.</summary>
    public static bool Apply(ILogger log)
    {
        var applied = true;
        foreach (var setting in Settings)
        {
            try
            {
                using var key = Registry.LocalMachine.CreateSubKey(setting.Key, writable: true);
                if (key is null)
                {
                    applied = false;
                    continue;
                }
                key.SetValue(setting.Name, setting.Value, setting.Kind);
            }
            catch (Exception e) when (e is UnauthorizedAccessException or System.Security.SecurityException or IOException)
            {
                applied = false;
                log.LogWarning("Could not enforce {Policy}: {Reason}", setting.Name, e.Message);
                Diag.Warn("doh.policy", e);
            }
        }
        return applied;
    }

    /// <summary>True when every kill-switch is already in place.</summary>
    public static bool IsEnforced()
    {
        foreach (var setting in Settings)
        {
            try
            {
                using var key = Registry.LocalMachine.OpenSubKey(setting.Key);
                var current = key?.GetValue(setting.Name)?.ToString();
                if (!string.Equals(current, setting.Value.ToString(), StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return false;
            }
        }
        return true;
    }
}

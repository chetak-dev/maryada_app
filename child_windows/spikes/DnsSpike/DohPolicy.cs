using Microsoft.Win32;

namespace GuardNest.Windows.Spikes.Dns;

/// <summary>
/// DNS-over-HTTPS defeats a local resolver completely: the browser resolves
/// names inside a TLS session to its own provider and never asks Windows. Any
/// DNS-based filtering is therefore only as good as these policies, which is
/// what this report checks.
/// </summary>
internal static class DohPolicy
{
    private sealed record Check(string Label, string Key, string Value, string Required);

    private static readonly Check[] Checks =
    {
        new("Chrome  DoH", @"SOFTWARE\Policies\Google\Chrome", "DnsOverHttpsMode", "off"),
        new("Edge    DoH", @"SOFTWARE\Policies\Microsoft\Edge", "DnsOverHttpsMode", "off"),
        new("Firefox DoH", @"SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS", "Enabled", "0"),
        new("Firefox lock", @"SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS", "Locked", "1"),
        new("Windows auto-DoH",
            @"SYSTEM\CurrentControlSet\Services\Dnscache\Parameters", "EnableAutoDoh", "0"),
    };

    public static bool Report()
    {
        var allSet = true;
        foreach (var check in Checks)
        {
            using var key = Registry.LocalMachine.OpenSubKey(check.Key);
            var value = key?.GetValue(check.Value)?.ToString();
            var ok = string.Equals(value, check.Required, StringComparison.OrdinalIgnoreCase);
            allSet &= ok;
            Console.WriteLine(
                $"  {check.Label,-18} {(ok ? "OK" : "NOT SET")}  " +
                $"(HKLM\\{check.Key}\\{check.Value} = {value ?? "<absent>"}, needs {check.Required})");
        }
        return allSet;
    }

    public static void PrintFixCommands()
    {
        Console.WriteLine("  Run elevated to enforce them (the installer will do this):");
        foreach (var check in Checks)
        {
            var type = check.Required is "off" ? "String" : "DWord";
            Console.WriteLine(
                $"    New-ItemProperty -Path 'HKLM:\\{check.Key}' -Name '{check.Value}' " +
                $"-Value {(type == "String" ? $"'{check.Required}'" : check.Required)} " +
                $"-PropertyType {type} -Force");
        }
    }
}

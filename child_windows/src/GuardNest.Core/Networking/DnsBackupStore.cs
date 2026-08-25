using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;

namespace GuardNest.Core.Networking;

/// <summary>Preserves the DNS configuration that existed before filtering.</summary>
public static class DnsBackupStore
{
    private static string Path => DataFolder.Path("dns-backup.json");

    public static void CaptureIfMissing()
    {
        if (File.Exists(Path)) return;

        var adapters = new List<DnsAdapterState>();
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
            {
                continue;
            }

            var servers = adapter.GetIPProperties().DnsAddresses
                .Where(address => address.AddressFamily == AddressFamily.InterNetwork)
                .Select(address => address.ToString())
                .ToList();

            // Never preserve our own redirect as the original configuration.
            if (servers.Contains(IPAddress.Loopback.ToString())) continue;

            adapters.Add(new DnsAdapterState(
                adapter.Name,
                UsesDhcp(adapter.Name),
                servers));
        }

        var json = JsonSerializer.Serialize(adapters);
        File.WriteAllText(Path, json);
    }

    public static void Restore()
    {
        if (!File.Exists(Path)) return;

        List<DnsAdapterState>? adapters;
        try
        {
            adapters = JsonSerializer.Deserialize<List<DnsAdapterState>>(File.ReadAllText(Path));
        }
        catch (Exception error) when (error is IOException or JsonException)
        {
            Diag.Warn("dnsBackup.read", error);
            return;
        }

        foreach (var adapter in adapters ?? [])
        {
            if (adapter.Dhcp || adapter.Servers.Count == 0)
            {
                RunNetsh($"interface ipv4 set dnsservers name=\"{Escape(adapter.Name)}\" source=dhcp");
                continue;
            }

            RunNetsh(
                $"interface ipv4 set dnsservers name=\"{Escape(adapter.Name)}\" " +
                $"static {adapter.Servers[0]} primary");
            for (var index = 1; index < adapter.Servers.Count; index++)
            {
                RunNetsh(
                    $"interface ipv4 add dnsservers name=\"{Escape(adapter.Name)}\" " +
                    $"address={adapter.Servers[index]} index={index + 1}");
            }
        }
    }

    public static void Delete()
    {
        try { File.Delete(Path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    private static bool UsesDhcp(string adapterName)
    {
        var output = RunNetsh(
            $"interface ipv4 show dnsservers name=\"{Escape(adapterName)}\"",
            captureOutput: true);
        return output.Contains("through DHCP", StringComparison.OrdinalIgnoreCase);
    }

    private static string RunNetsh(string arguments, bool captureOutput = false)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo("netsh", arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = captureOutput,
                RedirectStandardError = captureOutput,
            });
            if (process is null) return "";
            var output = captureOutput ? process.StandardOutput.ReadToEnd() : "";
            var error = captureOutput ? process.StandardError.ReadToEnd() : "";
            process.WaitForExit(15_000);
            return output + error;
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            Diag.Warn("dnsBackup.netsh", error);
            return "";
        }
    }

    private static string Escape(string value) => value.Replace("\"", "");

    private sealed record DnsAdapterState(string Name, bool Dhcp, List<string> Servers);
}
using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using GuardNest.Core;
using GuardNest.Core.Networking;
using Microsoft.Extensions.Logging;

namespace GuardNest.Service.Dns;

/// <summary>
/// Points every network adapter at the local filter and puts them back
/// afterwards. Kept separate from the resolver itself because this is the part
/// that can take a machine off the network if it goes wrong.
/// </summary>
public sealed class DnsRedirect
{
    private readonly ILogger _log;
    private readonly List<string> _redirected = new();

    public DnsRedirect(ILogger log)
    {
        _log = log;
    }

    /// <summary>The resolvers currently in use, so the filter can forward to them.</summary>
    public static IReadOnlyList<IPAddress> CurrentUpstreams()
    {
        var servers = new List<IPAddress>();
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.OperationalStatus != OperationalStatus.Up) continue;
            if (adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var server in adapter.GetIPProperties().DnsAddresses)
            {
                if (server.AddressFamily != AddressFamily.InterNetwork) continue;
                if (IPAddress.IsLoopback(server)) continue;
                if (!servers.Contains(server)) servers.Add(server);
            }
        }
        return servers;
    }

    public void Apply()
    {
        DnsBackupStore.CaptureIfMissing();
        foreach (var adapter in Adapters())
        {
            if (Run($"interface ipv4 set dnsservers name=\"{adapter}\" static 127.0.0.1 primary"))
            {
                _redirected.Add(adapter);
                _log.LogInformation("DNS for {Adapter} now points at the local filter", adapter);
            }
        }
    }

    public void Restore()
    {
        DnsBackupStore.Restore();
        _redirected.Clear();
    }

    private static IEnumerable<string> Adapters() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(a => a.OperationalStatus == OperationalStatus.Up
                        && a.NetworkInterfaceType != NetworkInterfaceType.Loopback
                        && a.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
            .Select(a => a.Name);

    private bool Run(string arguments)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo("netsh", arguments)
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            });
            if (process is null) return false;
            process.WaitForExit(10_000);
            return process.ExitCode == 0;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            Diag.Warn("dns.netsh", e);
            return false;
        }
    }
}

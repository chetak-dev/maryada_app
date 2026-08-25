using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Principal;

namespace GuardNest.Windows.Spikes.Dns;

/// <summary>
/// Phase 0 spike C — proves the network half of web filtering: a local resolver
/// that blocks names and forwards the rest, plus a report on the DNS-over-HTTPS
/// policies that decide whether browsers will even use it.
/// </summary>
internal static class Program
{
    private const string BlockedName = "doubleclick.net";
    private const string AllowedName = "example.com";

    private static async Task<int> Main(string[] args)
    {
        var port = args.Length > 0 && int.TryParse(args[0], out var p) ? p : 5354;
        var sinkhole = args.Contains("--sinkhole");

        Console.WriteLine("=== Spike C: local DNS filter + DoH kill-switch ===");
        Console.WriteLine();
        Console.WriteLine($"[1] elevation: {(IsElevated() ? "elevated" : "NOT elevated (port 53 and policy writes need admin)")}" );
        Console.WriteLine();

        Console.WriteLine("[2] DNS-over-HTTPS policy state");
        var policiesSet = DohPolicy.Report();
        if (!policiesSet)
        {
            Console.WriteLine();
            DohPolicy.PrintFixCommands();
        }
        Console.WriteLine();

        Console.WriteLine($"[3] starting the filter on 127.0.0.1:{port} " +
                          $"({(sinkhole ? "sinkhole 127.0.0.1" : "NXDOMAIN")} for blocked names)");
        using var cts = new CancellationTokenSource();
        using var proxy = new DnsProxy(
            port,
            new IPEndPoint(IPAddress.Parse("1.1.1.1"), 53),
            new[] { BlockedName },
            sinkhole);
        var serving = proxy.ServeAsync(cts.Token);
        Console.WriteLine();

        Console.WriteLine("[4] queries through the filter");
        var blockedOk = await QueryAsync(proxy.Port, BlockedName, expectBlocked: true);
        var allowedOk = await QueryAsync(proxy.Port, AllowedName, expectBlocked: false);
        var subdomainOk = await QueryAsync(proxy.Port, "ads." + BlockedName, expectBlocked: true);
        Console.WriteLine();

        cts.Cancel();
        await Task.WhenAny(serving, Task.Delay(1000));

        Console.WriteLine("=== result ===");
        Console.WriteLine($"  blocked name refused    : {(blockedOk ? "PASS" : "FAIL")}");
        Console.WriteLine($"  subdomain also refused  : {(subdomainOk ? "PASS" : "FAIL")}");
        Console.WriteLine($"  allowed name forwarded  : {(allowedOk ? "PASS" : "FAIL")}");
        Console.WriteLine($"  DoH policies enforced   : {(policiesSet ? "PASS" : "NOT YET — browsers can bypass DNS filtering")}");
        return blockedOk && allowedOk && subdomainOk ? 0 : 1;
    }

    private static async Task<bool> QueryAsync(int port, string name, bool expectBlocked)
    {
        using var client = new UdpClient();
        var query = DnsMessage.Query(name, (ushort)Random.Shared.Next(1, ushort.MaxValue));
        var sw = Stopwatch.StartNew();
        await client.SendAsync(query, query.Length, new IPEndPoint(IPAddress.Loopback, port));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        try
        {
            var reply = await client.ReceiveAsync(timeout.Token);
            sw.Stop();
            var rcode = DnsMessage.ResponseCode(reply.Buffer);
            var answers = DnsMessage.AnswerCount(reply.Buffer);
            Console.WriteLine(
                $"  {name,-24} rcode={rcode} answers={answers} in {sw.ElapsedMilliseconds} ms");
            return expectBlocked ? rcode == 3 || answers == 1 : rcode == 0 && answers > 0;
        }
        catch (OperationCanceledException)
        {
            Console.WriteLine($"  {name,-24} no reply (timeout)");
            return false;
        }
    }

    private static bool IsElevated()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }
}

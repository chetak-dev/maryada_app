using System.Net;
using System.Net.Sockets;
using GuardNest.Core;
using GuardNest.Core.Web;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Hosting.WindowsServices;
using Microsoft.Extensions.Logging;

namespace GuardNest.Service.Dns;

/// <summary>
/// The network half of web filtering: a local resolver that refuses blocked
/// names and forwards everything else. It stops a page loading at all, which
/// the on-screen block cannot do on its own.
/// </summary>
public sealed class DnsFilterService : BackgroundService
{
    private const int Port = 53;

    private readonly ILogger<DnsFilterService> _log;
    private readonly WebFilter _filter;
    private readonly WebActivity _activity;
    private DnsRedirect? _redirect;
    private IPEndPoint _upstream = new(IPAddress.Parse("1.1.1.1"), 53);

    public DnsFilterService(ILogger<DnsFilterService> log, WebFilter filter, WebActivity activity)
    {
        _log = log;
        _filter = filter;
        _activity = activity;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        UdpClient listener;
        try
        {
            listener = new UdpClient(new IPEndPoint(IPAddress.Loopback, Port));
        }
        catch (SocketException e)
        {
            // Port 53 needs elevation and a free port; without it the address-bar
            // filter still works, so this is a degraded mode, not a failure.
            _log.LogWarning(e, "DNS filter could not bind port {Port}; on-screen filtering only", Port);
            return;
        }

        // Read the real resolvers before redirecting, or we would forward every
        // query straight back to ourselves.
        var discovered = DnsRedirect.CurrentUpstreams().FirstOrDefault();
        if (discovered is not null) _upstream = new IPEndPoint(discovered, 53);
        _log.LogInformation("DNS filter listening on 127.0.0.1:{Port}, upstream {Upstream}", Port, _upstream);

        // Only an installed service touches the machine's DNS settings. A
        // developer running this in a console must not have their network
        // rewritten underneath them.
        if (WindowsServiceHelpers.IsWindowsService())
        {
            _redirect = new DnsRedirect(_log);
            _redirect.Apply();
        }

        try
        {
            using var upstreamClient = new UdpClient();
            while (!ct.IsCancellationRequested)
            {
                var request = await listener.ReceiveAsync(ct);
                _ = HandleAsync(listener, upstreamClient, request, ct);
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception e)
        {
            _log.LogError(e, "DNS filter stopped");
            Diag.Warn("dns.serve", e);
        }
        finally
        {
            _redirect?.Restore();
            listener.Dispose();
        }
    }

    private async Task HandleAsync(
        UdpClient listener, UdpClient upstream, UdpReceiveResult request, CancellationToken ct)
    {
        try
        {
            var name = DnsMessage.ReadQuestion(request.Buffer, out var questionEnd);
            if (name is null) return;

            var reason = _filter.ReasonFor(name);
            if (reason is not null)
            {
                var denial = DnsMessage.NxDomain(request.Buffer, questionEnd);
                await listener.SendAsync(denial, denial.Length, request.RemoteEndPoint);
                _activity.RecordBlocked(name, reason);
                return;
            }

            await upstream.SendAsync(request.Buffer, request.Buffer.Length, _upstream);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(3));
            var reply = await upstream.ReceiveAsync(timeout.Token);
            await listener.SendAsync(reply.Buffer, reply.Buffer.Length, request.RemoteEndPoint);
        }
        catch (Exception e) when (e is OperationCanceledException or SocketException or ObjectDisposedException)
        {
            // One lost query is not worth a log line; the client retries.
        }
    }
}

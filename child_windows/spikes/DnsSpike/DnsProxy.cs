using System.Net;
using System.Net.Sockets;

namespace GuardNest.Windows.Spikes.Dns;

/// <summary>
/// A local resolver that answers blocked names itself and forwards everything
/// else. In production it binds 127.0.0.1:53 and every adapter's DNS server is
/// pointed at it, which is the network-level half of web filtering (the UI
/// Automation watcher is the other half).
/// </summary>
internal sealed class DnsProxy : IDisposable
{
    private readonly UdpClient _listener;
    private readonly IPEndPoint _upstream;
    private readonly HashSet<string> _blocked;
    private readonly bool _sinkhole;

    public DnsProxy(int port, IPEndPoint upstream, IEnumerable<string> blocked, bool sinkhole)
    {
        _listener = new UdpClient(new IPEndPoint(IPAddress.Loopback, port));
        _upstream = upstream;
        _blocked = new HashSet<string>(blocked, StringComparer.OrdinalIgnoreCase);
        _sinkhole = sinkhole;
    }

    public int Port => ((IPEndPoint)_listener.Client.LocalEndPoint!).Port;
    public int Forwarded { get; private set; }
    public int Blocked { get; private set; }

    public async Task ServeAsync(CancellationToken ct)
    {
        using var upstreamClient = new UdpClient();
        while (!ct.IsCancellationRequested)
        {
            UdpReceiveResult request;
            try
            {
                request = await _listener.ReceiveAsync(ct);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            var name = DnsMessage.ReadQuestion(request.Buffer, out var questionEnd);
            if (name is null)
            {
                continue;
            }

            if (IsBlocked(name))
            {
                Blocked++;
                var denial = _sinkhole
                    ? DnsMessage.Sinkhole(request.Buffer, questionEnd, new byte[] { 127, 0, 0, 1 })
                    : DnsMessage.NxDomain(request.Buffer, questionEnd);
                await _listener.SendAsync(denial, denial.Length, request.RemoteEndPoint);
                Console.WriteLine($"  BLOCK  {name}");
                continue;
            }

            try
            {
                await upstreamClient.SendAsync(request.Buffer, request.Buffer.Length, _upstream);
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(3));
                var reply = await upstreamClient.ReceiveAsync(timeout.Token);
                await _listener.SendAsync(reply.Buffer, reply.Buffer.Length, request.RemoteEndPoint);
                Forwarded++;
                Console.WriteLine($"  allow  {name}");
            }
            catch (OperationCanceledException)
            {
                Console.WriteLine($"  (upstream timeout for {name})");
            }
            catch (SocketException ex)
            {
                Console.WriteLine($"  (upstream error for {name}: {ex.SocketErrorCode})");
            }
        }
    }

    /// A blocked domain covers its subdomains, the way a blocklist entry is meant
    /// to: blocking example.com must also stop ads.example.com.
    private bool IsBlocked(string name)
    {
        var candidate = name;
        while (candidate.Length > 0)
        {
            if (_blocked.Contains(candidate)) return true;
            var dot = candidate.IndexOf('.');
            if (dot < 0) return false;
            candidate = candidate[(dot + 1)..];
        }
        return false;
    }

    public void Dispose() => _listener.Dispose();
}

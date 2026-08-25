using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using GuardNest.Core;
using GuardNest.Core.Firebase;

namespace GuardNest.Setup;

/// <summary>
/// Asks the parent's records whether this PC is still linked.
///
/// The local pairing file is only cleared once the protection service is
/// refused by Firestore, which can take a minute. Removal would otherwise stay
/// blocked for that minute after a parent has already removed the device.
/// </summary>
internal static class RemovalCheck
{
    internal enum LinkStatus
    {
        StillLinked,
        Removed,
        Unknown,
    }

    public static async Task<LinkStatus> ConfirmAsync(CancellationToken ct = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        using var handler = new SocketsHttpHandler { ConnectCallback = ConnectIpv4Async };
        using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(18) };

        try
        {
            var auth = new AnonymousAuth(http, AppConfig.ApiKey);
            await auth.GetIdTokenAsync(timeout.Token);
            if (auth.Uid.Length == 0) return LinkStatus.Unknown;

            var firestore = new FirestoreClient(http, auth, AppConfig.ProjectId);
            var registration = await firestore.GetAsync($"devices/{auth.Uid}", timeout.Token);
            return registration is null ? LinkStatus.Removed : LinkStatus.StillLinked;
        }
        catch (FirestoreException error) when (error.PermissionDenied)
        {
            // The rules only reject a device the parent has taken off the family.
            return LinkStatus.Removed;
        }
        catch (Exception error) when (
            error is HttpRequestException or FirestoreException or OperationCanceledException)
        {
            return LinkStatus.Unknown;
        }
    }

    private static async ValueTask<Stream> ConnectIpv4Async(
        SocketsHttpConnectionContext context,
        CancellationToken ct)
    {
        var addresses = await Dns.GetHostAddressesAsync(context.DnsEndPoint.Host, ct);
        Exception? lastError = null;
        foreach (var address in addresses.Where(a => a.AddressFamily == AddressFamily.InterNetwork))
        {
            var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
            try
            {
                await socket.ConnectAsync(new IPEndPoint(address, context.DnsEndPoint.Port), ct);
                return new NetworkStream(socket, ownsSocket: true);
            }
            catch (Exception error) when (error is SocketException or OperationCanceledException)
            {
                socket.Dispose();
                lastError = error;
                if (error is OperationCanceledException) throw;
            }
        }

        throw new HttpRequestException(
            $"No IPv4 connection to {context.DnsEndPoint.Host} succeeded.",
            lastError);
    }
}

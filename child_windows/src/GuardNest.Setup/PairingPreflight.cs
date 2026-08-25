using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using GuardNest.Core;
using GuardNest.Core.Firebase;

namespace GuardNest.Setup;

/// <summary>Checks a code without installing, claiming, burning, or persisting it.</summary>
internal static class PairingPreflight
{
    private const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    public static async Task<(bool Ok, string Message)> ValidateAsync(
        string code,
        CancellationToken ct = default)
    {
        var normalized = code.Trim().ToUpperInvariant();
        if (normalized.Length != 6 || normalized.Any(character => !CodeAlphabet.Contains(character)))
        {
            return (false, "Enter a valid 6-character pairing code.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        using var handler = new SocketsHttpHandler
        {
            ConnectCallback = ConnectIpv4Async,
        };
        using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(18) };

        try
        {
            var auth = new AnonymousAuth(http, AppConfig.ApiKey, persistIdentity: false);
            var firestore = new FirestoreClient(http, auth, AppConfig.ProjectId);
            var pairing = new PairingService(firestore, auth);
            await pairing.ValidateAsync(normalized, timeout.Token);
            return (true, "Pairing code verified.");
        }
        catch (PairingException error)
        {
            return (false, error.Message);
        }
        catch (OperationCanceledException)
        {
            return (false, "Code check timed out. Check the internet connection and try again.");
        }
        catch (Exception error) when (error is HttpRequestException or FirestoreException)
        {
            return (false, "Couldn't check the code. Check the internet connection and try again.");
        }
    }

    private static async ValueTask<Stream> ConnectIpv4Async(
        SocketsHttpConnectionContext context,
        CancellationToken ct)
    {
        var addresses = await Dns.GetHostAddressesAsync(context.DnsEndPoint.Host, ct);
        Exception? lastError = null;
        foreach (var address in addresses.Where(address => address.AddressFamily == AddressFamily.InterNetwork))
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
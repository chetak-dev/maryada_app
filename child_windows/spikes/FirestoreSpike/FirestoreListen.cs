using Google.Cloud.Firestore;
using Google.Api.Gax.Grpc;
using Grpc.Core;
using Grpc.Net.Client;
using Microsoft.Extensions.Logging;

namespace GuardNest.Windows.Spikes.Firestore;

/// <summary>
/// The open question this spike answers: can the Google.Cloud.Firestore client
/// — built for service accounts — be driven by a Firebase *anonymous* ID token
/// so the Windows agent gets realtime rule updates instead of polling?
/// </summary>
internal static class FirestoreListen
{
    /// <summary>
    /// Builds a Firestore client whose every gRPC call carries the device's
    /// anonymous Firebase ID token instead of service-account credentials.
    /// </summary>
    public static Task<FirestoreDb> ConnectAsync(
        AnonymousAuth auth, string projectId, bool verbose, bool bypassProxy,
        CancellationToken ct)
    {
        // Invoked per RPC, and again whenever the client retries the stream, so
        // an hour-long Listen survives token expiry as long as we hand back a
        // freshly refreshed token here.
        var callCredentials = CallCredentials.FromInterceptor(async (_, metadata) =>
        {
            var token = await auth.GetIdTokenAsync(CancellationToken.None);
            metadata.Add("Authorization", "Bearer " + token);
        });

        var builder = new FirestoreDbBuilder
        {
            ProjectId = projectId,
            ChannelCredentials =
                ChannelCredentials.Create(ChannelCredentials.SecureSsl, callCredentials),
        };

        // gRPC's load balancer and an HTTP proxy do not mix: behind one, every
        // call dies with "Unable to get subchannel from HttpRequestMessage".
        var loggers = verbose
            ? LoggerFactory.Create(b => b.AddConsole().SetMinimumLevel(LogLevel.Debug))
            : null;
        if (verbose || bypassProxy)
        {
            builder.GrpcAdapter = GrpcNetClientAdapter.Default.WithAdditionalOptions(
                (Grpc.Net.Client.GrpcChannelOptions options) =>
                {
                    if (loggers is not null) options.LoggerFactory = loggers;
                    if (bypassProxy)
                    {
                        options.HttpHandler = new SocketsHttpHandler { UseProxy = false };
                    }
                });
        }

        return builder.BuildAsync(ct);
    }

    /// <summary>
    /// A single unary gRPC read. Separates "gRPC/credentials are broken" from
    /// "the Listen stream specifically is broken" — without it a silent stream
    /// looks identical to a blocked HTTP/2 connection.
    /// </summary>
    public static async Task<bool> ProbeAsync(
        AnonymousAuth auth, string projectId, string path, bool verbose, bool bypassProxy,
        CancellationToken ct)
    {
        var db = await ConnectAsync(auth, projectId, verbose, bypassProxy, ct);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        var started = DateTime.UtcNow;
        try
        {
            var snapshot = await db.Document(path).GetSnapshotAsync(timeout.Token);
            Console.WriteLine(
                $"  unary gRPC read -> exists={snapshot.Exists} " +
                $"in {(int)(DateTime.UtcNow - started).TotalMilliseconds} ms");
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  unary gRPC read -> {ex.GetType().Name}: {ex.Message}");
            return false;
        }
    }

    /// <summary>Returns how many snapshots arrived before the token was cancelled.</summary>
    public static async Task<int> RunAsync(
        AnonymousAuth auth, string projectId, string path, bool verbose, bool bypassProxy,
        CancellationToken ct)
    {
        var db = await ConnectAsync(auth, projectId, verbose, bypassProxy, ct);

        var segments = path.Trim('/').Split('/');
        var isDocument = segments.Length % 2 == 0;
        Console.WriteLine($"  listening to {(isDocument ? "document" : "collection")} {path}");

        var updates = 0;
        FirestoreChangeListener listener = isDocument
            ? db.Document(path).Listen(snapshot =>
            {
                Interlocked.Increment(ref updates);
                Console.WriteLine(
                    $"  [{DateTime.Now:HH:mm:ss}] snapshot exists={snapshot.Exists} " +
                    $"fields={(snapshot.Exists ? snapshot.ToDictionary().Count : 0)}");
            })
            : db.Collection(path).Listen(snapshot =>
            {
                Interlocked.Increment(ref updates);
                Console.WriteLine(
                    $"  [{DateTime.Now:HH:mm:ss}] snapshot docs={snapshot.Count} " +
                    $"changes={snapshot.Changes.Count}");
            });

        // A broken stream (bad credentials, blocked gRPC) completes the listener
        // task instead of throwing here — waiting only on the delay would report
        // a dead listener as a success.
        var idle = Task.Delay(Timeout.Infinite, ct);
        var finished = await Task.WhenAny(listener.ListenerTask, idle);
        Console.WriteLine($"  listener task: {listener.ListenerTask.Status}");
        if (finished == listener.ListenerTask) await listener.ListenerTask;

        await listener.StopAsync(CancellationToken.None);
        return Volatile.Read(ref updates);
    }
}

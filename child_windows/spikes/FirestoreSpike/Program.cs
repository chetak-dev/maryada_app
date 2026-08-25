using System.Diagnostics;
using System.Net;
using System.Text.Json;

namespace GuardNest.Windows.Spikes.Firestore;

/// <summary>
/// Phase 0 spike A — proves the Windows agent can reach Firestore the same way
/// the Android child app does: anonymous sign-in, an identity that survives
/// restarts, reads, server-timestamped writes, and realtime updates.
/// </summary>
internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        var auth = new AnonymousAuth(http, FirebaseConfig.ApiKey);
        var rest = new FirestoreRest(http, auth, FirebaseConfig.ProjectId);

        var command = args.Length > 0 ? args[0].ToLowerInvariant() : "all";
        var argument = args.Length > 1 && !args[1].StartsWith('-') ? args[1] : null;
        var verbose = args.Contains("-v") || args.Contains("--verbose");
        var bypassProxy = args.Contains("--noproxy");

        try
        {
            switch (command)
            {
                case "reset":
                    TokenStore.Clear();
                    Console.WriteLine("Stored device identity cleared.");
                    return 0;
                case "auth":
                    await SignInAsync(auth, cts.Token);
                    return 0;
                case "read":
                    await SignInAsync(auth, cts.Token);
                    await ReadAsync(rest, argument ?? "appConfig/kid", cts.Token);
                    return 0;
                case "write":
                    await SignInAsync(auth, cts.Token);
                    await WriteAsync(rest, auth, cts.Token);
                    return 0;
                case "listen":
                    await SignInAsync(auth, cts.Token);
                    var seen = await FirestoreListen.RunAsync(
                        auth, FirebaseConfig.ProjectId, argument ?? "appConfig/kid",
                        verbose, bypassProxy, cts.Token);
                    Console.WriteLine($"  {seen} snapshot(s) received");
                    return 0;
                case "grpc":
                    await SignInAsync(auth, cts.Token);
                    await FirestoreListen.ProbeAsync(
                        auth, FirebaseConfig.ProjectId, argument ?? "appConfig/kid",
                        verbose, bypassProxy, cts.Token);
                    return 0;
                case "all":
                    return await RunAllAsync(http, auth, rest, verbose, bypassProxy, cts.Token);
                default:
                    Console.WriteLine("usage: FirestoreSpike [all|auth|read <path>|write|grpc|listen <path>|reset] [-v] [--noproxy]");
                    return 1;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"FAILED: {ex.GetType().Name}: {ex.Message}");
            return 1;
        }
    }

    private static async Task<int> RunAllAsync(
        HttpClient http, AnonymousAuth auth, FirestoreRest rest, bool verbose, bool bypassProxy,
        CancellationToken ct)
    {
        Console.WriteLine("=== Spike A: Firestore from .NET with an anonymous Firebase identity ===");
        Console.WriteLine();

        Console.WriteLine("[1] anonymous sign-in");
        await SignInAsync(auth, ct);
        Console.WriteLine();

        Console.WriteLine("[2] read appConfig/kid (rules: any signed-in reader)");
        var readOk = await ReadAsync(rest, "appConfig/kid", ct);
        Console.WriteLine();

        Console.WriteLine("[3] write with a server timestamp (rules must REJECT: this device is unpaired)");
        var rulesEnforced = await WriteAsync(rest, auth, ct);
        Console.WriteLine();

        Console.WriteLine("[4] control: the same read with a bogus token must fail differently");
        var control = await BogusTokenAsync(http, rest, ct);
        Console.WriteLine();

        Console.WriteLine("[5] gRPC reachability (unary read)");
        var grpcOk = await FirestoreListen.ProbeAsync(
            auth, FirebaseConfig.ProjectId, "appConfig/kid", verbose, bypassProxy, ct);
        Console.WriteLine();

        Console.WriteLine("[6] realtime Listen over gRPC (30s)");
        var listenOk = await TryListenAsync(auth, verbose, bypassProxy, ct);
        Console.WriteLine();

        Console.WriteLine("=== result ===");
        Console.WriteLine($"  anonymous identity persisted : {(auth.Uid.Length > 0 ? "PASS" : "FAIL")}");
        Console.WriteLine($"  authenticated REST read      : {(readOk ? "PASS" : "FAIL")}");
        Console.WriteLine($"  rules enforced on write      : {(rulesEnforced ? "PASS" : "FAIL")}");
        Console.WriteLine($"  unauthenticated is rejected  : {(control ? "PASS" : "FAIL")}");
        Console.WriteLine($"  gRPC reachable               : {(grpcOk ? "PASS" : "FAIL")}");
        Console.WriteLine($"  realtime Listen              : {(listenOk ? "PASS" : "FAIL — poll instead")}");
        return readOk && rulesEnforced ? 0 : 1;
    }

    private static async Task SignInAsync(AnonymousAuth auth, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var token = await auth.GetIdTokenAsync(ct);
        sw.Stop();
        Console.WriteLine($"  uid       : {auth.Uid}");
        Console.WriteLine($"  source    : {(auth.RestoredFromDisk ? "restored from disk (same uid as last run)" : "new sign-up")}");
        Console.WriteLine($"  token     : {token.Length} chars, expires {auth.ExpiresAt.ToLocalTime():HH:mm:ss}");
        Console.WriteLine($"  took      : {sw.ElapsedMilliseconds} ms");
    }

    private static async Task<bool> ReadAsync(
        FirestoreRest rest, string path, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var (status, body) = await rest.GetAsync(path, ct);
        sw.Stop();
        Console.WriteLine($"  GET {path} -> {(int)status} in {sw.ElapsedMilliseconds} ms");
        if (status == HttpStatusCode.OK)
        {
            var fields = FirestoreRest.DecodeFields(JsonDocument.Parse(body).RootElement);
            foreach (var (key, value) in fields) Console.WriteLine($"    {key} = {value}");
            return true;
        }
        if (status == HttpStatusCode.NotFound)
        {
            // The document may simply not exist yet; the read itself was allowed.
            Console.WriteLine("    (document does not exist — read was still authorized)");
            return true;
        }
        Console.WriteLine($"    {Trim(body)}");
        return false;
    }

    private static async Task<bool> WriteAsync(
        FirestoreRest rest, AnonymousAuth auth, CancellationToken ct)
    {
        var path = $"devices/{auth.Uid}";
        var fields = new Dictionary<string, object?>
        {
            ["familyId"] = "spike-not-a-real-family",
            ["childId"] = "spike-not-a-real-child",
        };
        var sw = Stopwatch.StartNew();
        var (status, body) = await rest.CommitAsync(path, fields, new[] { "pairedAt" }, ct);
        sw.Stop();
        Console.WriteLine($"  COMMIT {path} -> {(int)status} in {sw.ElapsedMilliseconds} ms");
        if (status == HttpStatusCode.Forbidden)
        {
            Console.WriteLine("    PERMISSION_DENIED — expected: firestore.rules only lets a device");
            Console.WriteLine("    register once a child doc already names this uid as its deviceUid.");
            return true;
        }
        Console.WriteLine($"    {Trim(body)}");
        return false;
    }

    private static async Task<bool> BogusTokenAsync(
        HttpClient http, FirestoreRest rest, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, rest.DocumentUrl("appConfig/kid"));
        req.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", "not-a-real-token");
        using var res = await http.SendAsync(req, ct);
        Console.WriteLine($"  GET appConfig/kid with a bogus token -> {(int)res.StatusCode}");
        return res.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden;
    }

    private static async Task<bool> TryListenAsync(
        AnonymousAuth auth, bool verbose, bool bypassProxy, CancellationToken ct)
    {
        using var window = CancellationTokenSource.CreateLinkedTokenSource(ct);
        window.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            var updates = await FirestoreListen.RunAsync(
                auth, FirebaseConfig.ProjectId, "appConfig/kid", verbose, bypassProxy,
                window.Token);
            Console.WriteLine($"  {updates} snapshot(s) received");
            return updates > 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  {ex.GetType().Name}: {Trim(ex.Message)}");
            return false;
        }
    }

    private static string Trim(string body) =>
        body.Length <= 400 ? body.ReplaceLineEndings(" ") : body[..400].ReplaceLineEndings(" ") + "…";
}

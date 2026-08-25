using System.Diagnostics;

namespace GuardNest.Windows.Spikes.Uia;

/// <summary>
/// Phase 0 spike B — proves the Windows agent can see what the child is doing:
/// which app is in the foreground, whether the child is actually at the machine,
/// and which URL the browser is showing.
///
/// Run it, then switch between apps and browse; every change is printed with the
/// time the lookup cost, because this loop will run every second forever.
/// </summary>
internal static class Program
{
    private static void Main(string[] args)
    {
        var seconds = args.Length > 0 && int.TryParse(args[0], out var n) ? n : 60;
        Console.WriteLine("=== Spike B: foreground, idle and browser URL via UI Automation ===");
        Console.WriteLine($"Watching for {seconds}s — switch apps and browse to exercise it.");
        Console.WriteLine("Ctrl+C to stop.");
        Console.WriteLine();

        var reader = new BrowserUrlReader();
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        var lastKey = "";
        var samples = 0;
        long totalMs = 0;
        var slowest = 0L;
        var urlsSeen = 0;

        while (DateTime.UtcNow < deadline)
        {
            var sw = Stopwatch.StartNew();
            var hWnd = Native.GetForegroundWindow();
            Native.GetWindowThreadProcessId(hWnd, out var pid);
            var process = SafeProcessName(pid);
            var title = Native.WindowTitle(hWnd);
            var idle = Native.IdleTime();

            var url = "";
            var cacheHit = false;
            if (BrowserUrlReader.IsBrowser(process))
            {
                url = reader.Read(hWnd, process, out cacheHit);
                if (url.Length > 0) urlsSeen++;
            }
            sw.Stop();

            samples++;
            totalMs += sw.ElapsedMilliseconds;
            slowest = Math.Max(slowest, sw.ElapsedMilliseconds);

            var key = $"{process}|{title}|{url}";
            if (key != lastKey)
            {
                lastKey = key;
                Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {process}.exe  ({sw.ElapsedMilliseconds} ms{(cacheHit ? ", cached" : "")})");
                Console.WriteLine($"    title : {Shorten(title)}");
                if (url.Length > 0) Console.WriteLine($"    url   : {Shorten(url)}");
                Console.WriteLine($"    idle  : {idle.TotalSeconds:0}s");
            }

            Thread.Sleep(1000);
        }

        Console.WriteLine();
        Console.WriteLine("=== result ===");
        Console.WriteLine($"  samples         : {samples}");
        Console.WriteLine($"  average lookup  : {(samples == 0 ? 0 : totalMs / samples)} ms");
        Console.WriteLine($"  slowest lookup  : {slowest} ms");
        Console.WriteLine($"  URLs read       : {urlsSeen}");
        Console.WriteLine(urlsSeen > 0
            ? "  browser URL capture: PASS"
            : "  browser URL capture: NOT EXERCISED (no browser was in the foreground)");
    }

    private static string SafeProcessName(uint pid)
    {
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return process.ProcessName;
        }
        catch (ArgumentException)
        {
            return "?";
        }
        catch (InvalidOperationException)
        {
            return "?";
        }
    }

    private static string Shorten(string value) =>
        value.Length <= 110 ? value : value[..110] + "…";
}

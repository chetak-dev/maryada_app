using System.Diagnostics;
using System.IO;
using GuardNest.Core.Ipc;

namespace GuardNest.Agent;

/// <summary>
/// Tells the service what is in front and whether the child is actually there.
/// Screen time is counted from these reports, so it stops when the child walks
/// away rather than counting a window left open all afternoon.
/// </summary>
internal sealed class ForegroundReporter : IAsyncDisposable
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(1);

    /// A chat scan walks a whole window tree, so it runs far less often than the
    /// foreground sample.
    private static readonly TimeSpan ChatInterval = TimeSpan.FromSeconds(3);

    private readonly ServiceLink _link;
    private readonly BrowserUrlReader _urls = new();
    private readonly PageTextReader _pages = new();
    private readonly ChatScanner _chats = new();
    private readonly CancellationTokenSource _cts = new();
    private DateTimeOffset _lastChatScan = DateTimeOffset.MinValue;
    private Task? _loop;

    public ForegroundReporter(ServiceLink link)
    {
        _link = link;
    }

    public void Start() => _loop = Task.Run(() => RunAsync(_cts.Token));

    private async Task RunAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var (window, executable, title) = Foreground();
                if (executable.Length > 0)
                {
                    var url = BrowserUrlReader.IsBrowser(executable)
                        ? _urls.Read(window, executable)
                        : "";
                    var pageText = PageTextFor(window, url);
                    await _link.SendAsync(new IpcMessage
                    {
                        Type = IpcMessage.Foreground,
                        Executable = executable,
                        Title = title,
                        Url = url.Length > 0 ? url : null,
                        PageText = pageText.Length > 0 ? pageText : null,
                        IdleSeconds = (int)Native.IdleTime().TotalSeconds,
                    });
                    await ScanChatsAsync(window, executable, title, url);
                }
            }
            catch (Exception e) when (e is IOException or InvalidOperationException)
            {
            }

            try { await Task.Delay(Interval, ct); }
            catch (OperationCanceledException) { return; }
        }
    }

    /// <summary>
    /// The page's own text, read only when the child is on a real page. An empty
    /// address bar means they are still typing, and a results page is a list of
    /// other people's words rather than anything they chose to open.
    /// </summary>
    private string PageTextFor(IntPtr window, string url)
    {
        if (url.Length == 0) return "";
        var host = Core.Web.Domains.HostOf(url);
        if (host.Length == 0 || Core.Web.WebFilter.IsSearchEngine(host)) return "";
        return _pages.Read(window, url, DateTimeOffset.UtcNow);
    }

    private async Task ScanChatsAsync(IntPtr window, string executable, string title, string url)
    {
        var isChat = ChatScanner.IsChatApp(executable) || ChatScanner.IsChatUrl(url);
        if (!isChat) return;

        var now = DateTimeOffset.UtcNow;
        if (now - _lastChatScan < ChatInterval) return;
        _lastChatScan = now;

        var conversation = ChatScanner.ConversationFrom(title);
        if (conversation is null) return;

        var sightings = _chats.Scan(window, conversation);
        if (sightings.Count == 0) return;

        await _link.SendAsync(new IpcMessage
        {
            Type = IpcMessage.Chat,
            Chats = sightings.ToList(),
        });
    }

    private static (IntPtr Window, string Executable, string Title) Foreground()
    {
        var window = Native.GetForegroundWindow();
        if (window == IntPtr.Zero) return (IntPtr.Zero, "", "");
        Native.GetWindowThreadProcessId(window, out var pid);
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return (window, Core.Apps.InstalledApps.ExecutableKey(process.ProcessName), Native.WindowTitle(window));
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException)
        {
            return (IntPtr.Zero, "", "");
        }
    }

    public async ValueTask DisposeAsync()
    {
        _cts.Cancel();
        if (_loop is not null)
        {
            try { await _loop; } catch (OperationCanceledException) { }
        }
        _cts.Dispose();
    }
}

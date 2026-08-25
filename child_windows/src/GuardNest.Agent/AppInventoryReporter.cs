using GuardNest.Core;
using GuardNest.Core.Apps;
using GuardNest.Core.Ipc;

namespace GuardNest.Agent;

/// <summary>
/// Sends the service what is installed for this child.
/// The protection service runs as LocalSystem in session 0, where the child's
/// registry hive is not loaded and their windows belong to another station, so
/// an inventory taken there sees only machine-wide installs. Almost everything
/// a child actually uses installs per user, so it has to be read here.
/// </summary>
internal sealed class AppInventoryReporter : IAsyncDisposable
{
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(15);

    /// The link is usually still connecting when the agent starts, and a
    /// restarted service comes back with no inventory at all.
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(5);

    private readonly ServiceLink _link;
    private readonly CancellationTokenSource _cts = new();
    private Task? _loop;

    public AppInventoryReporter(ServiceLink link)
    {
        _link = link;
    }

    public void Start() => _loop = Task.Run(() => RunAsync(_cts.Token));

    private async Task RunAsync(CancellationToken ct)
    {
        var sentAt = DateTimeOffset.MinValue;
        var wasConnected = false;

        while (!ct.IsCancellationRequested)
        {
            var connected = _link.Connected;
            // A reconnect means a service that has not been told anything yet.
            var due = connected
                      && (!wasConnected || DateTimeOffset.UtcNow - sentAt >= Interval);
            wasConnected = connected;

            if (due && await SendAsync()) sentAt = DateTimeOffset.UtcNow;

            try { await Task.Delay(PollInterval, ct); }
            catch (OperationCanceledException) { return; }
        }
    }

    private async Task<bool> SendAsync()
    {
        try
        {
            var apps = InstalledApps.Enumerate();
            if (apps.Count == 0) return false;
            await _link.SendAsync(new IpcMessage
            {
                Type = IpcMessage.Apps,
                InstalledApps = apps.ToList(),
            });
            return true;
        }
        catch (Exception e)
        {
            Diag.Warn("agent.apps", e);
            return false;
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

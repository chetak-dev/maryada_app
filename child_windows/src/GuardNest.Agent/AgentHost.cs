using System.Windows;
using GuardNest.Core.Ipc;

namespace GuardNest.Agent;

/// <summary>
/// Owns the agent's windows and its link to the protection service. Split from
/// the entry point so the shared executable can host it alongside the other
/// roles.
/// </summary>
internal sealed class AgentHost
{
    private readonly ServiceLink _link = new();
    private ForegroundReporter? _reporter;
    private AppInventoryReporter? _inventory;
    private MainWindow? _main;
    private OverlayWindow? _overlay;

    public void Start()
    {
        _overlay = new OverlayWindow();
        _main = new MainWindow(_link);

        _overlay.Dismissed += (kind, detail) =>
            _ = _link.SendAsync(new IpcMessage
            {
                Type = IpcMessage.OverlayDismissed,
                OverlayKind = (int)kind,
                Text = detail,
            });

        _link.StateChanged += OnStateChanged;
        _link.ConnectionChanged += connected =>
            Application.Current.Dispatcher.Invoke(() =>
            {
                _main.SetConnected(connected);
                // The service is the only authority on what should be showing.
                // Leaving a full-screen lock up with nothing able to clear it
                // would strand the child.
                if (!connected) _overlay.Apply(new AgentState());
            });

        _reporter = new ForegroundReporter(_link);
        _inventory = new AppInventoryReporter(_link);
        _link.Start();
        _reporter.Start();
        _inventory.Start();
        _main.Show();
    }

    public async Task StopAsync()
    {
        if (_reporter is not null) await _reporter.DisposeAsync();
        if (_inventory is not null) await _inventory.DisposeAsync();
        await _link.DisposeAsync();
    }

    private void OnStateChanged(AgentState state)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            _main?.Apply(state);
            _overlay?.Apply(state);
        });
    }
}

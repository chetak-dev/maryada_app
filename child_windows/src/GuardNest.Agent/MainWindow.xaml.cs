using System.Windows;
using GuardNest.Core;
using GuardNest.Core.Ipc;

namespace GuardNest.Agent;

public partial class MainWindow : Window
{
    private readonly ServiceLink _link;

    public MainWindow(ServiceLink link)
    {
        InitializeComponent();
        _link = link;
        VersionText.Text = AppConfig.VersionLabel;
    }

    public void SetConnected(bool connected)
    {
        if (connected) return;
        StatusText.Text = "Protection service not running";
        DetailText.Text = "Maryada will reconnect on its own.";
    }

    public void Apply(AgentState state)
    {
        StatusText.Text = state.Status.Length > 0 ? state.Status : "Protected";
        if (state.PairingPending)
        {
            DetailText.Text = "Maryada is verifying the saved pairing with the parent app.";
            HeaderSubtitle.Text = "Checking family connection";
        }
        else if (state.Paired)
        {
            DetailText.Text = BuildDetail(state);
            HeaderSubtitle.Text = "Connected to your family";
        }
        else
        {
            DetailText.Text = "This PC is not connected. A parent can finish setup from Maryada Setup.";
            HeaderSubtitle.Text = "Not connected to a parent";
        }
        if (state.VersionLabel.Length > 0) VersionText.Text = state.VersionLabel;
    }

    private static string BuildDetail(AgentState state)
    {
        var name = state.DeviceName.Length > 0 ? state.DeviceName : Environment.MachineName;
        return state.Locked ? state.OverlaySubtitle : $"{name} is protected.";
    }

}

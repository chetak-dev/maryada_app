using System.ComponentModel;
using System.Windows;
using System.Windows.Threading;
using GuardNest.Core.Ipc;

namespace GuardNest.Agent;

/// <summary>
/// The full-screen lock, and the shorter notice shown when a blocked app is
/// closed. One window for both so the child sees one consistent screen.
/// </summary>
public partial class OverlayWindow : Window
{
    private readonly DispatcherTimer _autoHide = new();
    private OverlayKind _kind = OverlayKind.None;
    private bool _allowClose;

    public event Action<OverlayKind, string>? Dismissed;

    public OverlayWindow()
    {
        InitializeComponent();
        _autoHide.Tick += (_, _) => { _autoHide.Stop(); Dismiss(); };
    }

    /// <summary>Shows exactly what the service asked for, or nothing.</summary>
    public void Apply(AgentState state)
    {
        if (state.Overlay == OverlayKind.None)
        {
            Dismiss();
            return;
        }

        // A transient app notice must never replace a screen-time lock.
        if (_kind == OverlayKind.Lock && state.Overlay == OverlayKind.App) return;

        _kind = state.Overlay;
        TitleText.Text = state.OverlayTitle;
        SubtitleText.Text = state.OverlaySubtitle;
        DetailText.Text = state.OverlayDetail;
        DetailBadge.Visibility = state.OverlayDetail.Length > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        ActionButtons.Visibility = state.OverlayDismissible
            ? Visibility.Visible
            : Visibility.Collapsed;
        // Only a browser page can be navigated back; a closed app has nothing
        // to go back to.
        BackButton.Visibility = state.Overlay == OverlayKind.Site
            ? Visibility.Visible
            : Visibility.Collapsed;

        Present();

        _autoHide.Stop();
        if (state.OverlayAutoHideSeconds > 0)
        {
            _autoHide.Interval = TimeSpan.FromSeconds(state.OverlayAutoHideSeconds);
            _autoHide.Start();
        }
    }

    private void Dismiss()
    {
        _autoHide.Stop();
        _kind = OverlayKind.None;
        if (IsVisible) Hide();
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        var kind = _kind;
        var detail = DetailText.Text;
        Hide();
        Desktop.NavigateBack();
        Dismiss();
        Dismissed?.Invoke(kind, detail);
    }

    private void HomeButton_Click(object sender, RoutedEventArgs e)
    {
        var kind = _kind;
        var detail = DetailText.Text;
        Hide();
        Desktop.ShowDesktop();
        Dismiss();
        Dismissed?.Invoke(kind, detail);
    }

    /// <summary>Covers every monitor, so a second screen is not a way around the lock.</summary>
    private void Present()
    {
        if (IsVisible) return;
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;
        WindowState = WindowState.Normal;
        Show();
        Activate();
        Topmost = true;
    }

    protected override void OnDeactivated(EventArgs e)
    {
        base.OnDeactivated(e);
        // Alt+Tab must not park a screen-time lock behind the app it is blocking.
        if (_kind == OverlayKind.Lock && IsVisible) Dispatcher.BeginInvoke(Activate);
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnClosing(e);
    }

    public void AllowClose() => _allowClose = true;
}

using System.ComponentModel;
using System.Windows;
using System.Windows.Media;

namespace GuardNest.Setup;

public partial class MainWindow : Window
{
    private readonly InstallationEngine _engine;
    private readonly bool _uninstallRequested;
    private bool _busy;
    private bool _finished;
    private bool _pendingUnpairedInstall;
    private bool _allowClose;
    private bool _cleanupPromptOpen;

    /// Which operation the retry button should repeat.
    private bool _lastWasRemoval;

    public MainWindow(InstallationEngine engine, bool uninstallRequested)
    {
        InitializeComponent();
        _engine = engine;
        _uninstallRequested = uninstallRequested;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        RefreshReadyState();
        if (_uninstallRequested) await RunUninstallAsync();
    }

    private void RefreshReadyState()
    {
        var link = _engine.CurrentLink;
        PairingCard.Visibility = link.IsLinked ? Visibility.Collapsed : Visibility.Visible;
        if (!_engine.IsInstalled)
        {
            PrimaryButton.Content = "Install and connect";
            return;
        }

        HeadingText.Text = link.IsLinked
            ? "Maryada is installed and linked"
            : "Finish setting up Maryada";
        DescriptionText.Text = link.IsLinked
            ? (link.FamilyName.Length > 0
                ? $"This PC is connected to {link.FamilyName}. Remove it in the parent app before uninstalling."
                : "This PC is connected to a parent. Remove it in the parent app before uninstalling.")
            : "Enter a pairing code below. Setup remains incomplete until the parent connection succeeds.";
        PrimaryButton.Content = link.IsLinked ? "Repair protection" : "Connect and finish";
        RemoveButton.Visibility = Visibility.Visible;
        HeroText.Text = link.IsLinked
            ? "Connected to a parent"
            : "Not connected to a parent";
    }

    private async void PrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_finished)
        {
            _allowClose = true;
            Close();
            return;
        }
        // Retrying a blocked removal must re-check the parent link, not start
        // an installation the PC already has.
        if (_lastWasRemoval)
        {
            await RunUninstallAsync();
            return;
        }
        await RunInstallAsync();
    }

    private async void RemoveButton_Click(object sender, RoutedEventArgs e)
    {
        var answer = MessageBox.Show(
            "Maryada can only be removed after this PC is removed in the parent app. Continue?",
            "Remove Maryada",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (answer == MessageBoxResult.Yes) await RunUninstallAsync();
    }

    private async Task RunInstallAsync()
    {
        var link = _engine.CurrentLink;
        var code = CodeBox.Text.Trim();
        if (!link.IsLinked && code.Length < 6)
        {
            PairMessage.Text = "Enter the 6-character pairing code from the parent app.";
            CodeBox.Focus();
            return;
        }

        PairMessage.Text = "";
        _lastWasRemoval = false;
        if (!link.IsLinked)
        {
            SetPreflightBusy(true);
            PairMessage.Foreground = new SolidColorBrush(Color.FromRgb(79, 70, 229));
            PairMessage.Text = "Checking pairing code…";
            var validation = await PairingPreflight.ValidateAsync(code);
            SetPreflightBusy(false);
            if (!validation.Ok)
            {
                PairMessage.Foreground = new SolidColorBrush(Color.FromRgb(220, 38, 38));
                PairMessage.Text = validation.Message;
                CodeBox.SelectAll();
                CodeBox.Focus();
                return;
            }
        }

        BeginOperation("Installing Maryada");
        var progress = new Progress<SetupProgress>(UpdateProgress);
        var result = link.IsLinked
            ? await _engine.InstallAsync(progress)
            : await _engine.InstallAndPairAsync(code, progress);
        if (result.PairingRequired)
        {
            ShowPairingRetry(result.Message);
            return;
        }
        ShowResult(result);
    }

    private void SetPreflightBusy(bool busy)
    {
        _busy = busy;
        CodeBox.IsEnabled = !busy;
        PrimaryButton.IsEnabled = !busy;
        CloseButton.IsEnabled = !busy;
        RemoveButton.IsEnabled = !busy;
    }

    private async Task RunUninstallAsync()
    {
        _lastWasRemoval = true;
        BeginOperation("Removing Maryada");
        UpdateProgress(new SetupProgress("Checking with the parent app…", 5));
        var result = await _engine.UninstallAsync(new Progress<SetupProgress>(UpdateProgress));
        ShowResult(result);
    }

    private void ShowPairingRetry(string message)
    {
        _busy = false;
        _pendingUnpairedInstall = true;
        ProgressPanel.Visibility = Visibility.Collapsed;
        ResultPanel.Visibility = Visibility.Collapsed;
        ReadyPanel.Visibility = Visibility.Visible;
        PairingCard.Visibility = Visibility.Visible;
        PairMessage.Text = message;
        HeadingText.Text = "Pairing is required to finish";
        DescriptionText.Text =
            "Maryada is installed provisionally. Enter a valid code and try again, or cancel setup to remove the incomplete installation.";
        HeroText.Text = "Waiting for parent pairing";
        PrimaryButton.Content = "Try pairing again";
        PrimaryButton.IsEnabled = true;
        RemoveButton.Visibility = Visibility.Collapsed;
        CloseButton.Content = "Cancel setup";
        CloseButton.IsEnabled = true;
        CloseButton.Visibility = Visibility.Visible;
        CodeBox.SelectAll();
        CodeBox.Focus();
    }

    private void BeginOperation(string heading)
    {
        _busy = true;
        ReadyPanel.Visibility = Visibility.Collapsed;
        ResultPanel.Visibility = Visibility.Collapsed;
        ProgressPanel.Visibility = Visibility.Visible;
        ProgressHeading.Text = heading;
        ProgressBar.Value = 0;
        PrimaryButton.IsEnabled = false;
        RemoveButton.IsEnabled = false;
        CloseButton.IsEnabled = false;
    }

    private void UpdateProgress(SetupProgress progress)
    {
        StatusText.Text = progress.Status;
        ProgressBar.Value = progress.Percent;
    }

    private void ShowResult(SetupResult result)
    {
        _busy = false;
        _finished = result.Success;
        ProgressPanel.Visibility = Visibility.Collapsed;
        ResultPanel.Visibility = Visibility.Visible;
        ResultHeading.Text = result.Title;
        ResultMessage.Text = result.Message;
        ResultBadge.Background = new SolidColorBrush(result.Success
            ? Color.FromRgb(220, 252, 231)
            : Color.FromRgb(254, 226, 226));
        ResultMark.Text = result.Success ? "✓" : "!";
        ResultMark.Foreground = new SolidColorBrush(result.Success
            ? Color.FromRgb(21, 128, 61)
            : Color.FromRgb(185, 28, 28));
        PrimaryButton.Content = result.Success
            ? "Close"
            : _lastWasRemoval ? "Check again" : "Try again";
        PrimaryButton.IsEnabled = true;
        CloseButton.IsEnabled = true;
        CloseButton.Content = "Close";
        // A completed wizard gets one exit action, not two Close buttons.
        CloseButton.Visibility = result.Success ? Visibility.Collapsed : Visibility.Visible;
        RemoveButton.Visibility = Visibility.Collapsed;
        if (result.Success)
        {
            _pendingUnpairedInstall = false;
        }
    }

    private async void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        if (_pendingUnpairedInstall && !_engine.CurrentLink.IsLinked)
        {
            await CancelIncompleteSetupAsync();
            return;
        }
        _allowClose = true;
        Close();
    }

    private async Task CancelIncompleteSetupAsync()
    {
        if (_cleanupPromptOpen) return;
        _cleanupPromptOpen = true;
        try
        {
            var answer = MessageBox.Show(
                "Pairing has not finished. Cancel setup and remove the incomplete Maryada installation?",
                "Cancel Maryada setup",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (answer != MessageBoxResult.Yes) return;

            BeginOperation("Cancelling setup");
            var result = await _engine.UninstallAsync(new Progress<SetupProgress>(UpdateProgress));
            if (result.Success)
            {
                _pendingUnpairedInstall = false;
                _allowClose = true;
                Close();
                return;
            }
            ShowResult(result);
        }
        finally
        {
            _cleanupPromptOpen = false;
        }
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (_allowClose)
        {
            base.OnClosing(e);
            return;
        }
        if (_busy)
        {
            e.Cancel = true;
            return;
        }
        if (_pendingUnpairedInstall && !_engine.CurrentLink.IsLinked)
        {
            e.Cancel = true;
            Dispatcher.BeginInvoke(async () => await CancelIncompleteSetupAsync());
            return;
        }
        base.OnClosing(e);
    }
}
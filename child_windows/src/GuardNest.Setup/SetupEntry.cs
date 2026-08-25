using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

namespace GuardNest.Setup;

/// <summary>The install wizard, hosted by the shared Maryada executable.</summary>
public static class SetupEntry
{
    public static int Run(string[] args)
    {
        var uninstall = args.Contains("--uninstall", StringComparer.OrdinalIgnoreCase);
        var quiet = args.Contains("--quiet", StringComparer.OrdinalIgnoreCase);

        // The shared executable also runs as the child's agent, so it cannot
        // demand administrator rights in its manifest; the wizard asks for them
        // only when it is the one running.
        if (!IsAdministrator())
        {
            return Elevate(args, quiet);
        }

        var app = new Application();
        app.Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new Uri(
                "pack://application:,,,/GuardNest.Setup;component/SetupTheme.xaml",
                UriKind.Absolute),
        });

        var engine = new InstallationEngine();
        if (quiet)
        {
            var result = uninstall
                ? engine.UninstallAsync(progress: null).GetAwaiter().GetResult()
                : engine.InstallAsync(progress: null).GetAwaiter().GetResult();
            return result.Success ? 0 : 1;
        }

        var window = new MainWindow(engine, uninstall);
        window.Show();
        return app.Run();
    }

    private static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static int Elevate(string[] args, bool quiet)
    {
        var executable = Environment.ProcessPath;
        if (executable is null) return 1;

        var startInfo = new ProcessStartInfo(executable)
        {
            UseShellExecute = true,
            Verb = "runas",
        };
        foreach (var argument in args) startInfo.ArgumentList.Add(argument);

        try
        {
            using var elevated = Process.Start(startInfo);
            if (elevated is null) return 1;
            if (!quiet) return 0;
            elevated.WaitForExit();
            return elevated.ExitCode;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // The administrator prompt was declined.
            if (!quiet)
            {
                MessageBox.Show(
                    "Maryada needs administrator approval to change protection on this PC.",
                    "Maryada Setup",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
            return 1;
        }
    }
}

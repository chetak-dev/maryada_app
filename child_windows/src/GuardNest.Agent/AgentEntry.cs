using System.Threading;
using System.Windows;
using GuardNest.Core.Ipc;

namespace GuardNest.Agent;

/// <summary>The child-facing agent, hosted by the shared Maryada executable.</summary>
public static class AgentEntry
{
    public static int Run(string[] args)
    {
        if (args.Contains("--dump-uia", StringComparer.OrdinalIgnoreCase))
        {
            UiaDump.Run(
                delaySeconds: 8,
                path: System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "uia-tree.txt"));
            return 0;
        }

        var previewIndex = Array.FindIndex(
            args,
            value => value.Equals("--preview-overlay", StringComparison.OrdinalIgnoreCase));
        if (previewIndex >= 0)
        {
            // Checked before the mutex: previewing a block screen must work
            // while the real agent is running.
            var preview = CreateApplication();
            ShowPreview(args, previewIndex);
            return preview.Run();
        }

        // One agent per session: a second copy would double-count screen time.
        using var single = new Mutex(true, @"Local\GuardNest.Agent", out var created);
        if (!created) return 0;

        var app = CreateApplication();
        var host = new AgentHost();
        host.Start();
        // Closing the window must not end monitoring; the service would only
        // have to start the agent again.
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        app.Exit += async (_, _) => await host.StopAsync();
        return app.Run();
    }

    private static Application CreateApplication()
    {
        var app = new Application();
        app.Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new Uri(
                "pack://application:,,,/GuardNest.Agent;component/AgentTheme.xaml",
                UriKind.Absolute),
        });
        return app;
    }

    private static void ShowPreview(string[] args, int previewIndex)
    {
        var kind = previewIndex + 1 < args.Length
            && args[previewIndex + 1].Equals("app", StringComparison.OrdinalIgnoreCase)
            ? OverlayKind.App
            : OverlayKind.Site;
        new OverlayWindow().Apply(new AgentState
        {
            Overlay = kind,
            OverlayTitle = kind == OverlayKind.App ? "App blocked" : "Site blocked",
            OverlaySubtitle = kind == OverlayKind.App
                ? "Your parent does not allow this app."
                : "This page was blocked by your family's filter.",
            OverlayDetail = kind == OverlayKind.App ? "Example Game" : "blocked.example",
            OverlayDismissible = true,
        });
    }
}

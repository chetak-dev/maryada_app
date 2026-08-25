using System.Runtime.InteropServices;

namespace GuardNest.App;

/// <summary>
/// One executable, three roles. Shipping the setup, the protection service and
/// the child agent as separate self-contained programs meant three copies of
/// the .NET runtime; sharing one binary is what keeps the download small.
/// </summary>
public static class Program
{
    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int processId);

    [STAThread]
    public static int Main(string[] args)
    {
        if (Has(args, "--service"))
        {
            Service.ServiceEntry.RunAsync(args).GetAwaiter().GetResult();
            return 0;
        }

        if (Has(args, "--agent") || Has(args, "--dump-uia") || Has(args, "--preview-overlay"))
        {
            return Agent.AgentEntry.Run(args);
        }

        // Anything else is a person running the file: install, repair or remove.
        if (Has(args, "--quiet")) AttachConsole(-1);
        return Setup.SetupEntry.Run(args);
    }

    private static bool Has(string[] args, string flag) =>
        args.Contains(flag, StringComparer.OrdinalIgnoreCase);
}

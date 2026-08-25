using System.ComponentModel;
using System.Diagnostics;
using GuardNest.Core.Rules;

namespace GuardNest.Core.Apps;

/// <summary>
/// Enforces the parent's app rules by ending blocked programs. On Home editions
/// there is no AppLocker to refuse the launch, so the app starts and is closed
/// again; the agent shows the child why.
/// </summary>
public static class AppBlocker
{
    /// <summary>Ends every running instance of a blocked app; returns what it stopped.</summary>
    public static IReadOnlyList<string> Enforce(AppRules rules)
    {
        if (rules.Blocked.Count == 0) return Array.Empty<string>();

        var stopped = new List<string>();
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                var key = InstalledApps.ExecutableKey(process.ProcessName);
                if (ProcessGuard.IsProtected(key) || !rules.IsBlocked(key)) continue;

                process.Kill(entireProcessTree: true);
                if (!stopped.Contains(key)) stopped.Add(key);
            }
            catch (Exception e) when (e is InvalidOperationException or Win32Exception or NotSupportedException)
            {
                // Already gone, or owned by a session we may not touch.
            }
            finally
            {
                process.Dispose();
            }
        }
        return stopped;
    }
}

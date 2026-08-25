using Microsoft.Win32;

namespace GuardNest.Core.Apps;

/// <summary>One app the parent can write a rule for.</summary>
public sealed record InstalledApp(string Key, string Name);

/// <summary>
/// The apps this PC can actually enforce a rule against. Rules are keyed by
/// executable name (`chrome.exe`), which is both stable and the thing the
/// blocker matches — an app whose executable cannot be resolved is left out
/// rather than shown to the parent as a switch that would do nothing.
/// </summary>
public static class InstalledApps
{
    private static readonly IReadOnlySet<string> InventoryExcluded =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "applicationframehost.exe", "systemsettings.exe", "textinputhost.exe",
            "setup.exe", "uninstall.exe", "onedrivesetup.exe", "oktaverifysetup.exe",
            "officeclicktorun.exe", "azinfoprotection.exe",
            "maryada.exe", "maryada.setup.exe", "guardnest.service.exe", "guardnest.agent.exe",
        };

    private static readonly string[] UninstallKeys =
    {
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    };

    public static IReadOnlyList<InstalledApp> Enumerate()
    {
        var apps = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var path in UninstallKeys)
        {
            Collect(Registry.LocalMachine, path, apps);
            Collect(Registry.CurrentUser, path, apps);
        }
        CollectRunning(apps);

        return apps
            .Select(entry => new InstalledApp(entry.Key, entry.Value))
            .OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    private static void Collect(RegistryKey hive, string path, Dictionary<string, string> apps)
    {
        try
        {
            using var root = hive.OpenSubKey(path);
            if (root is null) return;
            foreach (var name in root.GetSubKeyNames())
            {
                using var entry = root.OpenSubKey(name);
                if (entry is null) continue;

                var display = entry.GetValue("DisplayName")?.ToString()?.Trim();
                if (string.IsNullOrEmpty(display)) continue;
                // Patches and driver packages are not apps a child opens.
                if (entry.GetValue("SystemComponent") is int and 1) continue;
                if (entry.GetValue("ParentKeyName") is not null) continue;
                if (LooksLikeMaintenancePackage(display, entry)) continue;

                var executable = ResolveExecutable(entry);
                if (executable is null) continue;
                if (InventoryExcluded.Contains(executable)) continue;
                apps.TryAdd(executable, display);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            Diag.Warn("installedApps.registry", e);
        }
    }

    /// <summary>
    /// Catches Store apps and portable executables, which have no uninstall
    /// entry but are exactly the kind of thing a child runs.
    /// </summary>
    private static void CollectRunning(Dictionary<string, string> apps)
    {
        foreach (var process in System.Diagnostics.Process.GetProcesses())
        {
            try
            {
                if (process.MainWindowHandle == IntPtr.Zero) continue;
                var key = ExecutableKey(process.ProcessName);
                if (ProcessGuard.IsProtected(key)) continue;
                if (InventoryExcluded.Contains(key)) continue;
                var title = process.MainWindowTitle.Trim();
                apps.TryAdd(key, title.Length > 0 ? Friendly(process.ProcessName) : Friendly(process.ProcessName));
            }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                // The process exited while we were reading it.
            }
            finally
            {
                process.Dispose();
            }
        }
    }

    private static string? ResolveExecutable(RegistryKey entry)
    {
        var icon = entry.GetValue("DisplayIcon")?.ToString();
        if (!string.IsNullOrWhiteSpace(icon))
        {
            // "C:\path\app.exe,0" — the index after the comma is not part of it.
            var comma = icon.LastIndexOf(',');
            var candidate = comma > 2 ? icon[..comma] : icon;
            candidate = candidate.Trim('"', ' ');
            if (candidate.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                return ExecutableKey(Path.GetFileName(candidate));
            }
        }

        var location = entry.GetValue("InstallLocation")?.ToString()?.Trim('"', ' ');
        if (string.IsNullOrWhiteSpace(location) || !Directory.Exists(location)) return null;
        try
        {
            var executables = Directory.EnumerateFiles(location, "*.exe", SearchOption.TopDirectoryOnly)
                .Where(file => !ProcessGuard.IsProtected(ExecutableKey(Path.GetFileName(file))))
                .Take(2)
                .ToList();
            // More than one candidate means we would be guessing which one the
            // rule should target, and a wrong guess blocks the wrong program.
            return executables.Count == 1 ? ExecutableKey(Path.GetFileName(executables[0])) : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>Normalises any spelling of an executable to the rule key form.</summary>
    public static string ExecutableKey(string nameOrPath)
    {
        var file = Path.GetFileName(nameOrPath).Trim();
        if (!file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) file += ".exe";
        return file.ToLowerInvariant();
    }

    private static string Friendly(string processName) =>
        processName.Length <= 1 ? processName : char.ToUpperInvariant(processName[0]) + processName[1..];

    private static bool LooksLikeMaintenancePackage(string displayName, RegistryKey entry)
    {
        var uninstall = entry.GetValue("UninstallString")?.ToString() ?? "";
        var lower = displayName.ToLowerInvariant();
        return lower.Contains("redistributable")
               || lower.Contains("runtime")
               || lower.Contains("sdk")
               || lower.Contains("update")
               || lower.Contains("maintenance service")
               || lower.Contains("sensor")
               || lower.Contains("web extension")
               || lower == "maryada"
               || uninstall.Contains("msiexec", StringComparison.OrdinalIgnoreCase)
                  && string.IsNullOrWhiteSpace(entry.GetValue("DisplayIcon")?.ToString());
    }
}

namespace GuardNest.Core.Apps;

/// <summary>
/// Executables that must never be terminated, whatever a rule says. Blocking
/// any of these would take the desktop, the sign-in path or the agent itself
/// down with the app — a parental control that can brick the PC is worse than
/// no control.
/// </summary>
public static class ProcessGuard
{
    private static readonly HashSet<string> Protected = new(StringComparer.OrdinalIgnoreCase)
    {
        // Windows itself.
        "system.exe", "smss.exe", "csrss.exe", "wininit.exe", "winlogon.exe",
        "services.exe", "lsass.exe", "svchost.exe", "fontdrvhost.exe", "dwm.exe",
        "explorer.exe", "sihost.exe", "taskhostw.exe", "ctfmon.exe", "runtimebroker.exe",
        "shellexperiencehost.exe", "startmenuexperiencehost.exe", "searchhost.exe",
        "logonui.exe", "userinit.exe", "dllhost.exe", "conhost.exe", "audiodg.exe",
        "wudfhost.exe", "spoolsv.exe", "lsaiso.exe", "memcompression.exe",
        // Accessibility tools a child may genuinely need.
        "narrator.exe", "magnify.exe", "osk.exe",
        // Ourselves.
        "maryada.exe", "guardnest.service.exe", "guardnest.agent.exe",
    };

    public static bool IsProtected(string executableKey) => Protected.Contains(executableKey);
}

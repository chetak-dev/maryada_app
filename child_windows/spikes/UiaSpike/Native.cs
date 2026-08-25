using System.Runtime.InteropServices;
using System.Text;

namespace GuardNest.Windows.Spikes.Uia;

/// <summary>
/// Foreground-window and idle tracking — the Windows stand-in for Android's
/// UsageStats event pairing. Screen time must not count a window that is merely
/// on top while the child is away, so foreground time is gated on real input.
/// </summary>
internal static class Native
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLastInputInfo(ref LastInputInfo info);

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo
    {
        public uint cbSize;
        public uint dwTime;
    }

    public static string WindowTitle(IntPtr hWnd)
    {
        var buffer = new StringBuilder(512);
        var length = GetWindowTextW(hWnd, buffer, buffer.Capacity);
        return length > 0 ? buffer.ToString() : "";
    }

    public static TimeSpan IdleTime()
    {
        var info = new LastInputInfo { cbSize = (uint)Marshal.SizeOf<LastInputInfo>() };
        if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;
        // Both are 32-bit tick counts, so unchecked subtraction survives the
        // 49-day wrap that would otherwise report a machine as idle for weeks.
        var elapsed = unchecked((uint)Environment.TickCount - info.dwTime);
        return TimeSpan.FromMilliseconds(elapsed);
    }
}

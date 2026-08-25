using System.Runtime.InteropServices;
using System.Text;

namespace GuardNest.Agent;

/// <summary>
/// Foreground and idle facts, which only exist inside an interactive session —
/// this is why the agent has to be a separate process from the service.
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
        return GetWindowTextW(hWnd, buffer, buffer.Capacity) > 0 ? buffer.ToString() : "";
    }

    public static TimeSpan IdleTime()
    {
        var info = new LastInputInfo { cbSize = (uint)Marshal.SizeOf<LastInputInfo>() };
        if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;
        // Unchecked subtraction of two 32-bit tick counts survives the 49-day
        // wrap that would otherwise report the machine as idle for weeks.
        return TimeSpan.FromMilliseconds(unchecked((uint)Environment.TickCount - info.dwTime));
    }
}

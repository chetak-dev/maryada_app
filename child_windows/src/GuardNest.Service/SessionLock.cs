using System.Runtime.InteropServices;

namespace GuardNest.Service;

/// <summary>
/// Signs the child out when the screen-time lock is in force but no agent is
/// there to show it. Without this, closing the agent would turn bedtime off.
/// </summary>
internal static class SessionLock
{
    private const int WtsActive = 0;

    /// Long enough that a child signing back in is not fighting a loop, short
    /// enough that they cannot get a usable session out of it.
    private static readonly TimeSpan Cooldown = TimeSpan.FromSeconds(30);

    private static DateTimeOffset _lastDisconnect = DateTimeOffset.MinValue;

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSEnumerateSessions(
        IntPtr server, int reserved, int version, out IntPtr sessions, out int count);

    [DllImport("wtsapi32.dll")]
    private static extern void WTSFreeMemory(IntPtr memory);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSDisconnectSession(IntPtr server, int sessionId, bool wait);

    [StructLayout(LayoutKind.Sequential)]
    private struct SessionInfo
    {
        public int SessionId;
        public IntPtr WinStationName;
        public int State;
    }

    /// <summary>Disconnects every signed-in session; returns how many it closed.</summary>
    public static int DisconnectActive()
    {
        var now = DateTimeOffset.UtcNow;
        if (now - _lastDisconnect < Cooldown) return 0;
        _lastDisconnect = now;

        if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out var buffer, out var count)) return 0;

        var closed = 0;
        try
        {
            var size = Marshal.SizeOf<SessionInfo>();
            for (var index = 0; index < count; index++)
            {
                var entry = Marshal.PtrToStructure<SessionInfo>(buffer + index * size);
                // Session 0 is the service's own; disconnecting it does nothing
                // useful and there is never a child signed into it.
                if (entry.State != WtsActive || entry.SessionId == 0) continue;
                if (WTSDisconnectSession(IntPtr.Zero, entry.SessionId, true)) closed++;
            }
        }
        finally
        {
            WTSFreeMemory(buffer);
        }
        return closed;
    }
}

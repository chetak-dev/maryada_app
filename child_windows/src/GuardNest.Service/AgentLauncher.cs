using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Win32.SafeHandles;

namespace GuardNest.Service;

/// <summary>Starts the per-user agent from the LocalSystem service.</summary>
public sealed class AgentLauncher
{
    private const uint InvalidSession = 0xFFFFFFFF;
    private const uint TokenAllAccess = 0xF01FF;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const int SecurityImpersonation = 2;
    private const int TokenPrimary = 1;

    private readonly ILogger<AgentLauncher> _log;

    public AgentLauncher(ILogger<AgentLauncher> log)
    {
        _log = log;
    }

    public int ActiveSessionId
    {
        get
        {
            var id = WTSGetActiveConsoleSessionId();
            return id == InvalidSession ? -1 : (int)id;
        }
    }

    public void EnsureRunning()
    {
        var sessionId = WTSGetActiveConsoleSessionId();
        if (sessionId == InvalidSession || AgentAlreadyRunsIn(sessionId)) return;

        var agent = Environment.ProcessPath;
        if (agent is null || !File.Exists(agent)) return;

        if (!WTSQueryUserToken(sessionId, out var userToken)) return;
        using (userToken)
        {
            if (!DuplicateTokenEx(
                    userToken,
                    TokenAllAccess,
                    IntPtr.Zero,
                    SecurityImpersonation,
                    TokenPrimary,
                    out var primaryToken))
            {
                return;
            }

            using (primaryToken)
            {
                CreateEnvironmentBlock(out var environment, primaryToken, false);
                try
                {
                    var startup = new StartupInfo
                    {
                        Size = Marshal.SizeOf<StartupInfo>(),
                        Desktop = @"winsta0\default",
                    };
                    var command = new StringBuilder($"\"{agent}\" --agent");
                    if (!CreateProcessAsUser(
                            primaryToken,
                            null,
                            command,
                            IntPtr.Zero,
                            IntPtr.Zero,
                            false,
                            CreateUnicodeEnvironment,
                            environment,
                            AppContext.BaseDirectory,
                            ref startup,
                            out var processInfo))
                    {
                        _log.LogWarning(
                            "Could not start the session agent: {Error}",
                            new Win32Exception(Marshal.GetLastWin32Error()).Message);
                        return;
                    }

                    CloseHandle(processInfo.Process);
                    CloseHandle(processInfo.Thread);
                    _log.LogInformation("Started the agent in session {SessionId}", sessionId);
                }
                finally
                {
                    if (environment != IntPtr.Zero) DestroyEnvironmentBlock(environment);
                }
            }
        }
    }

    public bool AgentRunsInActiveSession()
    {
        var sessionId = WTSGetActiveConsoleSessionId();
        return sessionId != InvalidSession && AgentAlreadyRunsIn(sessionId);
    }

    private static bool AgentAlreadyRunsIn(uint sessionId)
    {
        foreach (var name in new[] { "Maryada", "GuardNest.Agent" })
        {
            foreach (var process in Process.GetProcessesByName(name))
            {
                using (process)
                {
                    try
                    {
                        // The service itself runs from the same program, so only
                        // a copy in the interactive session counts.
                        if (process.SessionId == sessionId) return true;
                    }
                    catch (InvalidOperationException) { }
                }
            }
        }
        return false;
    }

    [DllImport("kernel32.dll")]
    private static extern uint WTSGetActiveConsoleSessionId();

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSQueryUserToken(uint sessionId, out SafeAccessTokenHandle token);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool DuplicateTokenEx(
        SafeAccessTokenHandle existingToken,
        uint desiredAccess,
        IntPtr tokenAttributes,
        int impersonationLevel,
        int tokenType,
        out SafeAccessTokenHandle newToken);

    [DllImport("userenv.dll", SetLastError = true)]
    private static extern bool CreateEnvironmentBlock(
        out IntPtr environment,
        SafeAccessTokenHandle token,
        bool inherit);

    [DllImport("userenv.dll")]
    private static extern bool DestroyEnvironmentBlock(IntPtr environment);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessAsUser(
        SafeAccessTokenHandle token,
        string? applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        bool inheritHandles,
        uint creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref StartupInfo startupInfo,
        out ProcessInformation processInformation);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int Size;
        public string? Reserved;
        public string? Desktop;
        public string? Title;
        public int X;
        public int Y;
        public int XSize;
        public int YSize;
        public int XCountChars;
        public int YCountChars;
        public int FillAttribute;
        public int Flags;
        public short ShowWindow;
        public short Reserved2;
        public IntPtr Reserved2Pointer;
        public IntPtr StandardInput;
        public IntPtr StandardOutput;
        public IntPtr StandardError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public IntPtr Process;
        public IntPtr Thread;
        public int ProcessId;
        public int ThreadId;
    }
}
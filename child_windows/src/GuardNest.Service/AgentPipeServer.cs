using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using GuardNest.Core;
using GuardNest.Core.Ipc;
using Microsoft.Extensions.Logging;

namespace GuardNest.Service;

/// <summary>
/// The service's end of the pipe. The service runs in session 0 and cannot draw
/// anything, so the interactive agent is its eyes (which window is in front) and
/// its face (the lock screen and pairing UI).
/// </summary>
public sealed class AgentPipeServer : IAsyncDisposable
{
    private readonly ILogger<AgentPipeServer> _log;
    private readonly List<Session> _sessions = new();
    private readonly object _gate = new();
    private CancellationTokenSource? _cts;
    private Task? _acceptLoop;

    public AgentPipeServer(ILogger<AgentPipeServer> log)
    {
        _log = log;
    }

    /// <summary>Handles a pairing code typed into the agent. Returns the result to show.</summary>
    public Func<string, CancellationToken, Task<(bool Ok, string Message)>>? PairRequested { get; set; }

    /// <summary>Reports the foreground window and, for a browser, the page in it.</summary>
    public Action<ForegroundReport>? ForegroundReported { get; set; }

    /// <summary>Reports one pass over an open conversation.</summary>
    public Action<IReadOnlyList<Core.Chat.ChatSighting>>? ChatsReported { get; set; }

    /// <summary>Reports what is installed for the child whose session the agent runs in.</summary>
    public Action<IReadOnlyList<Core.Apps.InstalledApp>>? AppsReported { get; set; }

    public Action<OverlayKind, string>? OverlayDismissed { get; set; }

    public bool AgentConnected
    {
        get { lock (_gate) return _sessions.Count > 0; }
    }

    public bool AgentConnectedInSession(int sessionId)
    {
        lock (_gate) return _sessions.Any(session => session.SessionId == sessionId);
    }

    public void Start(CancellationToken ct)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_cts.Token), CancellationToken.None);
    }

    public async Task BroadcastAsync(AgentState state, CancellationToken ct)
    {
        List<Session> sessions;
        lock (_gate) sessions = _sessions.ToList();

        var message = new IpcMessage { Type = IpcMessage.State, Payload = state };
        foreach (var session in sessions)
        {
            try
            {
                await session.SendAsync(message, ct);
            }
            catch (Exception e) when (e is IOException or ObjectDisposedException)
            {
                Remove(session);
            }
        }
    }

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            NamedPipeServerStream? pipe = null;
            try
            {
                pipe = CreatePipe();
                await pipe.WaitForConnectionAsync(ct);
                var session = new Session(pipe);
                lock (_gate) _sessions.Add(session);
                _ = Task.Run(() => ServeAsync(session, ct), CancellationToken.None);
            }
            catch (OperationCanceledException)
            {
                pipe?.Dispose();
                return;
            }
            catch (Exception e)
            {
                // This loop is fire-and-forget: letting anything escape would
                // leave the agent permanently unable to reconnect, with no
                // visible failure anywhere.
                pipe?.Dispose();
                _log.LogError(e, "Pipe accept failed");
                Diag.Warn("pipe.accept", e);
                try { await Task.Delay(TimeSpan.FromSeconds(2), ct); }
                catch (OperationCanceledException) { return; }
            }
        }
    }

    private async Task ServeAsync(Session session, CancellationToken ct)
    {
        using var reader = new StreamReader(session.Stream, Encoding.UTF8, leaveOpen: true);
        try
        {
            while (!ct.IsCancellationRequested && session.Stream.IsConnected)
            {
                var message = await PipeProtocol.ReadAsync(reader, ct);
                if (message is null) break;
                await HandleAsync(session, message, ct);
            }
        }
        catch (Exception e) when (e is IOException or ObjectDisposedException or OperationCanceledException)
        {
        }
        catch (Exception e)
        {
            // This runs detached from the accept loop, so an unexpected failure
            // would otherwise drop the agent with nothing recorded anywhere.
            _log.LogError(e, "Agent session failed");
            Diag.Warn("pipe.session", e);
        }
        finally
        {
            Remove(session);
        }
    }

    private async Task HandleAsync(Session session, IpcMessage message, CancellationToken ct)
    {
        switch (message.Type)
        {
            case IpcMessage.Hello:
                session.SessionId = message.SessionId;
                _log.LogInformation("Agent connected for {User}", message.Text);
                break;

            case IpcMessage.Foreground:
                ForegroundReported?.Invoke(new ForegroundReport(
                    message.Executable ?? "",
                    message.Title ?? "",
                    message.Url ?? "",
                    message.PageText ?? "",
                    message.IdleSeconds));
                break;

            case IpcMessage.Chat:
                if (message.Chats is { Count: > 0 }) ChatsReported?.Invoke(message.Chats);
                break;

            case IpcMessage.Apps:
                if (message.InstalledApps is { Count: > 0 }) AppsReported?.Invoke(message.InstalledApps);
                break;

            case IpcMessage.OverlayDismissed:
                if (Enum.IsDefined(typeof(OverlayKind), message.OverlayKind))
                {
                    OverlayDismissed?.Invoke((OverlayKind)message.OverlayKind, message.Text ?? "");
                }
                break;

            case IpcMessage.Pair:
                var handler = PairRequested;
                var result = handler is null
                    ? (false, "Pairing is not available right now.")
                    : await handler(message.Text ?? "", ct);
                await session.SendAsync(new IpcMessage
                {
                    Type = IpcMessage.PairResult,
                    Ok = result.Item1,
                    Text = result.Item2,
                }, ct);
                break;
        }
    }

    /// <summary>
    /// SYSTEM owns the pipe; the child's interactive session only needs to
    /// connect and talk, never to create a server instance of the same name —
    /// that would let a standard user impersonate the service to the agent.
    /// </summary>
    private static NamedPipeServerStream CreatePipe()
    {
        var security = new PipeSecurity();
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
            PipeAccessRights.ReadWrite,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            PipeAccessRights.FullControl,
            AccessControlType.Allow));

        // Every instance after the first needs CreateNewInstance on the existing
        // pipe, which ReadWrite does not include — without this the accept loop
        // serves exactly one client and then dies.
        using var identity = WindowsIdentity.GetCurrent();
        if (identity.User is { } account)
        {
            security.AddAccessRule(new PipeAccessRule(
                account, PipeAccessRights.FullControl, AccessControlType.Allow));
        }

        return NamedPipeServerStreamAcl.Create(
            AppConfig.PipeName,
            PipeDirection.InOut,
            NamedPipeServerStream.MaxAllowedServerInstances,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous,
            inBufferSize: 0,
            outBufferSize: 0,
            security);
    }

    private void Remove(Session session)
    {
        lock (_gate) _sessions.Remove(session);
        session.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        _cts?.Cancel();
        if (_acceptLoop is not null)
        {
            try { await _acceptLoop; } catch (OperationCanceledException) { }
        }
        lock (_gate)
        {
            foreach (var session in _sessions) session.Dispose();
            _sessions.Clear();
        }
        _cts?.Dispose();
    }

    private sealed class Session : IDisposable
    {
        private readonly SemaphoreSlim _writes = new(1, 1);

        public Session(NamedPipeServerStream stream)
        {
            Stream = stream;
        }

        public NamedPipeServerStream Stream { get; }
        public int SessionId { get; set; } = -1;

        /// A pipe allows one write at a time, and the state broadcast and a
        /// pairing reply come from different threads.
        public async Task SendAsync(IpcMessage message, CancellationToken ct)
        {
            await _writes.WaitAsync(ct);
            try { await PipeProtocol.WriteAsync(Stream, message, ct); }
            finally { _writes.Release(); }
        }

        public void Dispose()
        {
            try { Stream.Dispose(); } catch (IOException) { }
            _writes.Dispose();
        }
    }
}

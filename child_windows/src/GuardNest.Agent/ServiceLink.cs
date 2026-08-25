using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using GuardNest.Core;
using GuardNest.Core.Ipc;

namespace GuardNest.Agent;

/// <summary>
/// The agent's connection to the service. It reconnects on its own: the service
/// may restart, or start after the child logs in, and the agent must recover
/// without the child doing anything.
/// </summary>
public sealed class ServiceLink : IAsyncDisposable
{
    private readonly CancellationTokenSource _cts = new();
    private NamedPipeClientStream? _pipe;
    private StreamReader? _reader;
    private Task? _loop;

    public event Action<AgentState>? StateChanged;
    public event Action<bool, string>? PairCompleted;
    public event Action<bool>? ConnectionChanged;

    public bool Connected => _pipe?.IsConnected == true;

    public void Start()
    {
        _loop = Task.Run(() => RunAsync(_cts.Token));
    }

    public async Task SendAsync(IpcMessage message)
    {
        var pipe = _pipe;
        if (pipe is null || !pipe.IsConnected) return;
        try
        {
            await PipeProtocol.WriteAsync(pipe, message, _cts.Token);
        }
        catch (Exception e) when (e is IOException or ObjectDisposedException or OperationCanceledException)
        {
            // The reader loop notices the drop and reconnects.
        }
    }

    private async Task RunAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                _pipe = new NamedPipeClientStream(
                    ".", AppConfig.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
                await _pipe.ConnectAsync(ct);
                _reader = new StreamReader(_pipe, Encoding.UTF8, leaveOpen: true);
                ConnectionChanged?.Invoke(true);

                await PipeProtocol.WriteAsync(_pipe, new IpcMessage
                {
                    Type = IpcMessage.Hello,
                    Text = Environment.UserName,
                    SessionId = Environment.ProcessId > 0
                        ? System.Diagnostics.Process.GetCurrentProcess().SessionId
                        : 0,
                }, ct);

                while (!ct.IsCancellationRequested && _pipe.IsConnected)
                {
                    var message = await PipeProtocol.ReadAsync(_reader, ct);
                    if (message is null) break;
                    Dispatch(message);
                }
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception e) when (e is IOException or TimeoutException or UnauthorizedAccessException)
            {
                Debug.WriteLine($"pipe: {e.Message}");
            }
            finally
            {
                ConnectionChanged?.Invoke(false);
                _reader?.Dispose();
                _pipe?.Dispose();
                _pipe = null;
            }

            try { await Task.Delay(TimeSpan.FromSeconds(3), ct); }
            catch (OperationCanceledException) { return; }
        }
    }

    private void Dispatch(IpcMessage message)
    {
        switch (message.Type)
        {
            case IpcMessage.State when message.Payload is not null:
                StateChanged?.Invoke(message.Payload);
                break;
            case IpcMessage.PairResult:
                PairCompleted?.Invoke(message.Ok, message.Text ?? "");
                break;
        }
    }

    public async ValueTask DisposeAsync()
    {
        _cts.Cancel();
        if (_loop is not null)
        {
            try { await _loop; } catch (OperationCanceledException) { }
        }
        _reader?.Dispose();
        _pipe?.Dispose();
        _cts.Dispose();
    }
}

using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using GuardNest.Core;
using GuardNest.Core.Ipc;

namespace GuardNest.Setup;

/// <summary>Pairs through the installed service, the same path the agent uses.</summary>
internal static class ServicePairingClient
{
    public static async Task<(bool Ok, string Message)> PairAsync(
        string code,
        CancellationToken ct)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(45));

        try
        {
            await using var pipe = new NamedPipeClientStream(
                ".",
                AppConfig.PipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous);
            await pipe.ConnectAsync(timeout.Token);
            using var reader = new StreamReader(pipe, Encoding.UTF8, leaveOpen: true);

            await PipeProtocol.WriteAsync(pipe, new IpcMessage
            {
                Type = IpcMessage.Hello,
                Text = Environment.UserName,
                SessionId = Process.GetCurrentProcess().SessionId,
            }, timeout.Token);
            await PipeProtocol.WriteAsync(pipe, new IpcMessage
            {
                Type = IpcMessage.Pair,
                Text = code,
            }, timeout.Token);

            while (!timeout.IsCancellationRequested)
            {
                var message = await PipeProtocol.ReadAsync(reader, timeout.Token);
                if (message is null) break;
                if (message.Type == IpcMessage.PairResult)
                {
                    return (message.Ok, message.Text ?? "Pairing did not finish.");
                }
            }
        }
        catch (OperationCanceledException)
        {
            return (false, "Pairing timed out. Check the internet connection and try again.");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return (false, "Maryada could not reach its protection service. Try again.");
        }

        return (false, "Pairing did not finish. Try again.");
    }
}
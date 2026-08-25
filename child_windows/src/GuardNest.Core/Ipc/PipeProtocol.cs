using System.Text;
using System.Text.Json;

namespace GuardNest.Core.Ipc;

/// <summary>
/// Newline-delimited JSON over the pipe. A message never contains a raw newline
/// because the serializer escapes them, so a line is always exactly one message.
/// </summary>
public static class PipeProtocol
{
    public static async Task WriteAsync(Stream stream, IpcMessage message, CancellationToken ct)
    {
        var line = JsonSerializer.Serialize(message, IpcMessage.Json) + "\n";
        var bytes = Encoding.UTF8.GetBytes(line);
        await stream.WriteAsync(bytes, ct);
        await stream.FlushAsync(ct);
    }

    public static async Task<IpcMessage?> ReadAsync(StreamReader reader, CancellationToken ct)
    {
        var line = await reader.ReadLineAsync(ct);
        if (line is null) return null;
        try
        {
            return JsonSerializer.Deserialize<IpcMessage>(line, IpcMessage.Json);
        }
        catch (JsonException)
        {
            // A garbled line must not take the connection down with it.
            return new IpcMessage { Type = "" };
        }
    }
}

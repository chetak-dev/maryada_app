using System.Buffers.Binary;
using System.Text;

namespace GuardNest.Service.Dns;

/// <summary>
/// Just enough DNS wire format to read the question and answer it. The filter
/// either forwards the packet untouched or answers it itself, so nothing else
/// needs decoding.
/// </summary>
internal static class DnsMessage
{
    public const int HeaderLength = 12;

    public static string? ReadQuestion(ReadOnlySpan<byte> packet, out int questionEnd)
    {
        questionEnd = 0;
        if (packet.Length < HeaderLength + 5) return null;
        if (BinaryPrimitives.ReadUInt16BigEndian(packet[4..]) != 1) return null;

        var name = new StringBuilder();
        var offset = HeaderLength;
        while (offset < packet.Length)
        {
            int length = packet[offset++];
            if (length == 0) break;
            // A pointer cannot appear in a question, so anything with the top
            // bits set is malformed; refusing it keeps the parser bounded.
            if ((length & 0xC0) != 0 || offset + length > packet.Length) return null;
            if (name.Length > 0) name.Append('.');
            name.Append(Encoding.ASCII.GetString(packet.Slice(offset, length)));
            offset += length;
        }

        if (offset + 4 > packet.Length) return null;
        questionEnd = offset + 4;
        return name.ToString();
    }

    public static byte[] NxDomain(ReadOnlySpan<byte> query, int questionEnd)
    {
        var response = query[..questionEnd].ToArray();
        WriteResponseFlags(response, rcode: 3);
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(6), 0);
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(8), 0);
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(10), 0);
        return response;
    }

    private static void WriteResponseFlags(byte[] packet, int rcode)
    {
        packet[2] = (byte)(packet[2] | 0x80);
        packet[3] = (byte)(0x80 | (rcode & 0x0F));
    }
}

using System.Buffers.Binary;
using System.Text;

namespace GuardNest.Windows.Spikes.Dns;

/// <summary>
/// Just enough DNS wire format to read the question and answer it — the filter
/// only needs the queried name, and either forwards the packet untouched or
/// answers it itself.
/// </summary>
internal static class DnsMessage
{
    public const int HeaderLength = 12;

    /// <summary>Reads the queried name, or null when the packet is not a question we understand.</summary>
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

    /// <summary>"This name does not exist" — the cheapest way to stop a lookup.</summary>
    public static byte[] NxDomain(ReadOnlySpan<byte> query, int questionEnd)
    {
        var response = query[..questionEnd].ToArray();
        WriteResponseFlags(response, rcode: 3);
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(6), 0); // ANCOUNT
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(8), 0); // NSCOUNT
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(10), 0); // ARCOUNT
        return response;
    }

    /// <summary>
    /// Answers with 127.0.0.1 so a local block page can serve the request.
    /// Only useful for plain HTTP; HTTPS would fail the certificate check, which
    /// is why the on-screen block overlay stays the primary signal to the child.
    /// </summary>
    public static byte[] Sinkhole(ReadOnlySpan<byte> query, int questionEnd, byte[] address)
    {
        var answer = new byte[16];
        BinaryPrimitives.WriteUInt16BigEndian(answer.AsSpan(0), 0xC00C); // name -> question
        BinaryPrimitives.WriteUInt16BigEndian(answer.AsSpan(2), 1); // A
        BinaryPrimitives.WriteUInt16BigEndian(answer.AsSpan(4), 1); // IN
        BinaryPrimitives.WriteUInt32BigEndian(answer.AsSpan(6), 60); // TTL
        BinaryPrimitives.WriteUInt16BigEndian(answer.AsSpan(10), 4); // RDLENGTH
        address.CopyTo(answer, 12);

        var response = new byte[questionEnd + answer.Length];
        query[..questionEnd].CopyTo(response);
        answer.CopyTo(response, questionEnd);
        WriteResponseFlags(response, rcode: 0);
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(6), 1);
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(8), 0);
        BinaryPrimitives.WriteUInt16BigEndian(response.AsSpan(10), 0);
        return response;
    }

    public static int ResponseCode(ReadOnlySpan<byte> packet) =>
        packet.Length < HeaderLength ? -1 : packet[3] & 0x0F;

    public static int AnswerCount(ReadOnlySpan<byte> packet) =>
        packet.Length < HeaderLength ? 0 : BinaryPrimitives.ReadUInt16BigEndian(packet[6..]);

    public static byte[] Query(string name, ushort id)
    {
        var labels = name.Split('.', StringSplitOptions.RemoveEmptyEntries);
        var size = HeaderLength + labels.Sum(l => l.Length + 1) + 1 + 4;
        var packet = new byte[size];
        BinaryPrimitives.WriteUInt16BigEndian(packet.AsSpan(0), id);
        packet[2] = 0x01; // recursion desired
        BinaryPrimitives.WriteUInt16BigEndian(packet.AsSpan(4), 1); // QDCOUNT

        var offset = HeaderLength;
        foreach (var label in labels)
        {
            packet[offset++] = (byte)label.Length;
            Encoding.ASCII.GetBytes(label).CopyTo(packet, offset);
            offset += label.Length;
        }
        packet[offset++] = 0;
        BinaryPrimitives.WriteUInt16BigEndian(packet.AsSpan(offset), 1); // A
        BinaryPrimitives.WriteUInt16BigEndian(packet.AsSpan(offset + 2), 1); // IN
        return packet;
    }

    private static void WriteResponseFlags(byte[] packet, int rcode)
    {
        packet[2] = (byte)(packet[2] | 0x80); // QR = response
        packet[3] = (byte)(0x80 | (rcode & 0x0F)); // recursion available + rcode
    }
}

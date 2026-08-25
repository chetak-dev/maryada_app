using GuardNest.Core.Firebase;

namespace GuardNest.Core.Chat;

/// <summary>
/// Uploads captured chats. Each message is its own document in a per-contact
/// thread, keyed by a hash of the message itself, so a re-upload merges into the
/// existing document instead of adding a copy.
/// </summary>
public sealed class ChatReporter
{
    /// Firestore caps a commit at 500 writes.
    private const int BatchLimit = 400;

    private readonly FirestoreClient _firestore;
    private readonly AnonymousAuth _auth;

    /// The newest message already written per thread. A re-uploaded old message
    /// (one that only just revealed its date) would otherwise drag a live
    /// conversation to the bottom of the parent's chat list.
    private readonly Dictionary<string, long> _threadLatestAt = new(StringComparer.Ordinal);

    public ChatReporter(FirestoreClient firestore, AnonymousAuth auth)
    {
        _firestore = firestore;
        _auth = auth;
    }

    public async Task ReportAsync(
        DeviceState state, IReadOnlyList<ChatMessage> messages, CancellationToken ct)
    {
        if (messages.Count == 0) return;

        var root = $"families/{state.FamilyId}/children/{state.ChildId}/chatThreads";
        var deviceUid = _auth.Uid;

        var writes = new List<FirestoreWrite>();
        var deletes = new List<string>();
        var latest = new Dictionary<string, (ChatMessage Message, long At)>(StringComparer.Ordinal);

        foreach (var message in messages)
        {
            var threadKey = ChatIds.Hash($"{message.App}\u0000{message.Sender}");
            var sortAt = ChatIds.SortAt(message.TimeLabel, message.At, message.Slot, message.DayStart);

            if (message.Replaces.Length > 0)
            {
                deletes.Add($"{root}/{threadKey}/messages/{ChatIds.Hash(message.Replaces)}");
            }

            writes.Add(new FirestoreWrite(
                $"{root}/{threadKey}/messages/{ChatIds.Hash(message.DocKey)}",
                new Dictionary<string, object?>
                {
                    ["sender"] = message.Sender,
                    ["app"] = message.App,
                    ["text"] = message.Text,
                    ["outgoing"] = message.Outgoing,
                    // Only ever the bubble's own clock. Falling back to the time
                    // we happened to scrape it showed a time it was never sent.
                    ["time"] = message.TimeLabel,
                    ["at"] = sortAt,
                    ["deviceUid"] = deviceUid,
                },
                ServerTimestamps: new[] { "createdAt" }));

            if (!latest.TryGetValue(threadKey, out var current) || sortAt >= current.At)
            {
                latest[threadKey] = (message, sortAt);
            }
        }

        foreach (var (threadKey, entry) in latest)
        {
            if (entry.At < _threadLatestAt.GetValueOrDefault(threadKey)) continue;
            _threadLatestAt[threadKey] = entry.At;

            var summary = new Dictionary<string, object?>
            {
                ["sender"] = entry.Message.Sender,
                ["app"] = entry.Message.App,
                ["senderKey"] = threadKey,
                ["lastText"] = entry.Message.Text,
                ["lastOutgoing"] = entry.Message.Outgoing,
                ["lastTime"] = entry.Message.TimeLabel,
                ["at"] = entry.At,
                ["deviceUid"] = deviceUid,
            };
            if (entry.Message.Number.Length > 0) summary["number"] = entry.Message.Number;

            writes.Add(new FirestoreWrite(
                $"{root}/{threadKey}", summary, ServerTimestamps: new[] { "updatedAt" }));
        }

        for (var offset = 0; offset < writes.Count; offset += BatchLimit)
        {
            var chunk = writes.Skip(offset).Take(BatchLimit).ToList();
            // The delete of a superseded document must land with the write that
            // replaces it, or a failure between the two loses the message.
            var chunkDeletes = offset == 0 ? deletes : null;
            await _firestore.CommitAsync(chunk, ct, chunkDeletes);
        }
    }
}

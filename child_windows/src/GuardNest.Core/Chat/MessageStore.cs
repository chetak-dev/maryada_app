using System.Text.Json;

namespace GuardNest.Core.Chat;

/// <summary>
/// Buffers captured chat messages and decides which message each sighting is.
///
/// The hard part is identity, not capture. The same message is seen again on
/// every scroll and every reopened chat, and a later sighting often knows LESS
/// than an earlier one — WhatsApp shows the date only on a separator, and a
/// recycled row can hide the bubble's own time. Since the document id is derived
/// from the day and time, a sighting that learned more used to mint a second id
/// and the parent saw the message twice. This remembers what was already
/// uploaded and supersedes it instead.
/// </summary>
public sealed class MessageStore
{
    private const int PendingMax = 400;
    private const int IdentityMax = 3000;

    /// Ids are a deterministic hash written with merge, so re-sending cannot
    /// duplicate anything — this only saves bandwidth. Keeping it forever meant
    /// that once the parent wiped history, every message still on screen stayed
    /// suppressed and the chat list never came back.
    private static readonly TimeSpan ResendTtl = TimeSpan.FromHours(6);

    private readonly object _gate = new();
    private readonly LinkedList<string> _recency = new();
    private readonly Dictionary<string, Bucket> _identities = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _groupSlots = new(StringComparer.Ordinal);
    private readonly List<ChatMessage> _pending = new();

    public MessageStore()
    {
        Load();
    }

    public bool HasChanges
    {
        get { lock (_gate) return _pending.Count > 0; }
    }

    /// <summary>
    /// Records one sighting. Returns true when it produced something to upload.
    ///
    /// Identity deliberately excludes the day and the clock label: both come
    /// from WhatsApp's floating date pill and per-bubble times, which shift with
    /// scroll position, so treating a disagreement as a different message filed
    /// a fresh copy every time the chat was reopened.
    /// </summary>
    public bool Record(ChatSighting sighting, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(sighting.Text)) return false;

        var label = sighting.TimeLabel.Trim();
        lock (_gate)
        {
            var loose = ChatIds.LooseKey(sighting.App, sighting.Sender, sighting.Text);
            var bucket = Touch(loose);

            // More copies on screen than we have ever seen at once: this really
            // is another message, not another reading of an old one.
            if (sighting.Occurrence >= bucket.Entries.Count)
            {
                var slot = NextSlot(loose, sighting.DayStart, label);
                bucket.Entries.Add(new Entry
                {
                    Day = sighting.DayStart,
                    Label = label,
                    Side = sighting.Outgoing,
                    Slot = slot,
                    At = now,
                });
                Queue(new ChatMessage(
                    sighting.App, sighting.Sender, sighting.Text, now.ToUnixTimeMilliseconds(),
                    sighting.Outgoing == true, label, sighting.Number, sighting.DayStart, slot,
                    ChatIds.DocKey(loose, sighting.DayStart, label), ""));
                return true;
            }

            var entry = bucket.Entries[sighting.Occurrence];
            var learnsDay = entry.Day <= 0 && sighting.DayStart > 0;
            var learnsTime = !ChatIds.IsClock(entry.Label) && ChatIds.IsClock(label);
            var learnsSide = entry.Side is null && sighting.Outgoing is not null;
            if (!learnsDay && !learnsTime && !learnsSide && now - entry.At < ResendTtl)
            {
                return false;
            }

            var was = ChatIds.DocKey(loose, entry.Day, entry.Label);
            if (learnsDay) entry.Day = sighting.DayStart;
            if (learnsTime) entry.Label = label;
            if (learnsSide) entry.Side = sighting.Outgoing;
            entry.At = now;

            var key = ChatIds.DocKey(loose, entry.Day, entry.Label);
            // Only a message that moved to a different minute needs a new
            // position; re-sending one otherwise must not shuffle the thread.
            if (key != was) entry.Slot = NextSlot(loose, entry.Day, entry.Label);

            Queue(new ChatMessage(
                sighting.App, sighting.Sender, sighting.Text, now.ToUnixTimeMilliseconds(),
                entry.Side == true, entry.Label, sighting.Number, entry.Day, entry.Slot,
                key, key == was ? "" : was));
            return true;
        }
    }

    /// <summary>Removes and returns the queued messages, oldest first.</summary>
    public IReadOnlyList<ChatMessage> Drain()
    {
        List<ChatMessage> drained;
        lock (_gate)
        {
            drained = new List<ChatMessage>(_pending);
            _pending.Clear();
        }
        if (drained.Count > 0) Persist();
        return drained;
    }

    /// <summary>Puts failed uploads back at the front so nothing is lost.</summary>
    public void Requeue(IReadOnlyList<ChatMessage> messages)
    {
        lock (_gate)
        {
            _pending.InsertRange(0, messages);
            TrimPending();
        }
    }

    /// <summary>
    /// Forgets everything captured. After the parent wipes history server-side
    /// the messages still on screen must be capturable again, or the dedup
    /// memory silently keeps the chat list empty.
    /// </summary>
    public void ResetForClear()
    {
        lock (_gate)
        {
            _pending.Clear();
            _identities.Clear();
            _recency.Clear();
            _groupSlots.Clear();
        }
        try { File.Delete(Path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    private Bucket Touch(string loose)
    {
        if (_identities.TryGetValue(loose, out var bucket))
        {
            // Re-inserting keeps least-recently-seen order, so eviction drops
            // the messages that scrolled out of reach first.
            _recency.Remove(bucket.Node);
            bucket.Node = _recency.AddLast(loose);
            return bucket;
        }

        bucket = new Bucket { Node = _recency.AddLast(loose) };
        _identities[loose] = bucket;
        while (_identities.Count > IdentityMax && _recency.First is { } oldest)
        {
            _identities.Remove(oldest.Value);
            _recency.RemoveFirst();
        }
        return bucket;
    }

    private int NextSlot(string loose, long day, string label)
    {
        var group = ChatIds.GroupKey(loose, day, label);
        var slot = _groupSlots.GetValueOrDefault(group);
        _groupSlots[group] = slot + 1;
        return Math.Min(slot, 999);
    }

    private void Queue(ChatMessage message)
    {
        _pending.Add(message);
        TrimPending();
    }

    /// A long parent outage must not grow memory without bound; the oldest
    /// queued messages go first.
    private void TrimPending()
    {
        if (_pending.Count > PendingMax) _pending.RemoveRange(0, _pending.Count - PendingMax);
    }

    private static string Path => DataFolder.Path("chat-identities.json");

    private void Persist()
    {
        try
        {
            List<Persisted> snapshot;
            lock (_gate)
            {
                snapshot = _identities
                    .Select(entry => new Persisted(entry.Key, entry.Value.Entries))
                    .ToList();
            }
            File.WriteAllText(Path, JsonSerializer.Serialize(snapshot));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Diag.Warn("messageStore.persist", e);
        }
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(Path)) return;
            var snapshot = JsonSerializer.Deserialize<List<Persisted>>(File.ReadAllText(Path));
            if (snapshot is null) return;
            foreach (var record in snapshot)
            {
                var bucket = Touch(record.Loose);
                bucket.Entries.AddRange(record.Entries);
                foreach (var entry in record.Entries)
                {
                    var group = ChatIds.GroupKey(record.Loose, entry.Day, entry.Label);
                    _groupSlots[group] = Math.Max(_groupSlots.GetValueOrDefault(group), entry.Slot + 1);
                }
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            Diag.Warn("messageStore.load", e);
        }
    }

    /// <summary>What we know, and already uploaded, about one captured message.</summary>
    public sealed class Entry
    {
        public long Day { get; set; }
        public string Label { get; set; } = "";

        /// Null until a sighting could actually tell which side the row sits on.
        /// Never guessed: "ok" from the child and "ok" from the contact are the
        /// same text in the same chat, so a guess would let one adopt the
        /// other's identity and flip sides on screen.
        public bool? Side { get; set; }

        public int Slot { get; set; }
        public DateTimeOffset At { get; set; }
    }

    private sealed class Bucket
    {
        public List<Entry> Entries { get; } = new();
        public LinkedListNode<string> Node { get; set; } = null!;
    }

    private sealed record Persisted(string Loose, List<Entry> Entries);
}

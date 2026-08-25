using GuardNest.Core.Chat;
using GuardNest.Core.Media;

namespace GuardNest.Core.Tests;

public class ChatIdTests
{
    [Fact]
    public void Doc_ids_match_the_android_format()
    {
        var loose = ChatIds.LooseKey("WhatsApp", "Riya", "see you at 6");
        var key = ChatIds.DocKey(loose, DayStart(2026, 8, 25), "10:24 PM");

        // Day 20690 is 2026-08-25; the label loses its space and is upper-cased.
        Assert.Equal("WhatsApp\u0000Riya\u0000see you at 6\u00002069010:24PM", key);
        // Computed independently, so a change to the hashing would fail here
        // rather than silently duplicating every message in the parent's app.
        Assert.Equal("aab94e825eaaa996006ae21310de2fcd", ChatIds.Hash(key));
    }

    [Fact]
    public void A_message_with_no_time_still_gets_a_stable_id()
    {
        var loose = ChatIds.LooseKey("WhatsApp", "Riya", "hi");
        Assert.Equal("WhatsApp\u0000Riya\u0000hi\u0000NOTIME", ChatIds.DocKey(loose, 0, ""));
    }

    [Fact]
    public void A_known_day_anchors_the_time_exactly()
    {
        var day = DayStart(2026, 8, 25);
        var at = ChatIds.SortAt("10:24 PM", fallback: 0, slot: 3, dayStart: day);
        Assert.Equal(day + (22 * 3600 + 24 * 60) * 1000L + 3, at);
    }

    [Fact]
    public void Messages_sharing_a_minute_keep_their_order()
    {
        var day = DayStart(2026, 8, 25);
        var first = ChatIds.SortAt("10:24 PM", 0, slot: 0, dayStart: day);
        var second = ChatIds.SortAt("10:24 PM", 0, slot: 1, dayStart: day);
        Assert.True(second > first);
    }

    [Fact]
    public void An_unanchored_future_time_is_read_as_yesterday()
    {
        var now = new DateTimeOffset(2026, 8, 25, 9, 0, 0, TimeSpan.Zero);
        var at = ChatIds.SortAt("11:00 PM", fallback: 0, slot: 0, dayStart: 0, nowOverride: now);
        Assert.True(DateTimeOffset.FromUnixTimeMilliseconds(at) < now);
    }

    [Theory]
    [InlineData("10:24", true)]
    [InlineData("10:24 PM", true)]
    [InlineData("Yesterday", false)]
    [InlineData("", false)]
    public void Only_a_clock_counts_as_a_time_label(string label, bool expected) =>
        Assert.Equal(expected, ChatIds.IsClock(label));

    private static long DayStart(int year, int month, int day) =>
        new DateTimeOffset(year, month, day, 0, 0, 0, TimeSpan.Zero).ToUnixTimeMilliseconds();
}

public class MessageStoreTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 25, 12, 0, 0, TimeSpan.Zero);

    /// The store is a singleton in the service and shares one identity file, so
    /// a test has to start from a cleared one to be independent.
    private static MessageStore NewStore()
    {
        var store = new MessageStore();
        store.ResetForClear();
        return store;
    }

    private static ChatSighting Sighting(
        string text = "see you at 6",
        bool? outgoing = null,
        string time = "",
        long day = 0,
        int occurrence = 0) =>
        new("WhatsApp", "Riya", text, outgoing, time, "", day, occurrence);

    [Fact]
    public void A_new_message_is_queued_once()
    {
        var store = NewStore();
        Assert.True(store.Record(Sighting(time: "10:24 PM"), Now));
        // Seeing the same row again on the next scroll must not re-upload it.
        Assert.False(store.Record(Sighting(time: "10:24 PM"), Now));
        Assert.Single(store.Drain());
    }

    [Fact]
    public void Learning_the_day_supersedes_the_earlier_document()
    {
        var store = NewStore();
        store.Record(Sighting(time: "10:24 PM"), Now);
        store.Drain();

        // The date separator finally scrolled into view.
        Assert.True(store.Record(Sighting(time: "10:24 PM", day: 20_690 * 86_400_000L), Now));
        var queued = Assert.Single(store.Drain());
        Assert.NotEqual("", queued.Replaces);
        Assert.NotEqual(queued.Replaces, queued.DocKey);
    }

    [Fact]
    public void Learning_the_time_supersedes_the_earlier_document()
    {
        var store = NewStore();
        store.Record(Sighting(), Now);
        store.Drain();

        Assert.True(store.Record(Sighting(time: "10:24 PM"), Now));
        var queued = Assert.Single(store.Drain());
        Assert.Contains("NOTIME", queued.Replaces);
        Assert.Contains("10:24PM", queued.DocKey);
    }

    [Fact]
    public void The_same_text_twice_in_one_pass_is_two_messages()
    {
        var store = NewStore();
        Assert.True(store.Record(Sighting("ok", occurrence: 0), Now));
        Assert.True(store.Record(Sighting("ok", occurrence: 1), Now));

        var queued = store.Drain();
        Assert.Equal(2, queued.Count);
        // Different slots, or they would collide on one millisecond and the
        // thread would order them at random.
        Assert.NotEqual(queued[0].Slot, queued[1].Slot);
    }

    [Fact]
    public void A_side_is_learned_but_never_guessed()
    {
        var store = NewStore();
        store.Record(Sighting(time: "10:24 PM"), Now);
        var undecided = Assert.Single(store.Drain());
        Assert.False(undecided.Outgoing);

        Assert.True(store.Record(Sighting(time: "10:24 PM", outgoing: true), Now));
        var decided = Assert.Single(store.Drain());
        Assert.True(decided.Outgoing);
        // Only the side changed, so the document must stay the same one.
        Assert.Equal("", decided.Replaces);
        Assert.Equal(undecided.DocKey, decided.DocKey);
    }

    [Fact]
    public void Failed_uploads_go_back_on_the_queue()
    {
        var store = NewStore();
        store.Record(Sighting(time: "10:24 PM"), Now);
        var drained = store.Drain();
        Assert.False(store.HasChanges);

        store.Requeue(drained);
        Assert.True(store.HasChanges);
        Assert.Single(store.Drain());
    }
}

public class ChatTitleTests
{
    [Theory]
    [InlineData("Riya - WhatsApp", "Riya")]
    [InlineData("(3) Riya - WhatsApp", "Riya")]
    [InlineData("(12) Riya Sharma - WhatsApp - Google Chrome", "Riya Sharma")]
    [InlineData("Riya - WhatsApp and 4 more pages - Work - Microsoft Edge", "Riya")]
    public void The_contact_is_read_from_the_title(string title, string expected) =>
        Assert.Equal(expected, ChatTitles.ConversationFrom(title));

    [Theory]
    [InlineData("WhatsApp")]
    [InlineData("WhatsApp Web - Google Chrome")]
    [InlineData("")]
    public void An_unnamed_conversation_is_refused(string title) =>
        Assert.Null(ChatTitles.ConversationFrom(title));
}

public class YoutubeTitleTests
{
    [Theory]
    [InlineData("Never Gonna Give You Up - YouTube - Google Chrome", "Never Gonna Give You Up")]
    [InlineData("(2) Lo-fi beats - YouTube — Mozilla Firefox", "Lo-fi beats")]
    [InlineData("Maths in 5 minutes - YouTube and 3 more pages - Work - Microsoft Edge", "Maths in 5 minutes")]
    public void The_video_name_is_read_from_the_title(string title, string expected) =>
        Assert.Equal(expected, YoutubeStore.TitleFrom(title));

    [Theory]
    [InlineData("YouTube - Google Chrome")]
    [InlineData("Example Domain - Google Chrome")]
    [InlineData("")]
    public void Anything_that_is_not_a_video_page_is_ignored(string title) =>
        Assert.Null(YoutubeStore.TitleFrom(title));

    [Fact]
    public void Watch_time_accumulates_and_a_long_gap_is_capped()
    {
        var store = new YoutubeStore();
        var now = DateTimeOffset.UtcNow;
        store.Record("Lo-fi beats", TimeSpan.FromSeconds(5), now);
        // A tab left open overnight must not report as a night of watching.
        store.Record("Lo-fi beats", TimeSpan.FromHours(8), now);

        var videos = (List<object?>)store.Snapshot(now)["videos"]!;
        var first = (Dictionary<string, object?>)videos[0]!;
        Assert.Equal("Lo-fi beats", first["title"]);
        Assert.Equal(20_000L, first["watchedMs"]);
    }

    [Fact]
    public void A_video_glanced_at_is_not_reported_until_it_is_really_watched()
    {
        var store = new YoutubeStore();
        store.ClearAll();
        var now = DateTimeOffset.UtcNow;

        store.Record("Opened by mistake", TimeSpan.FromSeconds(8), now);
        Assert.Empty((List<object?>)store.Snapshot(now)["videos"]!);

        // The time keeps accruing, so it appears once it passes the threshold.
        store.Record("Opened by mistake", TimeSpan.FromSeconds(12), now);
        Assert.Single((List<object?>)store.Snapshot(now)["videos"]!);
    }
}

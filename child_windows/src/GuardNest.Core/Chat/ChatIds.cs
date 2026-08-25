using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace GuardNest.Core.Chat;

/// <summary>
/// Document ids and sort keys for captured chats.
///
/// Every string built here is byte-for-byte what the Android app builds, because
/// the ids are a hash of that material and both devices write to the same
/// thread. Change the format on one side only and the same WhatsApp message
/// arrives twice in the parent's app.
/// </summary>
public static class ChatIds
{
    private static readonly Regex Clock = new(@"^\d{1,2}:\d{2}\s?([AaPp][Mm])?$", RegexOptions.Compiled);
    private static readonly Regex ClockPrefix = new(@"^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?", RegexOptions.Compiled);

    /// A bubble time label is only ever a clock; anything else is a stray string.
    public static bool IsClock(string label) => Clock.IsMatch(label.Trim());

    public static string LooseKey(string app, string sender, string text) =>
        $"{app}\u0000{sender}\u0000{text}";

    public static string DocKey(string looseKey, long dayStart, string label) =>
        $"{looseKey}\u0000{DayKey(dayStart)}{TimeKey(label)}";

    public static string DayKey(long dayStart) =>
        dayStart > 0 ? (dayStart / 86_400_000L).ToString(CultureInfo.InvariantCulture) : "";

    public static string TimeKey(string label) =>
        string.IsNullOrWhiteSpace(label) ? "NOTIME" : label.ToUpperInvariant().Replace(" ", "");

    /// <summary>The chat and minute a slot is counted within.</summary>
    public static string GroupKey(string looseKey, long dayStart, string label)
    {
        var app = looseKey.IndexOf('\u0000');
        var sender = app < 0 ? -1 : looseKey.IndexOf('\u0000', app + 1);
        var chat = sender < 0 ? looseKey : looseKey[..sender];
        return $"{chat}\u0000{DayKey(dayStart)}{TimeKey(label)}";
    }

    /// <summary>
    /// The deterministic document id. MD5 is used for its stability, not for
    /// security: it only has to produce the same id the Android app produces.
    /// </summary>
    public static string Hash(string material)
    {
        var digest = MD5.HashData(Encoding.UTF8.GetBytes(material));
        return Convert.ToHexString(digest).ToLowerInvariant();
    }

    /// <summary>
    /// A sortable timestamp from a bubble label like "10:24 PM". The label has
    /// no seconds, so <paramref name="slot"/> separates messages sharing a
    /// minute — without it Firestore falls back to ordering by the (hashed,
    /// effectively random) id.
    /// </summary>
    public static long SortAt(string label, long fallback, int slot = 0, long dayStart = 0, DateTimeOffset? nowOverride = null)
    {
        var position = Math.Clamp(slot, 0, 999);
        var match = ClockPrefix.Match(label ?? "");
        if (!match.Success) return (dayStart > 0 ? dayStart : fallback) + position;

        if (!int.TryParse(match.Groups[1].Value, out var hour) ||
            !int.TryParse(match.Groups[2].Value, out var minute))
        {
            return (dayStart > 0 ? dayStart : fallback) + position;
        }

        var meridiem = match.Groups[3].Value.ToUpperInvariant();
        if (meridiem == "PM" && hour != 12) hour += 12;
        if (meridiem == "AM" && hour == 12) hour = 0;
        if (hour > 23 || minute > 59) return (dayStart > 0 ? dayStart : fallback) + position;

        // A known day is exact; anchor to it and skip the guesswork below.
        if (dayStart > 0) return dayStart + hour * 3_600_000L + minute * 60_000L + position;

        var now = nowOverride ?? DateTimeOffset.Now;
        var candidate = new DateTimeOffset(
            now.Year, now.Month, now.Day, hour, minute, 0, now.Offset).AddMilliseconds(position);
        // No date separator was visible, so the day is inferred: a time that
        // would land in the future cannot be from today. The slack absorbs the
        // label's missing seconds and any clock skew.
        if (candidate > now.AddMinutes(2)) candidate = candidate.AddDays(-1);
        return candidate.ToUnixTimeMilliseconds();
    }
}

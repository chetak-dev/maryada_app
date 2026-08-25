using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using GuardNest.Core.Chat;

namespace GuardNest.Agent;

/// <summary>
/// Reads the open conversation out of WhatsApp through UI Automation. The chat
/// database itself is encrypted and sandboxed, so what is on screen is the only
/// thing there is to read — the same constraint the Android build works under.
/// </summary>
internal sealed class ChatScanner
{
    private const string WhatsApp = "WhatsApp";

    /// A row further from one edge than the other by this much is on that side.
    /// Matched to the Android build, where a plain margin test read long
    /// messages as centred and lost their side.
    private const double SideRatio = 1.6;

    private static readonly Regex Clock = new(
        @"^\d{1,2}:\d{2}(\s?[AaPp][Mm])?$", RegexOptions.Compiled);

    /// Anything shorter is a status word ("Delivered"), not a message.
    private const int MinimumTextLength = 2;

    public static bool IsChatApp(string executableKey) => executableKey == "whatsapp.exe";

    public static bool IsChatUrl(string url) =>
        Core.Web.Domains.HostOf(url) == "web.whatsapp.com";

    public static string? ConversationFrom(string windowTitle) =>
        ChatTitles.ConversationFrom(windowTitle);

    /// <summary>
    /// One pass over the conversation. Returns a sighting per visible row; the
    /// store decides which of them are messages it has already seen.
    /// </summary>
    public IReadOnlyList<ChatSighting> Scan(IntPtr window, string conversation)
    {
        try
        {
            var root = AutomationElement.FromHandle(window);
            if (root is null) return Array.Empty<ChatSighting>();

            var rows = root.FindAll(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem));
            if (rows.Count == 0) return Array.Empty<ChatSighting>();

            var bounds = ListBounds(rows);
            var seen = new Dictionary<string, int>(StringComparer.Ordinal);
            var sightings = new List<ChatSighting>();

            foreach (AutomationElement row in rows)
            {
                var parsed = ReadRow(row, bounds);
                if (parsed is null) continue;

                // The same text twice in one pass is two different messages, not
                // one read twice; the count is what tells them apart later.
                var occurrence = seen.GetValueOrDefault(parsed.Value.Text);
                seen[parsed.Value.Text] = occurrence + 1;

                sightings.Add(new ChatSighting(
                    App: WhatsApp,
                    Sender: conversation,
                    Text: parsed.Value.Text,
                    Outgoing: parsed.Value.Side,
                    TimeLabel: parsed.Value.Time,
                    Occurrence: occurrence));
            }
            return sightings;
        }
        catch (Exception e) when (e is ElementNotAvailableException or COMException or InvalidOperationException)
        {
            return Array.Empty<ChatSighting>();
        }
    }

    private static (string Text, string Time, bool? Side)? ReadRow(AutomationElement row, Rect bounds)
    {
        Rect rect;
        try { rect = row.Current.BoundingRectangle; }
        catch (ElementNotAvailableException) { return null; }
        if (rect.IsEmpty || rect.Width <= 0) return null;

        var parts = new List<string>();
        var name = Safe(() => row.Current.Name);
        if (name.Length > 0) parts.Add(name);

        foreach (AutomationElement child in row.FindAll(
                     TreeScope.Descendants,
                     new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Text)))
        {
            var value = Safe(() => child.Current.Name).Trim();
            if (value.Length > 0 && !parts.Contains(value)) parts.Add(value);
        }
        if (parts.Count == 0) return null;

        var time = parts.LastOrDefault(part => Clock.IsMatch(part.Trim()))?.Trim() ?? "";
        var text = parts
            .Where(part => !Clock.IsMatch(part.Trim()))
            .OrderByDescending(part => part.Length)
            .FirstOrDefault()?.Trim() ?? "";
        if (text.Length < MinimumTextLength) return null;

        return (text, time, SideOf(rect, bounds));
    }

    /// <summary>
    /// Which side of the thread the row sits on, or null when it cannot be told.
    /// Never guess: "ok" from the child and "ok" from the contact are the same
    /// text in the same chat, so a guessed side lets one adopt the other's
    /// identity and the conversation flips around on the parent's screen.
    /// </summary>
    private static bool? SideOf(Rect row, Rect bounds)
    {
        if (bounds.Width <= 0) return null;
        var left = Math.Max(row.Left - bounds.Left, 0) + 1;
        var right = Math.Max(bounds.Right - row.Right, 0) + 1;
        if (left / right >= SideRatio) return true;
        if (right / left >= SideRatio) return false;
        return null;
    }

    private static Rect ListBounds(AutomationElementCollection rows)
    {
        var bounds = Rect.Empty;
        foreach (AutomationElement row in rows)
        {
            try
            {
                var rect = row.Current.BoundingRectangle;
                if (!rect.IsEmpty) bounds.Union(rect);
            }
            catch (ElementNotAvailableException)
            {
            }
        }
        return bounds;
    }

    private static string Safe(Func<string> read)
    {
        try { return read() ?? ""; }
        catch (Exception e) when (e is ElementNotAvailableException or COMException) { return ""; }
    }
}

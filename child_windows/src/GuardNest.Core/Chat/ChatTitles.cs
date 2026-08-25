using System.Text.RegularExpressions;

namespace GuardNest.Core.Chat;

/// <summary>
/// Reads the contact out of a window title. Kept separate from the scanner
/// because getting it wrong is expensive: the thread id is a hash of the
/// contact, so a guessed name files real messages under a thread that does not
/// exist in the parent's app.
/// </summary>
public static class ChatTitles
{
    private static readonly Regex UnreadCount = new(@"^\(\d+\)\s*", RegexOptions.Compiled);

    private static readonly Regex BrowserSuffix = new(
        @"\s+[-\u2014]\s+(Google Chrome|Microsoft.?\s*Edge|Mozilla Firefox|Brave|Opera|Vivaldi)\s*$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Edge appends the tab count and profile name to every title.
    private static readonly Regex EdgeExtras = new(
        @"\s+and\s+\d+\s+more\s+pages?.*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex AppSuffix = new(
        @"\s*[-\u2014|]\s*WhatsApp(\s+Web)?\s*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>The open conversation, or null when the title does not name one.</summary>
    public static string? ConversationFrom(string windowTitle)
    {
        if (string.IsNullOrWhiteSpace(windowTitle)) return null;

        var value = BrowserSuffix.Replace(windowTitle.Trim(), "");
        value = EdgeExtras.Replace(value, "").Trim();
        value = UnreadCount.Replace(value, "");
        value = AppSuffix.Replace(value, "").Trim();

        if (value.Length == 0) return null;
        return value.Equals("WhatsApp", StringComparison.OrdinalIgnoreCase)
               || value.Equals("WhatsApp Web", StringComparison.OrdinalIgnoreCase)
            ? null
            : value;
    }
}

using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace GuardNest.Agent;

/// <summary>
/// Reads the text a browser has actually rendered, which is how the phone's
/// accessibility service decides a page is unsafe. It works on HTTPS because it
/// reads the finished page, not the traffic, so no certificate interception is
/// involved.
/// </summary>
internal sealed class PageTextReader
{
    /// Enough for the body of a page; unsafe pages repeat their terms far
    /// sooner than this, and the whole string crosses the pipe every sample.
    private const int MaxCharacters = 8000;

    /// A page keeps filling in after it opens, so the text is re-read on a
    /// timer rather than once per address.
    private static readonly TimeSpan Refresh = TimeSpan.FromSeconds(2);

    /// Finding the tab's document means walking the browser's entire element
    /// tree, which measured over a second on a busy Firefox window. Reading an
    /// already-found document is about 4ms, so only the search is worth rationing.
    private static readonly TimeSpan SearchThrottle = TimeSpan.FromSeconds(5);

    private readonly Dictionary<IntPtr, AutomationElement> _documents = new();
    private DateTimeOffset _searchedAt = DateTimeOffset.MinValue;
    private string _address = "";
    private string _text = "";
    private DateTimeOffset _readAt = DateTimeOffset.MinValue;

    public string Read(IntPtr window, string address, DateTimeOffset now)
    {
        if (!string.Equals(address, _address, StringComparison.Ordinal))
        {
            _address = address;
            _text = "";
            _readAt = DateTimeOffset.MinValue;
            // Opening a page is exactly when the check matters, so the search
            // throttle must not hold the new page's text back.
            _searchedAt = DateTimeOffset.MinValue;
        }

        if (now - _readAt < Refresh) return _text;
        _readAt = now;
        _text = ReadDocument(window, now);
        return _text;
    }

    private string ReadDocument(IntPtr window, DateTimeOffset now)
    {
        try
        {
            if (_documents.TryGetValue(window, out var cached))
            {
                if (IsShowing(cached)) return TextOf(cached) ?? "";
                // The child switched tabs, so this document is a background one
                // and its text is not what is on the screen.
                _documents.Remove(window);
            }

            if (now - _searchedAt < SearchThrottle) return "";
            _searchedAt = now;

            var document = Locate(window);
            if (document is null) return "";

            _documents[window] = document;
            return TextOf(document) ?? "";
        }
        catch (Exception e) when (e is ElementNotAvailableException or COMException or InvalidOperationException)
        {
            _documents.Remove(window);
            return "";
        }
    }

    /// <summary>
    /// The document of the tab actually on screen. A browser keeps one document
    /// per open tab, and the first match is usually a background tab holding a
    /// page the child is not looking at.
    /// </summary>
    private static AutomationElement? Locate(IntPtr window)
    {
        var root = AutomationElement.FromHandle(window);
        if (root is null) return null;

        var documents = root.FindAll(
            TreeScope.Descendants,
            new AndCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document),
                new PropertyCondition(AutomationElement.IsTextPatternAvailableProperty, true)));

        foreach (AutomationElement document in documents)
        {
            if (IsShowing(document)) return document;
        }
        return null;
    }

    private static bool IsShowing(AutomationElement element)
    {
        try { return !element.Current.IsOffscreen; }
        catch (Exception e) when (e is ElementNotAvailableException or COMException or InvalidOperationException)
        {
            return false;
        }
    }

    private static string? TextOf(AutomationElement element)
    {
        try
        {
            if (!element.TryGetCurrentPattern(TextPattern.Pattern, out var pattern)) return null;
            // Images and form controls arrive as an object-replacement character.
            var text = ((TextPattern)pattern).DocumentRange
                .GetText(MaxCharacters)
                .Replace('\uFFFC', ' ');
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (Exception e) when (e is ElementNotAvailableException or COMException or InvalidOperationException)
        {
            return null;
        }
    }
}

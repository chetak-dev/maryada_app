using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace GuardNest.Agent;

/// <summary>
/// Reads the address bar of the foreground browser through UI Automation, the
/// Windows counterpart of the accessibility service on Android. DNS filtering
/// alone never sees the path, the query string, or a page reached over a
/// connection that is already open.
/// </summary>
internal sealed class BrowserUrlReader
{
    /// Walking a browser's tree costs hundreds of milliseconds; the element is
    /// resolved once per window and reused, which brings it under 2ms.
    private readonly Dictionary<IntPtr, AutomationElement> _cache = new();

    public static bool IsBrowser(string executableKey) => Core.Apps.Browsers.IsBrowser(executableKey);

    public string Read(IntPtr window, string executableKey)
    {
        try
        {
            if (_cache.TryGetValue(window, out var cached))
            {
                var value = ValueOf(cached);
                if (value is not null) return value;
                _cache.Remove(window);
            }

            var root = AutomationElement.FromHandle(window);
            if (root is null) return "";

            var element = Locate(root, executableKey);
            if (element is null) return "";
            _cache[window] = element;
            return ValueOf(element) ?? "";
        }
        catch (Exception e) when (e is ElementNotAvailableException or COMException or InvalidOperationException)
        {
            // The tab or window closed mid-read; nothing to report this tick.
            _cache.Remove(window);
            return "";
        }
    }

    private static AutomationElement? Locate(AutomationElement root, string executableKey)
    {
        if (Core.Apps.Browsers.IsGecko(executableKey))
        {
            var byId = root.FindFirst(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.AutomationIdProperty, "urlbar-input"));
            if (byId is not null) return byId;
        }

        // Chromium exposes the omnibox as the window's only Edit supporting
        // ValuePattern; matching the name ("Address and search bar") would break
        // on a non-English Windows.
        return root.FindFirst(
            TreeScope.Descendants,
            new AndCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit),
                new PropertyCondition(AutomationElement.IsValuePatternAvailableProperty, true)));
    }

    private static string? ValueOf(AutomationElement element)
    {
        if (!element.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern)) return null;
        var value = ((ValuePattern)pattern).Current.Value;
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }
}

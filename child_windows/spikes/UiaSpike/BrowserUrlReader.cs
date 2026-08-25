using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace GuardNest.Windows.Spikes.Uia;

/// <summary>
/// Reads the address bar of the foreground browser through UI Automation — the
/// Windows equivalent of the accessibility service the Android child app uses
/// to see URLs. Network filtering alone cannot do this: it never sees the path,
/// the query string, or a page reached over an already-open connection.
/// </summary>
internal sealed class BrowserUrlReader
{
    /// Walking the whole tree of a browser costs tens of milliseconds, so the
    /// address-bar element is resolved once per window and reused.
    private readonly Dictionary<IntPtr, AutomationElement> _cache = new();

    public static bool IsBrowser(string processName) => processName.ToLowerInvariant() switch
    {
        "chrome" or "msedge" or "firefox" or "brave" or "opera" or "opera_gx"
            or "vivaldi" or "iexplore" => true,
        _ => false,
    };

    public string Read(IntPtr hWnd, string processName, out bool cacheHit)
    {
        cacheHit = false;
        try
        {
            if (_cache.TryGetValue(hWnd, out var cached))
            {
                var value = ValueOf(cached);
                if (value is not null)
                {
                    cacheHit = true;
                    return value;
                }
                _cache.Remove(hWnd);
            }

            var root = AutomationElement.FromHandle(hWnd);
            if (root is null) return "";

            var element = Locate(root, processName);
            if (element is null) return "";
            _cache[hWnd] = element;
            return ValueOf(element) ?? "";
        }
        catch (ElementNotAvailableException)
        {
            // The tab or window closed mid-read; nothing to report this tick.
            _cache.Remove(hWnd);
            return "";
        }
        catch (COMException)
        {
            _cache.Remove(hWnd);
            return "";
        }
    }

    private static AutomationElement? Locate(AutomationElement root, string processName)
    {
        if (processName.Equals("firefox", StringComparison.OrdinalIgnoreCase))
        {
            var byId = root.FindFirst(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.AutomationIdProperty, "urlbar-input"));
            if (byId is not null) return byId;
        }

        // Chromium exposes the omnibox as the window's only enabled Edit that
        // supports ValuePattern; matching on the localised name ("Address and
        // search bar") would break on a non-English Windows.
        return root.FindFirst(
            TreeScope.Descendants,
            new AndCondition(
                new PropertyCondition(
                    AutomationElement.ControlTypeProperty, ControlType.Edit),
                new PropertyCondition(
                    AutomationElement.IsValuePatternAvailableProperty, true)));
    }

    private static string? ValueOf(AutomationElement element)
    {
        if (!element.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern)) return null;
        return ((ValuePattern)pattern).Current.Value;
    }
}

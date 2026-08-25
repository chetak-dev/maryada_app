namespace GuardNest.Core.Web;

/// <summary>Host matching that treats a domain as covering its subdomains.</summary>
public static class Domains
{
    /// <summary>Strips scheme noise and the www/m prefixes so lists match.</summary>
    public static string Normalize(string host)
    {
        var value = host.Trim().ToLowerInvariant();
        if (value.Length == 0) return "";
        if (value.StartsWith("www.")) value = value[4..];
        else if (value.StartsWith("m.")) value = value[2..];
        return value.TrimEnd('.');
    }

    /// <summary>True when <paramref name="host"/> is <paramref name="domain"/> or below it.</summary>
    public static bool Covers(string domain, string host) =>
        host == domain || host.EndsWith("." + domain, StringComparison.Ordinal);

    public static bool MatchesAny(string host, IReadOnlyCollection<string> domains)
    {
        if (domains.Count == 0 || host.Length == 0) return false;
        // Walking up the labels is O(labels) instead of O(list), which matters
        // when a category feed holds tens of thousands of domains.
        var candidate = host;
        while (candidate.Length > 0)
        {
            if (domains.Contains(candidate)) return true;
            var dot = candidate.IndexOf('.');
            if (dot < 0) return false;
            candidate = candidate[(dot + 1)..];
        }
        return false;
    }

    /// <summary>The host part of an address the browser showed, or "".</summary>
    public static string HostOf(string address)
    {
        var value = address.Trim();
        if (value.Length == 0) return "";
        // Chrome and Firefox drop the scheme from the omnibox; Edge keeps it.
        if (!value.Contains("://")) value = "https://" + value;
        return Uri.TryCreate(value, UriKind.Absolute, out var uri) ? Normalize(uri.Host) : "";
    }
}

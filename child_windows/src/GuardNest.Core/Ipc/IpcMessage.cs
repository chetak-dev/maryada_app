using System.Text.Json;
using System.Text.Json.Serialization;

namespace GuardNest.Core.Ipc;

/// <summary>What the session agent needs to draw: the current enforcement state.</summary>
public sealed class AgentState
{
    public bool Paired { get; set; }

    /// Local pairing exists but Firestore has not confirmed it for this run.
    public bool PairingPending { get; set; }

    public bool Locked { get; set; }
    public string DeviceName { get; set; } = "";
    public string FamilyName { get; set; } = "";
    public string VersionLabel { get; set; } = AppConfig.VersionLabel;
    public string Status { get; set; } = "";

    public OverlayKind Overlay { get; set; }
    public string OverlayTitle { get; set; } = "";
    public string OverlaySubtitle { get; set; } = "";
    public string OverlayDetail { get; set; } = "";

    /// A screen-time lock has no way out; a blocked site or app does.
    public bool OverlayDismissible { get; set; }

    /// Zero means it stays until the service says otherwise.
    public int OverlayAutoHideSeconds { get; set; }
}

/// <summary>What the agent saw in front of the child on one sample.</summary>
public sealed record ForegroundReport(
    string Executable,
    string Title,
    string Url,
    string PageText,
    int IdleSeconds);

/// <summary>
/// One line of the agent protocol. A single shape with optional fields keeps the
/// pipe readable and avoids polymorphic serialisation.
/// </summary>
public sealed class IpcMessage
{
    public const string Hello = "hello";
    public const string Foreground = "foreground";
    public const string Chat = "chat";
    public const string Apps = "apps";
    public const string OverlayDismissed = "overlayDismissed";
    public const string Pair = "pair";
    public const string PairResult = "pairResult";
    public const string State = "state";

    public string Type { get; set; } = "";
    public string? Text { get; set; }
    public string? Executable { get; set; }
    public string? Title { get; set; }

    /// Which overlay was dismissed, encoded as its enum integer.
    public int OverlayKind { get; set; }

    /// The address bar, when the foreground window is a browser.
    public string? Url { get; set; }

    /// The text the page has rendered, read only for a real page that is not a
    /// search results list.
    public string? PageText { get; set; }

    /// Windows session that owns the interactive agent.
    public int SessionId { get; set; }

    public int IdleSeconds { get; set; }
    public bool Ok { get; set; }
    public AgentState? Payload { get; set; }

    /// One pass over an open conversation, in the order the rows appeared.
    public List<Chat.ChatSighting>? Chats { get; set; }

    /// What is installed for the logged-in child, which only their own session
    /// can see.
    public List<GuardNest.Core.Apps.InstalledApp>? InstalledApps { get; set; }

    [JsonIgnore]
    public static JsonSerializerOptions Json { get; } = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}

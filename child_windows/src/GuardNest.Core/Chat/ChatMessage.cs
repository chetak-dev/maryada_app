namespace GuardNest.Core.Chat;

/// <summary>One captured chat message, ready to upload.</summary>
public sealed record ChatMessage(
    string App,
    string Sender,
    string Text,
    long At,
    bool Outgoing,
    string TimeLabel,
    string Number,
    long DayStart,
    int Slot,
    /// Deterministic id material for this message's document.
    string DocKey,
    /// Id material of the document this one supersedes, blank if none.
    string Replaces);

/// <summary>One sighting of a message on screen, before identity is resolved.</summary>
public sealed record ChatSighting(
    string App,
    string Sender,
    string Text,
    /// Null when the row genuinely did not say which side it is on. Never guessed.
    bool? Outgoing,
    string TimeLabel = "",
    string Number = "",
    long DayStart = 0,
    /// How many times this exact text already appeared in the same scan.
    int Occurrence = 0);

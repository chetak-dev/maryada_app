namespace GuardNest.Setup;

public sealed record SetupProgress(string Status, double Percent);

public sealed record SetupResult(
    bool Success,
    string Title,
    string Message,
    bool PairingRequired = false)
{
    public static SetupResult Installed(bool linked, string familyName) => linked
        ? new(
            true,
            "Maryada is installed and linked",
            familyName.Length > 0
                ? $"This PC remains connected to {familyName}. Protection is running."
                : "This PC remains connected to its family. Protection is running.")
        : new(
            true,
            "Maryada is installed, but not connected",
            "Open Maryada in the child's Windows account and enter a pairing code from the parent app. Installation alone does not connect this PC to any parent.");

    public static SetupResult Removed() => new(
        true,
        "Maryada is removed",
        "Protection has been removed from this PC. A final setup file may disappear after Windows restarts.");

    public static SetupResult Failed(string message) => new(
        false,
        "Setup could not finish",
        message);

    /// <summary>Removal refused because the parent still owns this PC.</summary>
    public static SetupResult RemovalBlocked(string familyName) => new(
        false,
        "This PC is still linked",
        familyName.Length > 0
            ? $"Maryada is still connected to {familyName}. Ask a parent to remove this PC in the Maryada app, then choose Check again."
            : "Maryada is still connected to a parent. Ask a parent to remove this PC in the Maryada app, then choose Check again.");

    public static SetupResult PairingFailed(string message) => new(
        false,
        "Connect this PC to a parent",
        message,
        PairingRequired: true);

    /// <summary>The parent's records were unreachable, so removal cannot be justified.</summary>
    public static SetupResult RemovalUnconfirmed(string familyName) => new(
        false,
        "Couldn't check with the parent app",
        familyName.Length > 0
            ? $"This PC still shows as connected to {familyName}, and the parent's records could not be reached. Check the internet connection, then choose Check again."
            : "This PC still shows as connected to a parent, and those records could not be reached. Check the internet connection, then choose Check again.");
}
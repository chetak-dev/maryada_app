namespace GuardNest.Core.Ipc;

/// <summary>What the agent should be showing, decided entirely by the service.</summary>
public enum OverlayKind
{
    None = 0,

    /// Screen time: paused, bedtime or the daily limit. Stays until it lifts.
    Lock = 1,

    /// A refused website. Stays while the child is still looking at it.
    Site = 2,

    /// A blocked app that was just closed. Says its piece and goes away.
    App = 3,
}

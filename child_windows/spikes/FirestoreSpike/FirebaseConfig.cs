namespace GuardNest.Windows.Spikes.Firestore;

/// <summary>
/// The same Firebase project the Android child app and the parent app use.
/// These are public client identifiers (they ship inside every mobile build and
/// the web bundle); access is controlled by firestore.rules, not by hiding them.
/// </summary>
internal static class FirebaseConfig
{
    public const string ProjectId = "guardnest-1ec2c";

    /// Web API key from parent_app/lib/firebase_options.dart.
    public const string ApiKey = "AIzaSyASJIA4PM0kQHy2MWEnaQdhejTqdQuRMw4";
}

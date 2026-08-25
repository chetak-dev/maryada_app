using System.Net;

namespace GuardNest.Core.Firebase;

/// <summary>
/// A Firestore call that the server refused. <see cref="PermissionDenied"/> is
/// the one the agent acts on: it means the rules rejected this device, which
/// after pairing can only mean the parent removed it.
/// </summary>
public sealed class FirestoreException : Exception
{
    public FirestoreException(HttpStatusCode status, string operation, string body)
        : base($"{operation} failed with {(int)status}: {Shorten(body)}")
    {
        Status = status;
        Body = body;
    }

    public HttpStatusCode Status { get; }
    public string Body { get; }

    public bool PermissionDenied => Status == HttpStatusCode.Forbidden;

    private static string Shorten(string body) =>
        body.Length <= 300 ? body.ReplaceLineEndings(" ") : body[..300].ReplaceLineEndings(" ") + "…";
}

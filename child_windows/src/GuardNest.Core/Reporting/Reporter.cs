using System.Security.Cryptography;
using GuardNest.Core.Firebase;

namespace GuardNest.Core.Reporting;

/// <summary>
/// Everything this device tells the parent: that it is alive and healthy, what
/// was used, what is installed, and anything worth an alert.
/// </summary>
public sealed class Reporter
{
    private const string IdAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    private readonly FirestoreClient _firestore;
    private readonly AnonymousAuth _auth;

    public Reporter(FirestoreClient firestore, AnonymousAuth auth)
    {
        _firestore = firestore;
        _auth = auth;
    }

    /// <summary>
    /// Tells the parent this device is online and whether monitoring is intact.
    /// Throws <see cref="FirestoreException"/> with PermissionDenied when the
    /// parent has removed this device, which is the caller's cue to unpair.
    /// </summary>
    public async Task HeartbeatAsync(
        DeviceState state,
        IReadOnlyDictionary<string, bool> protections,
        CancellationToken ct)
    {
        var permissionsOk = protections.Values.All(granted => granted);
        var fields = new Dictionary<string, object?>
        {
            ["online"] = true,
            ["protections"] = protections.ToDictionary(e => e.Key, e => (object?)e.Value),
            ["permissionsOk"] = permissionsOk,
            ["appVersionCode"] = AppConfig.VersionCode,
            ["appVersionName"] = AppConfig.VersionName,
            ["appVersionLabel"] = AppConfig.VersionLabel,
        };

        var error = Diag.Last();
        // A merge write leaves old fields in place, so a resolved error has to
        // be cleared explicitly or it stays on the parent's screen forever.
        fields["lastError"] = error?.Message;
        fields["lastErrorAt"] = error?.At;

        var deviceRecord = new Dictionary<string, object?>(fields)
        {
            ["platform"] = AppConfig.Platform,
            ["deviceUid"] = _auth.Uid,
            ["deviceModel"] = DeviceState.DeviceModel(),
            ["osVersion"] = SystemInfo.WindowsEdition(),
            ["capabilities"] = DeviceCapabilities.AsMap(),
        };
        if (state.DeviceName.Length > 0) deviceRecord["displayName"] = state.DeviceName;

        // This device's own copy, under its uid, so a profile can hold several
        // devices without them overwriting each other's state. Masking each leaf
        // keeps one heartbeat to one write and leaves `pairedAt`/`revoked` alone.
        var slot = $"devices.`{_auth.Uid}`";
        var mask = fields.Keys.Concat(deviceRecord.Keys.Select(k => $"{slot}.{k}")).ToList();
        mask.Add($"{slot}.lastSeenAt");
        fields["devices"] = new Dictionary<string, object?> { [_auth.Uid] = deviceRecord };

        await _firestore.MergeAsync(
            $"families/{state.FamilyId}/children/{state.ChildId}",
            fields, ct,
            serverTimestamps: new[] { "lastSeenAt", $"{slot}.lastSeenAt" },
            maskPaths: mask);

        // Reaching Firestore proves the device is healthy, so whatever it just
        // reported is history.
        if (error is not null) Diag.ClearResolved(error.Value.At);
    }

    public async Task ReportInstalledAppsAsync(
        DeviceState state, IReadOnlyList<Apps.InstalledApp> apps, CancellationToken ct)
    {        if (apps.Count == 0) return;
        var payload = new Dictionary<string, object?>
        {
            ["apps"] = apps.Select(app => (object?)new Dictionary<string, object?>
            {
                ["packageName"] = app.Key,
                ["appName"] = app.Name,
            }).ToList(),
            ["count"] = apps.Count,
            ["platform"] = AppConfig.Platform,
            ["deviceUid"] = _auth.Uid,
        };
        await _firestore.MergeAsync(
            $"families/{state.FamilyId}/children/{state.ChildId}/reports/installedApps-{_auth.Uid}",
            payload, ct, serverTimestamps: new[] { "updatedAt" });
    }

    public async Task AlertAsync(DeviceState state, string type, string detail, CancellationToken ct)    {
        var fields = new Dictionary<string, object?>
        {
            ["type"] = type,
            ["detail"] = detail,
            ["childId"] = state.ChildId,
            ["deviceName"] = state.DeviceName.Length > 0 ? state.DeviceName : DeviceState.DeviceModel(),
            ["platform"] = AppConfig.Platform,
        };
        await _firestore.MergeAsync(
            $"families/{state.FamilyId}/alerts/{NewId()}", fields, ct,
            serverTimestamps: new[] { "at" });
    }

    /// <summary>
    /// Browsing goes to this device's own report document. Every device keeps a
    /// separate one, keyed by uid, so a phone and a PC on the same profile do
    /// not overwrite each other's history.
    /// </summary>
    public Task ReportWebHistoryAsync(
        DeviceState state, IReadOnlyDictionary<string, object?> snapshot, CancellationToken ct)
    {
        var payload = new Dictionary<string, object?>(snapshot) { ["deviceUid"] = _auth.Uid };
        return _firestore.MergeAsync(
            $"families/{state.FamilyId}/children/{state.ChildId}/webHistory/{_auth.Uid}",
            payload, ct, serverTimestamps: new[] { "updatedAt" });
    }

    /// <summary>Watch history goes to this device's own report document.</summary>
    public Task ReportYoutubeAsync(
        DeviceState state, IReadOnlyDictionary<string, object?> snapshot, CancellationToken ct)
    {
        var payload = new Dictionary<string, object?>(snapshot) { ["deviceUid"] = _auth.Uid };
        return _firestore.MergeAsync(
            $"families/{state.FamilyId}/children/{state.ChildId}/youtubeHistory/{_auth.Uid}",
            payload, ct, serverTimestamps: new[] { "updatedAt" });
    }

    /// <summary>Firestore's own id shape, since REST has no auto-id create.</summary>
    private static string NewId()
    {
        Span<char> id = stackalloc char[20];
        for (var i = 0; i < id.Length; i++)
        {
            id[i] = IdAlphabet[RandomNumberGenerator.GetInt32(IdAlphabet.Length)];
        }
        return new string(id);
    }
}

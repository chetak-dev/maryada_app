using GuardNest.Core.Firebase;

namespace GuardNest.Core;

/// <summary>A pairing attempt the child can act on ("that code has expired").</summary>
public sealed class PairingException : Exception
{
    public PairingException(string message) : base(message) { }
}

/// <summary>Validated pairing-code data; validation itself performs no writes.</summary>
public sealed record PairingCodeInfo(
    string Code,
    string FamilyId,
    string ChildId,
    string DeviceName,
    string FamilyName);

/// <summary>
/// The child-side handshake, mirroring Pairing.kt: redeem a one-time code, bind
/// this device's anonymous uid to the profile, then register it so the security
/// rules know which family's settings this device may read.
/// </summary>
public sealed class PairingService
{
    private readonly FirestoreClient _firestore;
    private readonly AnonymousAuth _auth;

    public PairingService(FirestoreClient firestore, AnonymousAuth auth)
    {
        _firestore = firestore;
        _auth = auth;
    }

    public async Task<DeviceState> RedeemAsync(string rawCode, CancellationToken ct)
    {
        var validated = await ValidateAsync(rawCode, ct);
        var code = validated.Code;
        var familyId = validated.FamilyId;
        var childId = validated.ChildId;
        var deviceName = validated.DeviceName;
        var uid = _auth.Uid;
        var model = DeviceState.DeviceModel();

        // Order matters and these cannot be batched: the rules only let this
        // device register once the child doc already names it as `deviceUid`,
        // and a batch is evaluated against the state before the batch.
        await _firestore.MergeAsync(
            $"families/{familyId}/children/{childId}",
            new Dictionary<string, object?>
            {
                ["paired"] = true,
                ["deviceModel"] = model,
                ["deviceUid"] = uid,
                ["pairingCode"] = code,
                ["online"] = true,
                ["setupComplete"] = true,
                ["permissionsOk"] = true,
            },
            ct,
            serverTimestamps: new[] { "pairedAt", "lastSeenAt" });

        await _firestore.MergeAsync(
            $"families/{familyId}/children/{childId}/devices/{uid}",
            new Dictionary<string, object?>
            {
                ["deviceUid"] = uid,
                ["deviceModel"] = model,
                ["displayName"] = deviceName,
                ["platform"] = AppConfig.Platform,
                ["revoked"] = false,
                ["capabilities"] = DeviceCapabilities.AsMap(),
            },
            ct,
            serverTimestamps: new[] { "pairedAt" });

        await RegisterDeviceAsync(familyId, childId, ct);

        try
        {
            await _firestore.MergeAsync(
                $"pairingCodes/{code}",
                new Dictionary<string, object?> { ["used"] = true },
                ct,
                serverTimestamps: new[] { "usedAt" });
        }
        catch (FirestoreException e)
        {
            // The device is already bound; leaving the code unspent beats
            // failing a pairing that actually worked.
            Diag.Warn("pair.markCodeUsed", e);
        }

        var state = new DeviceState
        {
            FamilyId = familyId,
            ChildId = childId,
            DeviceName = deviceName,
            FamilyName = validated.FamilyName,
            PairedAt = DateTimeOffset.UtcNow,
        };
        state.Save();
        return state;
    }

    /// <summary>
    /// Confirms a code before installation changes the PC. This only reads the
    /// exact pairing-code document and never claims the child or burns the code.
    /// </summary>
    public async Task<PairingCodeInfo> ValidateAsync(string rawCode, CancellationToken ct)
    {
        var code = rawCode.Trim().ToUpperInvariant();
        if (code.Length != 6) throw new PairingException("Enter the 6-character code.");

        await EnsureIdentityAsync(ct);
        var snapshot = await _firestore.GetAsync($"pairingCodes/{code}", ct)
                       ?? throw new PairingException("That code isn't valid.");
        if (snapshot.GetBool("used")) throw new PairingException("That code has already been used.");

        var expiresAt = snapshot.GetTimestamp("expiresAt");
        if (expiresAt is not null && expiresAt < DateTimeOffset.UtcNow)
        {
            throw new PairingException("That code has expired. Ask for a new one.");
        }

        return new PairingCodeInfo(
            code,
            snapshot.GetString("familyId")
                ?? throw new PairingException("Code is missing its family."),
            snapshot.GetString("childId")
                ?? throw new PairingException("Code is missing its child."),
            snapshot.GetString("deviceName")?.Trim() ?? "",
            snapshot.GetString("familyName")?.Trim() ?? "");
    }

    /// <summary>
    /// Writes `devices/{uid}`, which is what the rules read to decide whose
    /// settings this anonymous device may see. Retried from the enforcement loop
    /// because a device that fails this can still be paired.
    /// </summary>
    public async Task<bool> RegisterDeviceAsync(string familyId, string childId, CancellationToken ct)
    {
        try
        {
            await _firestore.MergeAsync(
                $"devices/{_auth.Uid}",
                new Dictionary<string, object?>
                {
                    ["familyId"] = familyId,
                    ["childId"] = childId,
                },
                ct,
                serverTimestamps: new[] { "pairedAt" });
            return true;
        }
        catch (FirestoreException e)
        {
            Diag.Warn("pair.registerDevice", e);
            return false;
        }
    }

    private async Task<string> EnsureIdentityAsync(CancellationToken ct)
    {
        await _auth.GetIdTokenAsync(ct);
        if (_auth.Uid.Length == 0) throw new PairingException("Couldn't sign in. Check the connection.");
        return _auth.Uid;
    }
}

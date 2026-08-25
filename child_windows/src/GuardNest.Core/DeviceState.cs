using System.Text.Json;

namespace GuardNest.Core;

/// <summary>
/// This installation's pairing, mirroring ChildStore on Android. Separate from
/// the token file because none of it is secret — it just says which family and
/// profile this PC belongs to.
/// </summary>
public sealed class DeviceState
{
    public string FamilyId { get; set; } = "";
    public string ChildId { get; set; } = "";
    public string DeviceName { get; set; } = "";
    public string FamilyName { get; set; } = "";
    public DateTimeOffset? PairedAt { get; set; }

    public bool IsPaired => FamilyId.Length > 0 && ChildId.Length > 0;

    private static string Path => DataFolder.Path("device.json");

    public static DeviceState Load()
    {
        try
        {
            if (!File.Exists(Path)) return new DeviceState();
            return JsonSerializer.Deserialize<DeviceState>(File.ReadAllText(Path)) ?? new DeviceState();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            return new DeviceState();
        }
    }

    public void Save()
    {
        try { File.WriteAllText(Path, JsonSerializer.Serialize(this)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Diag.Warn("deviceState.save", e);
        }
    }

    public void Clear()
    {
        FamilyId = "";
        ChildId = "";
        DeviceName = "";
        FamilyName = "";
        PairedAt = null;
        try { File.Delete(Path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>What the parent sees as the device model: the PC itself.</summary>
    public static string DeviceModel()
    {
        var manufacturer = SystemInfo.Manufacturer();
        var model = SystemInfo.Model();
        if (manufacturer.Length == 0 && model.Length == 0) return Environment.MachineName;
        return $"{manufacturer} {model}".Trim();
    }
}

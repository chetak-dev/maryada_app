using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using GuardNest.Core;
using GuardNest.Core.Networking;
using Microsoft.Win32;

namespace GuardNest.Setup;

public sealed class InstallationEngine
{
    private const string ServiceName = "GuardNest";
    private const string DisplayName = "Maryada Protection";
    private const int MoveFileDelayUntilReboot = 0x4;

    private static readonly string InstallDirectory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Maryada");
    private static readonly string DataDirectory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GuardNest");

    /// One binary is the service, the agent and this wizard; the role comes
    /// from the command line, which is what keeps the download small.
    private static readonly string ProgramPath = Path.Combine(InstallDirectory, "Maryada.exe");
    private static readonly string PolicyBackupPath = Path.Combine(DataDirectory, "policy-backup.json");

    private static readonly PolicySetting[] Policies =
    [
        new(@"SOFTWARE\Policies\Google\Chrome", "DnsOverHttpsMode", "off", RegistryValueKind.String),
        new(@"SOFTWARE\Policies\Microsoft\Edge", "DnsOverHttpsMode", "off", RegistryValueKind.String),
        new(@"SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS", "Enabled", 0, RegistryValueKind.DWord),
        new(@"SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS", "Locked", 1, RegistryValueKind.DWord),
        new(@"SYSTEM\CurrentControlSet\Services\Dnscache\Parameters", "EnableAutoDoh", 0, RegistryValueKind.DWord),
    ];

    public bool IsInstalled => File.Exists(ProgramPath) && ServiceExists();

    public LinkState CurrentLink => ReadLink();

    public Task<SetupResult> InstallAsync(IProgress<SetupProgress>? progress) =>
        Task.Run(() => Install(progress));

    public Task<SetupResult> InstallAndPairAsync(
        string code,
        IProgress<SetupProgress>? progress,
        CancellationToken ct = default) =>
        Task.Run(() => InstallAndPair(code, progress, ct), ct);

    public Task<SetupResult> UninstallAsync(IProgress<SetupProgress>? progress) =>
        Task.Run(() => Uninstall(progress));

    private SetupResult Install(IProgress<SetupProgress>? progress)
    {
        try
        {
            InstallCore(progress);
            var link = ReadLink();
            if (!link.IsLinked)
            {
                return SetupResult.PairingFailed(
                    "A pairing code is required before setup can finish.");
            }
            Report(progress, "Installation complete", 100);
            return SetupResult.Installed(true, link.FamilyName);
        }
        catch (Exception error)
        {
            return SetupResult.Failed(error.Message);
        }
    }

    private SetupResult InstallAndPair(
        string code,
        IProgress<SetupProgress>? progress,
        CancellationToken ct)
    {
        try
        {
            InstallCore(progress);

            Report(progress, "Connecting this PC to the parent…", 94);
            var pairing = ServicePairingClient.PairAsync(code, ct)
                .GetAwaiter()
                .GetResult();
            if (!pairing.Ok)
            {
                return SetupResult.PairingFailed(pairing.Message);
            }

            var link = ReadLink();
            if (!link.IsLinked)
            {
                return SetupResult.PairingFailed(
                    "The pairing response was received, but the local link was not saved. Try again.");
            }

            Report(progress, "Installation and pairing complete", 100);
            return SetupResult.Installed(true, link.FamilyName);
        }
        catch (Exception error)
        {
            return SetupResult.Failed(error.Message);
        }
    }

    private static void InstallCore(IProgress<SetupProgress>? progress)
    {
        EnsureAdministrator();
        EnsurePayload();

        Report(progress, "Stopping the previous version…", 8);
        StopService();
        StopAgents();

        Report(progress, "Preserving network settings…", 18);
        Directory.CreateDirectory(DataDirectory);
        DnsBackupStore.CaptureIfMissing();
        DnsBackupStore.Restore();
        CapturePolicyBackup();

        Report(progress, "Installing protected files…", 32);
        Directory.CreateDirectory(InstallDirectory);
        RemoveLegacyPayloadFolders();
        InstallProgram();
        SecureInstallDirectory();
        SecureDataDirectory();

        Report(progress, "Registering the protection service…", 56);
        RegisterService();
        RegisterAgentStartup();

        Report(progress, "Applying safe-browsing policies…", 72);
        ApplyDohPolicies();
        RegisterUninstall();
        RegisterStartMenuShortcuts();

        Report(progress, "Starting protection…", 88);
        RunSc(["start", ServiceName], [0, 1056]);
        WaitForServiceRunning();
    }

    private SetupResult Uninstall(IProgress<SetupProgress>? progress)
    {
        try
        {
            EnsureAdministrator();
            var linked = ReadLink();
            if (linked.FamilyId.Length > 0)
            {
                // The local file lags behind the parent's decision, so ask the
                // family's records before refusing.
                Report(progress, "Checking with the parent app…", 8);
                var status = RemovalCheck.ConfirmAsync().GetAwaiter().GetResult();
                if (status != RemovalCheck.LinkStatus.Removed)
                {
                    return status == RemovalCheck.LinkStatus.Unknown
                        ? SetupResult.RemovalUnconfirmed(linked.FamilyName)
                        : SetupResult.RemovalBlocked(linked.FamilyName);
                }
            }

            Report(progress, "Stopping protection…", 15);
            StopService();
            StopAgents();

            Report(progress, "Restoring network settings…", 34);
            DnsBackupStore.Restore();
            RestoreAdaptersStillRedirected();
            RestoreDohPolicies();

            Report(progress, "Removing Windows registrations…", 55);
            RunSc(["delete", ServiceName], [0, 1060]);
            RemoveAgentStartup();
            RemoveUninstallRegistration();
            RemoveStartMenuShortcuts();

            Report(progress, "Removing protected files…", 78);
            DnsBackupStore.Delete();
            DeleteDirectory(DataDirectory);
            DeleteInstalledFiles();

            Report(progress, "Removal complete", 100);
            return SetupResult.Removed();
        }
        catch (Exception error)
        {
            return SetupResult.Failed(error.Message);
        }
    }

    private static void EnsureAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
        {
            throw new InvalidOperationException("Administrator approval is required to protect this PC.");
        }
    }

    private static void EnsurePayload()
    {
        if (Environment.ProcessPath is null)
        {
            throw new InvalidOperationException("Setup cannot locate its own program file.");
        }
    }

    /// <summary>
    /// Puts this very executable in Program Files. It then serves as the
    /// service, the agent and the uninstaller.
    /// </summary>
    private static void InstallProgram()
    {
        var current = Environment.ProcessPath
            ?? throw new InvalidOperationException("Setup cannot locate its own program file.");
        if (Path.GetFullPath(current).Equals(Path.GetFullPath(ProgramPath), StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var staged = ProgramPath + ".new";
        File.Copy(current, staged, overwrite: true);
        File.Move(staged, ProgramPath, overwrite: true);
    }

    private static void RemoveLegacyPayloadFolders()
    {
        foreach (var name in new[] { "service", "agent" })
        {
            DeleteDirectory(Path.Combine(InstallDirectory, name));
        }
        // Earlier builds shipped three programs; a repair install replaces them
        // with the single shared one.
        foreach (var legacy in new[]
                 {
                     "GuardNest.Service.exe", "GuardNest.Agent.exe", "Maryada.Setup.exe",
                     "Install-GuardNest.ps1", "Uninstall-GuardNest.ps1",
                 })
        {
            var path = Path.Combine(InstallDirectory, legacy);
            try { if (File.Exists(path)) File.Delete(path); }
            catch (IOException) { MoveFileEx(path, null, MoveFileDelayUntilReboot); }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static void RegisterService()
    {
        // sc.exe takes the whole "program plus arguments" as one value, so the
        // executable is quoted inside it; passing --service as its own token
        // makes sc print its usage instead of creating the service.
        var binPath = $"{Quote(ProgramPath)} --service";
        var command = ServiceExists() ? "config" : "create";
        RunSc(
            [command, ServiceName, "binPath=", binPath, "start=", "auto", "DisplayName=", DisplayName],
            [0]);
        RunSc(["description", ServiceName, "Keeps this PC protected by Maryada family safety."], [0]);
        RunSc(["failure", ServiceName, "reset=", "0", "actions=", "restart/5000/restart/5000/restart/60000"], [0]);
        RunSc(["failureflag", ServiceName, "1"], [0]);
    }

    private static void StopService()
    {
        if (!ServiceExists()) return;
        RunSc(["stop", ServiceName], [0, 1062]);
        var deadline = DateTime.UtcNow.AddSeconds(20);
        while (DateTime.UtcNow < deadline)
        {
            var status = RunProcess("sc.exe", $"query {ServiceName}", [0, 1060]);
            if (!status.Contains("RUNNING", StringComparison.OrdinalIgnoreCase)
                && !status.Contains("STOP_PENDING", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
            Thread.Sleep(300);
        }
        throw new InvalidOperationException("The existing protection service did not stop.");
    }

    private static void StopAgents()
    {
        // "Maryada" is the shared program running as the agent; the other name
        // is the separate agent that earlier builds installed.
        foreach (var name in new[] { "Maryada", "GuardNest.Agent" })
        {
            foreach (var process in Process.GetProcessesByName(name))
            {
                using (process)
                {
                    if (process.Id == Environment.ProcessId) continue;
                    try { process.Kill(entireProcessTree: true); }
                    catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception) { }
                }
            }
        }
    }

    private static bool ServiceExists()
    {
        using var key = Registry.LocalMachine.OpenSubKey($@"SYSTEM\CurrentControlSet\Services\{ServiceName}");
        return key is not null;
    }

    private static void WaitForServiceRunning()
    {
        var deadline = DateTime.UtcNow.AddSeconds(20);
        while (DateTime.UtcNow < deadline)
        {
            var status = RunProcess("sc.exe", $"query {ServiceName}", [0]);
            if (status.Contains("RUNNING", StringComparison.OrdinalIgnoreCase)) return;
            Thread.Sleep(300);
        }
        throw new InvalidOperationException("Maryada was installed, but its protection service did not start.");
    }

    private static void RegisterAgentStartup()
    {
        using var key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run");
        key?.SetValue("Maryada", $"{Quote(ProgramPath)} --agent", RegistryValueKind.String);
    }

    private static void RemoveAgentStartup()
    {
        using var key = Registry.LocalMachine.OpenSubKey(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            writable: true);
        key?.DeleteValue("Maryada", throwOnMissingValue: false);
    }

    private static void CapturePolicyBackup()
    {
        if (File.Exists(PolicyBackupPath)) return;

        var backup = new List<PolicyBackup>();
        foreach (var policy in Policies)
        {
            using var key = Registry.LocalMachine.OpenSubKey(policy.Path);
            var value = key?.GetValue(policy.Name);
            var kind = value is null ? null : key?.GetValueKind(policy.Name);
            backup.Add(new PolicyBackup(
                policy.Path,
                policy.Name,
                value is not null,
                value?.ToString(),
                kind));
        }
        File.WriteAllText(PolicyBackupPath, JsonSerializer.Serialize(backup));
    }

    private static void ApplyDohPolicies()
    {
        foreach (var policy in Policies)
        {
            using var key = Registry.LocalMachine.CreateSubKey(policy.Path);
            key?.SetValue(policy.Name, policy.Value, policy.Kind);
        }
    }

    private static void RestoreDohPolicies()
    {
        if (!File.Exists(PolicyBackupPath))
        {
            foreach (var policy in Policies) DeleteRegistryValue(policy.Path, policy.Name);
            return;
        }

        List<PolicyBackup>? backup;
        try
        {
            backup = JsonSerializer.Deserialize<List<PolicyBackup>>(File.ReadAllText(PolicyBackupPath));
        }
        catch (JsonException)
        {
            backup = null;
        }

        foreach (var item in backup ?? [])
        {
            if (!item.Existed || item.Kind is null)
            {
                DeleteRegistryValue(item.Path, item.Name);
                continue;
            }
            using var key = Registry.LocalMachine.CreateSubKey(item.Path);
            object value = item.Kind == RegistryValueKind.DWord
                ? int.TryParse(item.Value, out var number) ? number : 0
                : item.Value ?? "";
            key?.SetValue(item.Name, value, item.Kind.Value);
        }
    }

    private static void RegisterUninstall()
    {
        using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        using var key = baseKey.CreateSubKey(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Maryada");
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        key?.SetValue("DisplayName", "Maryada", RegistryValueKind.String);
        key?.SetValue("DisplayVersion", version?.ToString(3) ?? AppConfig.VersionName, RegistryValueKind.String);
        key?.SetValue("VersionMajor", version?.Major ?? 1, RegistryValueKind.DWord);
        key?.SetValue("VersionMinor", version?.Minor ?? 0, RegistryValueKind.DWord);
        key?.SetValue("Publisher", "ISKCON Brahmapur", RegistryValueKind.String);
        key?.SetValue("InstallLocation", InstallDirectory, RegistryValueKind.String);
        key?.SetValue("DisplayIcon", ProgramPath, RegistryValueKind.String);
        key?.SetValue("NoModify", 1, RegistryValueKind.DWord);
        key?.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        key?.SetValue("NoRemove", 0, RegistryValueKind.DWord);
        key?.SetValue("SystemComponent", 0, RegistryValueKind.DWord);
        key?.SetValue("WindowsInstaller", 0, RegistryValueKind.DWord);
        key?.SetValue("InstallDate", DateTime.Today.ToString("yyyyMMdd"), RegistryValueKind.String);
        key?.SetValue("UninstallString", $"{Quote(ProgramPath)} --uninstall", RegistryValueKind.String);
        key?.SetValue("QuietUninstallString", $"{Quote(ProgramPath)} --uninstall --quiet", RegistryValueKind.String);
        key?.SetValue("EstimatedSize", 240_000, RegistryValueKind.DWord);
    }

    private static void RemoveUninstallRegistration()
    {
        using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        baseKey.DeleteSubKeyTree(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Maryada",
            throwOnMissingSubKey: false);
    }

    private static void RegisterStartMenuShortcuts()
    {
        var folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
            "Programs",
            "Maryada");
        Directory.CreateDirectory(folder);
        CreateShortcut(
            Path.Combine(folder, "Open Maryada.lnk"),
            ProgramPath,
            "--agent",
            "Open Maryada family protection");
        CreateShortcut(
            Path.Combine(folder, "Set up or repair Maryada.lnk"),
            ProgramPath,
            "",
            "Pair or repair Maryada family protection");
        CreateShortcut(
            Path.Combine(folder, "Remove Maryada.lnk"),
            ProgramPath,
            "--uninstall",
            "Remove Maryada after the parent unlinks this PC");
    }

    private static void RemoveStartMenuShortcuts()
    {
        var folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
            "Programs",
            "Maryada");
        DeleteDirectory(folder);
    }

    private static void CreateShortcut(
        string path,
        string target,
        string arguments,
        string description)
    {
        var shellType = Type.GetTypeFromProgID("WScript.Shell")
            ?? throw new InvalidOperationException("Windows shortcut support is unavailable.");
        dynamic? shell = null;
        dynamic? shortcut = null;
        try
        {
            shell = Activator.CreateInstance(shellType);
            shortcut = shell!.CreateShortcut(path);
            shortcut.TargetPath = target;
            shortcut.Arguments = arguments;
            shortcut.WorkingDirectory = InstallDirectory;
            shortcut.IconLocation = ProgramPath;
            shortcut.Description = description;
            shortcut.Save();
        }
        finally
        {
            if (shortcut is not null && Marshal.IsComObject(shortcut))
            {
                Marshal.FinalReleaseComObject(shortcut);
            }
            if (shell is not null && Marshal.IsComObject(shell))
            {
                Marshal.FinalReleaseComObject(shell);
            }
        }
    }

    private static void SecureInstallDirectory() => SecureDirectory(InstallDirectory, allowUsersRead: true);

    private static void SecureDataDirectory() => SecureDirectory(DataDirectory, allowUsersRead: false);

    private static void SecureDirectory(string path, bool allowUsersRead)
    {
        var security = new DirectorySecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        AddRule(security, WellKnownSidType.LocalSystemSid, FileSystemRights.FullControl);
        AddRule(security, WellKnownSidType.BuiltinAdministratorsSid, FileSystemRights.FullControl);
        if (allowUsersRead)
        {
            AddRule(
                security,
                WellKnownSidType.BuiltinUsersSid,
                FileSystemRights.ReadAndExecute | FileSystemRights.Synchronize);
        }
        new DirectoryInfo(path).SetAccessControl(security);
    }

    private static void AddRule(
        DirectorySecurity security,
        WellKnownSidType sid,
        FileSystemRights rights)
    {
        security.AddAccessRule(new FileSystemAccessRule(
            new SecurityIdentifier(sid, null),
            rights,
            InheritanceFlags.ObjectInherit | InheritanceFlags.ContainerInherit,
            PropagationFlags.None,
            AccessControlType.Allow));
    }

    private static void RestoreAdaptersStillRedirected()
    {
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
            {
                continue;
            }
            if (adapter.GetIPProperties().DnsAddresses.Any(address => address.Equals(IPAddress.Loopback)))
            {
                RunProcess(
                    "netsh",
                    $"interface ipv4 set dnsservers name={Quote(adapter.Name.Replace("\"", ""))} source=dhcp",
                    [0]);
            }
        }
    }

    private static LinkState ReadLink()
    {
        var path = Path.Combine(DataDirectory, "device.json");
        if (!File.Exists(path)) return new LinkState();
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;
            return new LinkState
            {
                FamilyId = ReadString(root, "FamilyId"),
                FamilyName = ReadString(root, "FamilyName"),
            };
        }
        catch (Exception error) when (error is IOException or JsonException)
        {
            throw new InvalidOperationException(
                "The pairing record could not be checked. Repair Maryada before trying to remove it.",
                error);
        }
    }

    private static string ReadString(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) ? value.GetString() ?? "" : "";

    private static void DeleteInstalledFiles()
    {
        if (!Directory.Exists(InstallDirectory)) return;
        var current = Path.GetFullPath(Environment.ProcessPath ?? "");
        foreach (var path in Directory.EnumerateFiles(InstallDirectory, "*", SearchOption.AllDirectories))
        {
            if (Path.GetFullPath(path).Equals(current, StringComparison.OrdinalIgnoreCase)) continue;
            try { File.Delete(path); } catch (IOException) { }
        }
        foreach (var directory in Directory.EnumerateDirectories(InstallDirectory, "*", SearchOption.AllDirectories)
                     .OrderByDescending(value => value.Length))
        {
            try { Directory.Delete(directory); } catch (IOException) { }
        }

        if (current.StartsWith(Path.GetFullPath(InstallDirectory), StringComparison.OrdinalIgnoreCase))
        {
            MoveFileEx(current, null, MoveFileDelayUntilReboot);
            MoveFileEx(InstallDirectory, null, MoveFileDelayUntilReboot);
        }
        else
        {
            DeleteDirectory(InstallDirectory);
        }
    }

    private static void DeleteDirectory(string path)
    {
        try { Directory.Delete(path, recursive: true); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    private static void DeleteRegistryValue(string path, string name)
    {
        using var key = Registry.LocalMachine.OpenSubKey(path, writable: true);
        key?.DeleteValue(name, throwOnMissingValue: false);
    }

    private static void RunSc(string[] arguments, int[] allowedExitCodes) =>
        RunProcess("sc.exe", arguments, allowedExitCodes);

    /// <summary>
    /// Runs a program with each argument passed separately, so Windows quotes
    /// them rather than this code trying to.
    /// </summary>
    private static string RunProcess(
        string fileName,
        IReadOnlyList<string> arguments,
        int[] allowedExitCodes)
    {
        var startInfo = new ProcessStartInfo(fileName)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
        return Run(startInfo, fileName, allowedExitCodes);
    }

    private static string RunProcess(string fileName, string arguments, int[] allowedExitCodes) =>
        Run(
            new ProcessStartInfo(fileName, arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
            fileName,
            allowedExitCodes);

    private static string Run(ProcessStartInfo startInfo, string fileName, int[] allowedExitCodes)
    {
        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Could not start {fileName}.");

        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        if (!process.WaitForExit(30_000))
        {
            try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            throw new InvalidOperationException($"{fileName} did not finish.");
        }
        if (!allowedExitCodes.Contains(process.ExitCode))
        {
            var detail = string.IsNullOrWhiteSpace(error) ? output : error;
            throw new InvalidOperationException(
                $"{fileName} failed ({process.ExitCode}): {detail.Trim()}");
        }
        return output + error;
    }

    private static string Quote(string value) => $"\"{value.Replace("\"", "")}\"";

    private static void Report(IProgress<SetupProgress>? progress, string status, double percent) =>
        progress?.Report(new SetupProgress(status, percent));

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileEx(string existingFile, string? newFile, int flags);

    public sealed class LinkState
    {
        public string FamilyId { get; init; } = "";
        public string FamilyName { get; init; } = "";

        public bool IsLinked => FamilyId.Length > 0;
    }

    private sealed record PolicySetting(
        string Path,
        string Name,
        object Value,
        RegistryValueKind Kind);

    private sealed record PolicyBackup(
        string Path,
        string Name,
        bool Existed,
        string? Value,
        RegistryValueKind? Kind);
}
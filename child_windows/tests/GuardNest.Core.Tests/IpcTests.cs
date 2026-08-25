using System.Text.Json;
using GuardNest.Core.Apps;
using GuardNest.Core.Ipc;

namespace GuardNest.Core.Tests;

public class AgentProtocolTests
{
    [Fact]
    public void An_installed_app_list_survives_the_pipe()
    {
        var message = new IpcMessage
        {
            Type = IpcMessage.Apps,
            InstalledApps = new List<InstalledApp> { new("chrome.exe", "Google Chrome") },
        };

        var line = JsonSerializer.Serialize(message, IpcMessage.Json);
        var parsed = JsonSerializer.Deserialize<IpcMessage>(line, IpcMessage.Json);

        Assert.Equal(IpcMessage.Apps, parsed!.Type);
        var app = Assert.Single(parsed.InstalledApps!);
        Assert.Equal("chrome.exe", app.Key);
        Assert.Equal("Google Chrome", app.Name);
    }

    [Fact]
    public void A_message_without_apps_stays_as_small_as_before()
    {
        var line = JsonSerializer.Serialize(
            new IpcMessage { Type = IpcMessage.Foreground, Executable = "chrome.exe" },
            IpcMessage.Json);

        Assert.DoesNotContain("installedApps", line, StringComparison.OrdinalIgnoreCase);
    }
}

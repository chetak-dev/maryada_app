using System.Runtime.CompilerServices;

namespace GuardNest.Core.Tests;

/// <summary>
/// Points the stores at a scratch folder before anything reads
/// <see cref="AppConfig.DataDirectory"/>, which is resolved once and would
/// otherwise be the real machine-wide folder.
/// </summary>
internal static class TestSetup
{
    [ModuleInitializer]
    public static void Initialize()
    {
        var scratch = Path.Combine(Path.GetTempPath(), "GuardNestTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(scratch);
        Environment.SetEnvironmentVariable("GUARDNEST_DATA", scratch);
    }
}

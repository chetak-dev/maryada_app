using GuardNest.Core;
using GuardNest.Core.Chat;
using GuardNest.Core.Firebase;
using GuardNest.Core.Media;
using GuardNest.Core.Reporting;
using GuardNest.Core.Rules;
using GuardNest.Core.Update;
using GuardNest.Core.Web;
using GuardNest.Service.Dns;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Hosting.WindowsServices;
using Microsoft.Extensions.Logging;

namespace GuardNest.Service;

/// <summary>The protection service, hosted by the shared Maryada executable.</summary>
public static class ServiceEntry
{
    public static async Task RunAsync(string[] args)
    {
        var builder = Host.CreateApplicationBuilder(args);

        builder.Services.AddWindowsService(options => options.ServiceName = ServiceHealth.ServiceName);
        builder.Logging.AddEventLog(settings => settings.SourceName = ServiceHealth.ServiceName);

        builder.Services.AddSingleton(_ => new HttpClient { Timeout = TimeSpan.FromSeconds(30) });
        builder.Services.AddSingleton(sp =>
            new AnonymousAuth(sp.GetRequiredService<HttpClient>(), AppConfig.ApiKey));
        builder.Services.AddSingleton(sp => new FirestoreClient(
            sp.GetRequiredService<HttpClient>(),
            sp.GetRequiredService<AnonymousAuth>(),
            AppConfig.ProjectId));
        builder.Services.AddSingleton(sp => new PairingService(
            sp.GetRequiredService<FirestoreClient>(), sp.GetRequiredService<AnonymousAuth>()));
        builder.Services.AddSingleton(sp => new RuleSync(sp.GetRequiredService<FirestoreClient>()));
        builder.Services.AddSingleton(sp => new CategoryFeed(sp.GetRequiredService<HttpClient>()));
        builder.Services.AddSingleton(sp => new WebFilter(sp.GetRequiredService<CategoryFeed>()));
        builder.Services.AddSingleton<WebActivity>();
        builder.Services.AddSingleton(sp => new WebPolicySync(
            sp.GetRequiredService<FirestoreClient>(),
            sp.GetRequiredService<WebFilter>(),
            sp.GetRequiredService<CategoryFeed>()));
        builder.Services.AddSingleton(sp => new Reporter(
            sp.GetRequiredService<FirestoreClient>(), sp.GetRequiredService<AnonymousAuth>()));
        builder.Services.AddSingleton<MessageStore>();
        builder.Services.AddSingleton(sp => new ChatReporter(
            sp.GetRequiredService<FirestoreClient>(), sp.GetRequiredService<AnonymousAuth>()));
        builder.Services.AddSingleton<YoutubeStore>();
        builder.Services.AddSingleton(sp => new AppUpdater(
            sp.GetRequiredService<HttpClient>(), sp.GetRequiredService<FirestoreClient>()));
        builder.Services.AddSingleton<AgentPipeServer>();
        builder.Services.AddSingleton<AgentLauncher>();
        builder.Services.AddHostedService<EnforcementWorker>();
        builder.Services.AddHostedService<DnsFilterService>();

        DataFolder.Prepare();

        var host = builder.Build();
        var log = host.Services.GetRequiredService<ILoggerFactory>().CreateLogger("GuardNest");

        // DNS filtering is only as good as this: a browser using DNS-over-HTTPS
        // never asks Windows, so it would never reach the local resolver.
        // Machine-wide policy is only written by the installed service.
        if (WindowsServiceHelpers.IsWindowsService() && !DohPolicy.Apply(log))
        {
            log.LogWarning("DNS-over-HTTPS is not fully disabled; browsers may bypass web filtering");
        }

        await host.RunAsync();
    }
}

using GuardNest.Core;
using GuardNest.Core.Apps;
using GuardNest.Core.Chat;
using GuardNest.Core.Firebase;
using GuardNest.Core.Ipc;
using GuardNest.Core.Media;
using GuardNest.Core.Reporting;
using GuardNest.Core.Rules;
using GuardNest.Core.Update;
using GuardNest.Core.Web;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Hosting.WindowsServices;
using Microsoft.Extensions.Logging;

namespace GuardNest.Service;

/// <summary>
/// The enforcement loop: keeps the rules current, applies them, and tells the
/// parent this device is alive. Everything is throttled off one short tick so a
/// pause reaches the child in seconds without writing to Firestore constantly.
/// </summary>
public sealed class EnforcementWorker : BackgroundService
{
    private static readonly TimeSpan Tick = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan RuleInterval = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan HeartbeatInterval = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan ReportInterval = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan WebReportInterval = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan ChatReportInterval = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan PersistInterval = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan RegisterRetry = TimeSpan.FromMinutes(5);

    /// Longer than the agent's own reporting gap, so a hiccup does not read as
    /// the child walking away, but short enough that a break stops counting.
    private static readonly TimeSpan IdleThreshold = TimeSpan.FromSeconds(60);

    private readonly ILogger<EnforcementWorker> _log;
    private readonly AgentPipeServer _pipe;
    private readonly AgentLauncher _agentLauncher;
    private readonly AnonymousAuth _auth;
    private readonly FirestoreClient _firestore;
    private readonly PairingService _pairing;
    private readonly RuleSync _rules;
    private readonly WebPolicySync _webPolicy;
    private readonly WebFilter _webFilter;
    private readonly WebActivity _web;
    private readonly MessageStore _messages;
    private readonly ChatReporter _chats;
    private readonly YoutubeStore _youtube;
    private readonly AppUpdater _updater;
    private readonly Reporter _reporter;
    private readonly UsageTracker _usage = new();

    private DeviceState _state = DeviceState.Load();
    private Dictionary<string, string> _appNames = new(StringComparer.OrdinalIgnoreCase);
    private volatile IReadOnlyList<InstalledApp> _sessionApps = Array.Empty<InstalledApp>();
    private DateTimeOffset _lastRules = DateTimeOffset.MinValue;
    private DateTimeOffset _lastHeartbeat = DateTimeOffset.MinValue;
    private DateTimeOffset _lastReport = DateTimeOffset.MinValue;
    private DateTimeOffset _lastWebReport = DateTimeOffset.MinValue;
    private DateTimeOffset _lastYoutubeReport = DateTimeOffset.MinValue;
    private DateTimeOffset _lastChatReport = DateTimeOffset.MinValue;
    private DateTimeOffset _lastPersist = DateTimeOffset.MinValue;
    private DateTimeOffset _lastRegisterAttempt = DateTimeOffset.MinValue;
    private DateTimeOffset? _lastForegroundAt;
    private bool _deviceRegistered;
    private string? _blockedApp;
    private DateTimeOffset _blockedAppUntil;
    private readonly Dictionary<string, DateTimeOffset> _appAlerts = new(StringComparer.OrdinalIgnoreCase);
    private string _blockedSite = "";
    private string _blockedReason = "";
    private string _suppressedSite = "";
    private DateTimeOffset _suppressedSiteUntil;
    private bool _stoppedUncleanly;
    private DateTimeOffset? _lockedWithoutAgentSince;
    private string _status = "Starting…";

    public EnforcementWorker(
        ILogger<EnforcementWorker> log,
        AgentPipeServer pipe,
        AgentLauncher agentLauncher,
        AnonymousAuth auth,
        FirestoreClient firestore,
        PairingService pairing,
        RuleSync rules,
        WebPolicySync webPolicy,
        WebFilter webFilter,
        WebActivity web,
        MessageStore messages,
        ChatReporter chats,
        YoutubeStore youtube,
        AppUpdater updater,
        Reporter reporter)
    {
        _log = log;
        _pipe = pipe;
        _agentLauncher = agentLauncher;
        _auth = auth;
        _firestore = firestore;
        _pairing = pairing;
        _rules = rules;
        _webPolicy = webPolicy;
        _webFilter = webFilter;
        _web = web;
        _messages = messages;
        _chats = chats;
        _youtube = youtube;
        _updater = updater;
        _reporter = reporter;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        _pipe.PairRequested = PairAsync;
        _pipe.ForegroundReported = OnForeground;
        _pipe.ChatsReported = OnChats;
        _pipe.AppsReported = OnApps;
        _pipe.OverlayDismissed = OnOverlayDismissed;
        _pipe.Start(ct);
        RefreshAppNames();

        _stoppedUncleanly = RunMarker.Claim();
        if (_stoppedUncleanly) _log.LogWarning("Previous run did not stop cleanly");

        while (!ct.IsCancellationRequested)
        {
            try
            {
                await TickAsync(ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception e)
            {
                Diag.Warn("worker.tick", e);
                _log.LogError(e, "Enforcement tick failed");
            }

            try { await Task.Delay(Tick, ct); }
            catch (OperationCanceledException) { break; }
        }

        _usage.Flush();
        _web.Flush();
        _youtube.Persist();
        RunMarker.Release();
    }

    private async Task TickAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;

        if (WindowsServiceHelpers.IsWindowsService())
        {
            _agentLauncher.EnsureRunning();
        }

        // Browsing is captured whether or not this PC is paired yet, so it is
        // saved on its own schedule rather than only when a report goes out.
        if (_web.HasChanges && now - _lastPersist > PersistInterval)
        {
            _lastPersist = now;
            _web.Flush();
        }

        if (!_state.IsPaired)
        {
            _status = "Not connected. Enter a pairing code.";
            await BroadcastAsync(locked: false, usedMinutes: 0, ct);
            return;
        }

        if (!_deviceRegistered && now - _lastRegisterAttempt > RegisterRetry)
        {
            _lastRegisterAttempt = now;
            _deviceRegistered = await _pairing.RegisterDeviceAsync(_state.FamilyId, _state.ChildId, ct);
        }

        if (now - _lastRules > RuleInterval)
        {
            _lastRules = now;
            try
            {
                await _rules.RefreshAsync(_state, ct);
                await _webPolicy.RefreshAsync(_state, ct);
            }
            catch (FirestoreException e)
            {
                if (await HandleRemovalAsync(e, ct)) return;
                Diag.Warn("worker.rules", e);
            }
        }

        var usedMinutes = _usage.MinutesToday();
        var locked = ScreenGuard.ShouldLock(_rules.ScreenTime, usedMinutes);

        EnforceWithoutAgent(locked, now);

        foreach (var stopped in AppBlocker.Enforce(EffectiveAppRules()))
        {
            _blockedApp = _appNames.GetValueOrDefault(stopped, stopped);
            // Hold the notice up long enough to read, and re-arm it every time
            // the child launches the app again.
            _blockedAppUntil = now.AddSeconds(6);
            _log.LogInformation("Blocked {App}", stopped);

            // One alert per app per 10 minutes: the enforcement loop runs every
            // couple of seconds and would otherwise flood the parent's feed.
            if (now - _appAlerts.GetValueOrDefault(stopped) > TimeSpan.FromMinutes(10))
            {
                _appAlerts[stopped] = now;
                await SafeAlertAsync("app_blocked", $"{_blockedApp} was blocked", ct);
            }
        }

        _status = locked ? ScreenGuard.LockText(_rules.ScreenTime, usedMinutes).Title : "Protected";

        if (now - _lastHeartbeat > HeartbeatInterval)
        {
            _lastHeartbeat = now;
            try
            {
                await _reporter.HeartbeatAsync(
                    _state,
                    ServiceHealth.Protections(WindowsServiceHelpers.IsWindowsService()),
                    ct);

                if (_stoppedUncleanly)
                {
                    // Only after a heartbeat lands, so the parent sees the
                    // alert on a device that is demonstrably reachable.
                    _stoppedUncleanly = false;
                    await SafeAlertAsync(
                        "protection_disabled", "Protection stopped unexpectedly on this PC", ct);
                }
            }
            catch (FirestoreException e)
            {
                if (await HandleRemovalAsync(e, ct)) return;
                Diag.Warn("worker.heartbeat", e);
            }
        }

        if (now - _lastReport > ReportInterval)
        {
            _lastReport = now;
            _usage.Flush();
            var inventory = Inventory();
            _appNames = NamesOf(inventory);
            try
            {
                await _reporter.ReportInstalledAppsAsync(_state, inventory, ct);
            }
            catch (FirestoreException e)
            {
                if (await HandleRemovalAsync(e, ct)) return;
                Diag.Warn("worker.report", e);
            }

            // The fleet is unreachable once installed, so this is the only way a
            // fix ever reaches it.
            if (WindowsServiceHelpers.IsWindowsService()) await _updater.CheckAsync(ct);
        }

        if (_web.HasChanges && now - _lastWebReport > WebReportInterval)
        {
            _lastWebReport = now;
            try
            {
                await _reporter.ReportWebHistoryAsync(_state, _web.Snapshot(now), ct);
            }
            catch (FirestoreException e)
            {
                if (await HandleRemovalAsync(e, ct)) return;
                Diag.Warn("worker.web", e);
            }
        }

        // Watch history uploads on its own schedule; tying it to web history
        // meant a video watched with no new browsing was never reported.
        if (_youtube.HasChanges && now - _lastYoutubeReport > WebReportInterval)
        {
            _lastYoutubeReport = now;
            try
            {
                await _reporter.ReportYoutubeAsync(_state, _youtube.Snapshot(now), ct);
            }
            catch (FirestoreException e)
            {
                if (await HandleRemovalAsync(e, ct)) return;
                Diag.Warn("worker.youtube", e);
            }
        }

        if (_messages.HasChanges && now - _lastChatReport > ChatReportInterval)
        {
            _lastChatReport = now;
            var drained = _messages.Drain();
            try
            {
                await _chats.ReportAsync(_state, drained, ct);
            }
            catch (FirestoreException e)
            {
                // Put them back rather than losing a conversation to one
                // failed upload.
                _messages.Requeue(drained);
                if (await HandleRemovalAsync(e, ct)) return;
                Diag.Warn("worker.chats", e);
            }
        }

        await BroadcastAsync(locked, usedMinutes, ct);
    }

    /// <summary>
    /// The lock has to hold even with the agent closed. The service cannot draw
    /// anything from session 0, so when there is nobody to show the lock screen
    /// it signs the session out instead — otherwise closing one process would
    /// turn bedtime off.
    /// </summary>
    private void EnforceWithoutAgent(bool locked, DateTimeOffset now)
    {
        var activeSession = _agentLauncher.ActiveSessionId;
        var activeAgentConnected = activeSession < 0 || _pipe.AgentConnectedInSession(activeSession);
        if (!locked || activeAgentConnected)
        {
            _lockedWithoutAgentSince = null;
            return;
        }

        _lockedWithoutAgentSince ??= now;
        // A moment's grace: the agent reconnects on its own after a restart or
        // a fresh sign-in, and signing the child straight out would be wrong.
        if (now - _lockedWithoutAgentSince < TimeSpan.FromSeconds(15)) return;

        var closed = SessionLock.DisconnectActive();
        if (closed > 0) _log.LogWarning("Signed out {Count} session(s): locked with no agent", closed);
    }

    private AppRules EffectiveAppRules()
    {
        // On PC, browsers are monitoring surfaces rather than blockable apps:
        // every supported browser stays available while its URL is recorded.
        return new AppRules(Browsers.RemoveFrom(_rules.Apps.Blocked));
    }

    private async Task BroadcastAsync(bool locked, int usedMinutes, CancellationToken ct)
    {
        var state = new AgentState
        {
            // A stale device.json must never make the UI claim that the parent
            // still owns this PC. Registration is protected by Firestore rules,
            // so success is the authoritative confirmation.
            Paired = _state.IsPaired && _deviceRegistered,
            PairingPending = _state.IsPaired && !_deviceRegistered,
            Locked = locked,
            DeviceName = _state.DeviceName,
            FamilyName = _state.FamilyName,
            Status = _state.IsPaired && !_deviceRegistered
                ? "Checking family connection…"
                : _status,
        };

        // One intent wins, in the order that matters to the child: a lock they
        // cannot pass, then the site they are looking at, then a passing notice.
        if (locked)
        {
            var (title, subtitle) = ScreenGuard.LockText(_rules.ScreenTime, usedMinutes);
            state.Overlay = OverlayKind.Lock;
            state.OverlayTitle = title;
            state.OverlaySubtitle = subtitle;
        }
        else if (_blockedSite.Length > 0)
        {
            state.Overlay = OverlayKind.Site;
            state.OverlayTitle = "Site blocked";
            state.OverlaySubtitle = ReasonText(_blockedReason);
            state.OverlayDetail = _blockedSite;
            state.OverlayDismissible = true;
        }
        else if (_blockedApp is { Length: > 0 } app && DateTimeOffset.UtcNow < _blockedAppUntil)
        {
            state.Overlay = OverlayKind.App;
            state.OverlayTitle = "App blocked";
            state.OverlaySubtitle = "Your parent does not allow this app.";
            state.OverlayDetail = app;
            state.OverlayDismissible = true;
        }
        else
        {
            // The window has passed; forget it so a later launch shows a fresh
            // notice instead of being swallowed as a repeat.
            _blockedApp = null;
        }

        await _pipe.BroadcastAsync(state, ct);
    }

    private static string ReasonText(string reason) => reason switch
    {
        BlockReason.Keyword => "This page was blocked by your family's filter.",
        BlockReason.Blocklist => "Your parent has blocked this site.",
        _ => "This site is not allowed.",
    };

    private async Task<(bool Ok, string Message)> PairAsync(string code, CancellationToken ct)
    {
        try
        {
            _state = await _pairing.RedeemAsync(code, ct);
            _deviceRegistered = true;
            _lastRules = DateTimeOffset.MinValue;
            _lastHeartbeat = DateTimeOffset.MinValue;
            _lastReport = DateTimeOffset.MinValue;
            _log.LogInformation("Paired to family {Family}", _state.FamilyId);
            return (true, "Connected to your family.");
        }
        catch (PairingException e)
        {
            return (false, e.Message);
        }
        catch (Exception e)
        {
            Diag.Warn("worker.pair", e);
            return (false, "Couldn't connect. Check the internet connection and try again.");
        }
    }

    /// <summary>
    /// A rejected write on a paired device means the parent removed it, so the
    /// PC lets go: it stops enforcing and forgets the identity rather than
    /// hammering Firestore with writes it will never be allowed to make.
    /// </summary>
    private async Task<bool> HandleRemovalAsync(FirestoreException error, CancellationToken ct)
    {
        if (!error.PermissionDenied) return false;
        _log.LogWarning("Removed by the parent; unpairing");
        _state.Clear();
        _auth.Forget();
        _deviceRegistered = false;
        _status = "Not connected. Enter a pairing code.";
        await BroadcastAsync(locked: false, usedMinutes: 0, ct);
        return true;
    }

    private async Task SafeAlertAsync(string type, string detail, CancellationToken ct)
    {
        try { await _reporter.AlertAsync(_state, type, detail, ct); }
        catch (FirestoreException e) { Diag.Warn("worker.alert", e); }
    }

    private void OnForeground(ForegroundReport report)
    {
        var now = DateTimeOffset.UtcNow;
        var previous = _lastForegroundAt;
        _lastForegroundAt = now;
        var executable = report.Executable;
        if (executable.Length == 0) return;

        TrackBrowsing(report.Url, report.Title, report.PageText, now);

        if (previous is null) return;
        var elapsed = now - previous.Value;
        // A gap this long means the agent restarted or the PC slept; counting it
        // would invent screen time nobody spent.
        if (elapsed > TimeSpan.FromSeconds(10)) return;
        if (report.IdleSeconds >= IdleThreshold.TotalSeconds) return;

        TrackYoutube(report.Title, report.Url, elapsed, now);
        _usage.Record(executable, _appNames.GetValueOrDefault(executable, Friendly(executable)), elapsed);
    }

    /// <summary>
    /// Watch history from the window title. Windows has no YouTube app, so the
    /// title is the only place the video's name appears — the URL carries an id
    /// and nothing else.
    /// </summary>
    private void TrackYoutube(string title, string url, TimeSpan elapsed, DateTimeOffset now)
    {
        if (url.Length == 0 || !WebFilter.IsYoutube(Domains.HostOf(url))) return;
        var video = YoutubeStore.TitleFrom(title);
        if (video is null) return;
        _youtube.Record(video, elapsed, now);
    }

    private void OnChats(IReadOnlyList<ChatSighting> sightings)
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var sighting in sightings) _messages.Record(sighting, now);
    }

    private void OnOverlayDismissed(OverlayKind kind, string detail)
    {
        if (kind == OverlayKind.App)
        {
            _blockedApp = null;
            _blockedAppUntil = DateTimeOffset.MinValue;
            return;
        }
        if (kind == OverlayKind.Site)
        {
            _suppressedSite = Domains.Normalize(detail);
            _suppressedSiteUntil = DateTimeOffset.UtcNow.AddSeconds(5);
            _blockedSite = "";
            _blockedReason = "";
        }
    }

    /// <summary>
    /// Decides on the page the child is actually looking at. The DNS filter
    /// already refuses the lookup; this is what puts the block on screen and
    /// catches what DNS cannot see — the path, the query and the search terms.
    /// </summary>
    private void TrackBrowsing(string url, string title, string pageText, DateTimeOffset now)
    {
        if (url.Length == 0)
        {
            if (SearchParser.FromTitle(title) is not null)
            {
                _web.RecordVisit("", title, now);
            }
            else
            {
                _web.EndVisit(now);
            }
            _blockedSite = "";
            _blockedReason = "";
            return;
        }

        var reason = _webFilter.ReasonFor(url, title, pageText);
        if (reason is null)
        {
            _blockedSite = "";
            _blockedReason = "";
            _suppressedSite = "";
            _web.RecordVisit(url, title, now);
            return;
        }

        var host = Domains.HostOf(url);
        if (host == _suppressedSite && now < _suppressedSiteUntil)
        {
            return;
        }
        _suppressedSite = "";
        _blockedSite = host;
        _blockedReason = reason;
        _web.RecordBlocked(host, reason, now);
    }

    private void RefreshAppNames()
    {
        try
        {
            _appNames = NamesOf(Inventory());
        }
        catch (Exception e)
        {
            Diag.Warn("worker.appNames", e);
        }
    }

    private void OnApps(IReadOnlyList<InstalledApp> apps)
    {
        _sessionApps = apps;
        RefreshAppNames();
    }

    /// <summary>
    /// Every app on this PC. A LocalSystem service can only read machine-wide
    /// installs, so the agent's view of the child's own per-user apps — which is
    /// most of what they use — is merged over the top.
    /// </summary>
    private IReadOnlyList<InstalledApp> Inventory()
    {
        var merged = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var app in InstalledApps.Enumerate()) merged[app.Key] = app.Name;
        foreach (var app in _sessionApps) merged[app.Key] = app.Name;
        return merged
            .Select(entry => new InstalledApp(entry.Key, entry.Value))
            .OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    private static Dictionary<string, string> NamesOf(IReadOnlyList<InstalledApp> apps) =>
        apps.ToDictionary(app => app.Key, app => app.Name, StringComparer.OrdinalIgnoreCase);

    private static string Friendly(string executable)
    {
        var name = Path.GetFileNameWithoutExtension(executable);
        return name.Length <= 1 ? name : char.ToUpperInvariant(name[0]) + name[1..];
    }
}

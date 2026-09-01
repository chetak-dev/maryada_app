package com.guardnest.kid

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import com.google.firebase.firestore.FirebaseFirestore
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.Calendar
import java.util.Locale

/**
 * Lets the app UI ask the running accessibility service to turn itself off —
 * used by the "Temporary Access" button, which drops only the accessibility
 * permission so a strict banking app can run. When it's off, [EnforcementService]
 * locks the device down to the parent's allow-list until it's turned back on.
 */
object AccessibilityController {
    @Volatile
    var service: android.accessibilityservice.AccessibilityService? = null

    fun isRunning(): Boolean = service != null

    /** Turns off GuardNest's accessibility service. Returns true if it acted. */
    fun disable(): Boolean {
        val s = service ?: return false
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                s.disableSelf()
                service = null
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }
}

/**
 * Jobs, all without Device Owner:
 *
 *  1. App blocking — if the foreground app is on the parent's blocked list, the
 *     child is bounced back to the home screen.
 *  2. Web history — for browser apps, the current address-bar URL is read.
 *  3. Chat capture — WhatsApp on-screen message text.
 *  4. Anti-tamper — while linked, if the child opens the "deactivate device
 *     admin" or app-uninstall screen for GuardNest, they're bounced out (Back),
 *     so protection can't be removed until the parent unlinks the device.
 *
 * The child grants this in Settings > Accessibility (there's no runtime dialog).
 */
class GuardNestAccessibilityService : AccessibilityService() {

    private var lastToast = 0L
    private var lastTamperToast = 0L
    private var lastPairingVerify = 0L
    private var lastLockToast = 0L
    private var lastBlockPageAt = 0L
    private var lastBrowserToast = 0L
    private var lastShot = 0L
    @Volatile private var shotInFlight = false
    // Coalesces the per-event browser guards; a loading page fires content
    // changes far faster than the tree is worth re-reading.
    private var lastBrowserGuard = 0L
    private var lastChatCapture = 0L
    private var lastYtCapture = 0L
    // The address-bar view id that actually worked for a given browser.
    private val urlBarIdCache = mutableMapOf<String, String>()
    // YouTube watch-time tracking (current video + last capture time).
    private var lastYtTitle: String? = null
    private var lastYtChannel: String? = null
    private var lastYtTickAt = 0L
    // True while a full watch page is/was playing, so watch time keeps counting
    // when the video goes full-screen and its on-screen title disappears.
    private var ytActivePlayback = false
    private val ytHandler = Handler(Looper.getMainLooper())
    private val ytPump = object : Runnable {
        override fun run() {
            try {
                pumpYoutubeWatchTime()
            } catch (_: Throwable) {
            } finally {
                ytHandler.postDelayed(this, YT_PUMP_MS)
            }
        }
    }
    // Continuous browser guard so blocked sites are caught near-instantly.
    private val browserGuard = object : Runnable {
        override fun run() {
            var browsing = false
            try {
                browsing = guardBrowserNow()
            } catch (_: Throwable) {
            } finally {
                // Only poll fast while a browser is actually open; otherwise
                // this loop was reading the whole window list several times a
                // second all day for nothing.
                ytHandler.postDelayed(
                    this,
                    if (browsing) BROWSER_GUARD_MS else BROWSER_IDLE_MS,
                )
            }
        }
    }
    // Periodic browser OCR guard: screenshots the browser and reads the words
    // rendered on the page (text the accessibility tree doesn't expose), then
    // blocks the page on any unsafe word.
    @Volatile private var imgShotInFlight = false
    private var lastImgShot = 0L
    // aHash of the last scanned browser frame; identical frames skip the OCR
    // pass so a static page costs almost no battery.
    private var lastFrameSig = 0L
    private val imageGuard = object : Runnable {
        override fun run() {
            var browsing = false
            try {
                browsing = guardBrowserImageNow()
            } catch (_: Throwable) {
            } finally {
                ytHandler.postDelayed(
                    this,
                    if (browsing) IMAGE_GUARD_MS else BROWSER_IDLE_MS,
                )
            }
        }
    }
    private val textRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val type = event?.eventType ?: return
        val pkg = event.packageName?.toString() ?: return

        // Anti-tamper first: block deactivate-admin / uninstall of GuardNest.
        if (guardTamperScreens(pkg)) return

        // Then block reaching any app's "App info" / "Uninstall" screen (the
        // dangerous long-press options) — the child must ask the parent instead.
        if (guardAppManagementScreens(pkg, type)) return

        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            // The lock overlay is a focusable window, so raising it fires this
            // event under our own package. Recording that as the foreground app
            // made the enforcement poller read it as "the child left the app",
            // hide the overlay, and flash it straight back — the flicker the
            // child saw on every blocked app.
            if (pkg != packageName || !LockOverlay.isShowing()) ForegroundApp.set(pkg)
            // Pause / bedtime: block every app except emergency calls & home.
            if (guardScreenTimeLock(pkg)) return
            // If a required protection was turned off, only let the child use the
            // apps needed to fix it — everything else is bounced to GuardNest.
            if (guardPermissionLockdown(pkg)) return
            if (pkg != packageName && BlockedApps.isBlocked(pkg)) {
                blockApp(pkg)
                return
            }
            // Only one browser allowed: bounce out of any other browser, so no
            // browser's private/incognito mode can be used. Safe browsing locks
            // the child to Chrome (the approved browser).
            if (pkg != packageName && WebFilter.shouldLockOtherBrowsers() &&
                ForegroundApp.isBrowser(pkg) &&
                pkg != WebFilter.effectiveApprovedBrowser()
            ) {
                performGlobalAction(GLOBAL_ACTION_HOME)
                val now = System.currentTimeMillis()
                if (now - lastBrowserToast > 2000) {
                    lastBrowserToast = now
                    Toast.makeText(
                        this,
                        "This browser is blocked. Use the one your parent approved.",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                return
            }
        }

        // For a browser, read the address bar and record the visited site.
        // A loading or scrolling web page fires content-changed events
        // continuously, and each pass here walks every window's node tree — left
        // unthrottled it made browsing crawl. Blocking still lands well inside a
        // second, and the 250ms imageGuard/OCR pass is unaffected.
        if (pkg != packageName && ForegroundApp.isBrowserForeground()) {
            val now = System.currentTimeMillis()
            if (now - lastBrowserGuard >= BROWSER_GUARD_MS) {
                lastBrowserGuard = now
                if (guardIncognito()) return
                // Enforce first (URL across all windows + page-text keyword scan) so
                // a bad site is blocked on load, not only after a refresh.
                guardBrowserNow()
                captureBrowserUrl(pkg)
            }
        }

        // For a messaging app (WhatsApp only), read the visible on-screen chat text.
        if (pkg != packageName && CHAT_SCRAPE.containsKey(pkg)) {
            val now = System.currentTimeMillis()
            // Scan faster during a scroll so the fading floating date pill is
            // read before it disappears; otherwise keep the calmer cadence.
            val throttle =
                if (type == AccessibilityEvent.TYPE_VIEW_SCROLLED) CHAT_SCROLL_THROTTLE_MS
                else CAPTURE_THROTTLE_MS
            if (now - lastChatCapture >= throttle) {
                lastChatCapture = now
                captureChatText(pkg)
            }
            // Note: OCR screenshot capture is intentionally NOT used for chats —
            // it can't tell a message's side or time, which mangled the display.
        }

        // In the YouTube app (official, Vanced or ReVanced), record the video
        // the child is watching. Scrolling the feed fires events far faster than
        // the title can change, so the tree scan is coalesced.
        if (Pkgs.isYoutube(pkg)) {
            val now = System.currentTimeMillis()
            if (now - lastYtCapture >= CAPTURE_THROTTLE_MS) {
                lastYtCapture = now
                captureYoutube(pkg)
            }
        }
    }

    /**
     * Records the currently-playing YouTube video's title and channel. Reads the
     * watch page's metadata block (`video_metadata_layout`) whose first text is
     * the title and whose "@handle" is the channel. Works across YouTube forks
     * because they share Google's resource-id names (only the package differs).
     */
    private fun captureYoutube(pkg: String) {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        }
        // Search capture is independent of watch-time tracking, so it runs even
        // while the MediaSession source owns the watch history.
        if (root != null) captureYoutubeSearch(pkg, root)
        // When the notification-listener MediaSession source is covering YouTube
        // (it works full-screen and in the background), defer entirely to it so
        // we don't double-count watch time or create duplicate title entries.
        if (YoutubeWatch.mediaActive()) {
            ytActivePlayback = false
            return
        }
        if (root == null) {
            // Without a readable screen we no longer know what's playing. The
            // pump used to keep crediting the last title here, so a failed read
            // quietly added the current video's time to the previous one.
            ytActivePlayback = false
            return
        }
        // Shorts are watched by scrolling (no watch-page metadata), so try them
        // first; then the standard watch page; then inline autoplay in the feed.
        if (captureYoutubeShorts(pkg, root)) return
        if (captureYoutubeWatchPage(pkg, root)) return
        captureYoutubeFeed(root)
    }

    // The last search seen in the YouTube app, so an open results page that
    // keeps firing events doesn't repeat the same record.
    private var lastYtSearch = ""

    /**
     * Records a search the child *submitted* in the YouTube app. The search box
     * is focused while typing; once submitted, the results screen shows the same
     * view holding the query without focus — that's the state recorded, so
     * keystrokes and suggestions never appear.
     *
     * Every window is searched, not just the active one: on some builds the
     * search bar and the results list are separate windows. The id also moved
     * between YouTube versions and forks rename the package, so each known id is
     * tried under the app's own namespace.
     */
    private fun captureYoutubeSearch(pkg: String, root: AccessibilityNodeInfo) {
        try {
            val roots = ArrayList<AccessibilityNodeInfo>()
            roots.add(root)
            try {
                windows?.forEach { w ->
                    val r = w.root ?: return@forEach
                    if (r.packageName?.toString() == pkg) roots.add(r)
                }
            } catch (_: Exception) {
            }
            for (r in roots) {
                for (id in YT_SEARCH_IDS) {
                    val box = r.findAccessibilityNodeInfosByViewId("$pkg:id/$id")
                        ?.firstOrNull { !it.text.isNullOrBlank() } ?: continue
                    if (box.isFocused) return // still typing
                    val query = box.text?.toString()?.trim() ?: continue
                    if (query.isEmpty() || query == lastYtSearch) return
                    // The box shows its hint on the empty search screen.
                    if (query.equals("search", true)) return
                    lastYtSearch = query
                    WebHistoryStore.recordSearchQuery(query, "YouTube")
                    return
                }
            }
        } catch (_: Exception) {
        }
    }

    /** Standard watch page: reads the video metadata block. Returns true if found. */
    private fun captureYoutubeWatchPage(pkg: String, root: AccessibilityNodeInfo): Boolean {
        return try {
            val meta = root
                .findAccessibilityNodeInfosByViewId("$pkg:id/video_metadata_layout")
                ?.firstOrNull() ?: return false
            val texts = ArrayList<String>()
            collectTexts(meta, texts, 0)
            val title = texts.firstOrNull {
                it.length >= 2 && it.lowercase() !in YT_NOISE
            } ?: return false
            val channel = texts.firstOrNull { it.startsWith("@") }
                ?: texts.getOrNull(texts.indexOf(title) + 1)
                    ?.takeIf { !it.contains("views", true) && it.lowercase() !in YT_NOISE }
                ?: ""
            recordYt(title, channel)
            ytActivePlayback = true
            true
        } catch (_: Exception) {
            false
        }
    }

    // Feed autoplay: which video is centred, and since when (dwell detection).
    private var lastFeedTitle: String? = null
    private var lastFeedSince = 0L
    // Same idea for Shorts, which are scrolled through quickly.
    private var lastShortTitle: String? = null
    private var lastShortSince = 0L

    /**
     * Best-effort capture of a 16:9 video that autoplays inline in the YouTube
     * home feed while the child scrolls (no tap needed). Picks the video cell
     * most centred on screen and only records it once it has stayed centred for
     * a short dwell — so videos merely scrolled past aren't logged.
     */
    private fun captureYoutubeFeed(root: AccessibilityNodeInfo) {
        val dm = resources.displayMetrics
        val centerY = dm.heightPixels / 2
        val minWidth = (dm.widthPixels * 0.55).toInt()
        val rect = Rect()
        var bestCd: String? = null
        var bestDist = Int.MAX_VALUE
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var scanned = 0
        while (queue.isNotEmpty() && scanned < 700) {
            val node = queue.removeFirst()
            scanned++
            val cd = node.contentDescription?.toString()?.trim()
            if (cd != null && cd.length in 8..220 && looksLikeVideoDesc(cd)) {
                node.getBoundsInScreen(rect)
                // A feed video thumbnail is wide and currently on screen.
                if (rect.width() >= minWidth &&
                    rect.top < dm.heightPixels && rect.bottom > 0
                ) {
                    val dist = kotlin.math.abs((rect.top + rect.bottom) / 2 - centerY)
                    if (dist < bestDist) {
                        bestDist = dist
                        bestCd = cd
                    }
                }
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        val cd = bestCd ?: return
        val (title, channel) = parseFeedDescription(cd)
        if (title.length < 3) return
        val now = System.currentTimeMillis()
        if (title != lastFeedTitle) {
            // Newly centred — start the dwell timer, don't record yet.
            lastFeedTitle = title
            lastFeedSince = now
            return
        }
        if (now - lastFeedSince < FEED_DWELL_MS) return
        ytActivePlayback = false
        // The dwell already elapsed watching it, so it counts.
        recordYt(title, channel, seedMs = FEED_DWELL_MS)
    }

    /** Heuristic: a YouTube feed thumbnail's description mentions the channel /
     *  view / age, so it's a real video (not a shelf header or ad button). */
    private fun looksLikeVideoDesc(cd: String): Boolean {
        val l = cd.lowercase()
        return l.contains(" by ") ||
            l.contains(" views") ||
            l.contains(" ago") ||
            YT_COUNT.containsMatchIn(cd)
    }

    /** Splits a feed thumbnail description into (title, channel), best effort.
     *  Format is usually "Title - Channel - duration - N views - N ago". */
    private fun parseFeedDescription(cd: String): Pair<String, String> {
        val parts = cd.split(" - ", " by ").map { it.trim() }.filter { it.isNotEmpty() }
        val title = parts.firstOrNull() ?: cd
        val channel = parts.getOrNull(1)
            ?.takeIf { !it.contains("view", true) && !it.contains("ago", true) }
            ?: ""
        return title to channel
    }

    /**
     * Captures a YouTube **Short** (watched by scrolling). Shorts have no
     * watch-page metadata; instead the reel overlay shows the channel "@handle"
     * and the caption. Returns true if a Short was detected and recorded.
     */
    private fun captureYoutubeShorts(pkg: String, root: AccessibilityNodeInfo): Boolean {
        val reel = REEL_IDS.firstNotNullOfOrNull { id ->
            root.findAccessibilityNodeInfosByViewId("$pkg:id/$id")?.firstOrNull()
        } ?: return false
        val texts = ArrayList<String>()
        collectTexts(reel, texts, 0)
        if (texts.isEmpty()) return false
        val channel = texts.firstOrNull { it.startsWith("@") } ?: ""
        // The caption/title: first substantial line that isn't the handle, a
        // like/view/comment count, or a bare number/duration.
        val caption = texts.firstOrNull {
            it.length >= 2 &&
                !it.startsWith("@") &&
                it.lowercase() !in YT_NOISE &&
                !YT_COUNT.containsMatchIn(it) &&
                !it.all { c -> c.isDigit() || c == ':' || c == '.' }
        }
        // A Short with no readable caption can't be told apart from any other
        // Short by the same channel. Recording it as "Short from @handle" made
        // every one of them merge into a single row with their watch time
        // summed, so an unidentifiable Short is skipped instead.
        val title = caption ?: return false
        // Shorts are watched by scrolling, so only count one the child actually
        // stayed on.
        val now = System.currentTimeMillis()
        if (title != lastShortTitle) {
            lastShortTitle = title
            lastShortSince = now
            return true
        }
        if (now - lastShortSince < SHORT_DWELL_MS) return true
        ytActivePlayback = false
        recordYt(title, channel, seedMs = SHORT_DWELL_MS)
        return true
    }

    /** Accumulates watch time for the current YouTube title and records it.
     *
     * [seedMs] is credited when this title is first seen, for the sources that
     * only recognise a video after it has already been on screen for a while.
     * Without it their watch time started at zero and never reached
     * `YoutubeStore.MIN_WATCHED_MS`, so the video never reached the parent. */
    private fun recordYt(title: String, channel: String, seedMs: Long = 0L) {
        val now = System.currentTimeMillis()
        // Add the gap since the last capture of the SAME video (ignoring big
        // gaps that mean the child was away/paused).
        val addMs = if (title == lastYtTitle) {
            val d = now - lastYtTickAt
            if (d in 1..YT_MAX_GAP_MS) d else 0L
        } else seedMs
        lastYtTitle = title
        if (channel.isNotBlank()) lastYtChannel = channel
        lastYtTickAt = now
        YoutubeStore.record(title, channel, addMs)
        // This is the on-screen path, so the child is actually looking at the
        // video and can be taken off it. The media-session path in the
        // notification listener only alerts: it also fires with the screen off
        // or the app in the background, where bouncing would interrupt nothing
        // the child is watching.
        val unsafe = ContentFilter.matchWords(title.lowercase())
        if (unsafe != null) {
            blockVideo(title, unsafe)
            return
        }
        ContentWatch.video(this, title, channel)
    }

    /** Leaves an unsafe video and says why, the same way a blocked page does. */
    private fun blockVideo(title: String, matched: String) {
        val category = ContentFilter.categoryOf(matched) ?: WebFilter.REASON_CONTENT
        showBlockPage(null, "Hare Krishna, this video may not be safe for you")
        AlertLog.log(
            this, "unsafeVideo",
            "Blocked video (\u201C$matched\u201D): $title",
            throttleKey = "video:$title",
            category = category,
        )
    }

    /**
     * Keeps accumulating watch time for the current video while it plays
     * full-screen (when the on-screen title/metadata disappears). Only runs
     * while a real watch page was last seen, YouTube is still foreground and the
     * screen is on — so it won't count time after the child leaves or the screen
     * locks.
     */
    private fun pumpYoutubeWatchTime() {
        // The MediaSession source owns watch time whenever it's active (it keeps
        // counting full-screen and in the background), so step aside for it.
        if (YoutubeWatch.mediaActive()) {
            ytActivePlayback = false
            return
        }
        if (!ytActivePlayback) return
        val title = lastYtTitle ?: return
        if (!Pkgs.isYoutube(ForegroundApp.packageName)) {
            ytActivePlayback = false
            return
        }
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (pm != null && !pm.isInteractive) return // screen off — not watching
        recordYt(title, lastYtChannel ?: "")
    }

    /** Depth-first collects up to a few visible text lines from a node subtree. */
    private fun collectTexts(node: AccessibilityNodeInfo, out: MutableList<String>, depth: Int) {
        if (depth > 10 || out.size > 18) return
        val t = node.text?.toString()?.trim()
        if (!t.isNullOrBlank()) out.add(t)
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectTexts(child, out, depth + 1)
        }
    }

    /**
     * While the device is linked and GuardNest is an active device admin, detect
     * the Settings screen that would deactivate our admin or uninstall the app,
     * and bounce the child out. (Android already blocks uninstalling an active
     * device-admin app, so blocking the deactivate screen protects both.)
     *
     * Returns true if it acted (so the event is consumed).
     */
    private var lastTamperScan = 0L

    private fun guardTamperScreens(pkg: String): Boolean {
        // Cheapest test first: this only ever fires on Settings/installer
        // screens, and it runs for every event from every app. isAdminActive()
        // is a binder call, so it must not come before this.
        val isSensitive = pkg in SENSITIVE_PACKAGES ||
            pkg.contains("settings") || pkg.contains("packageinstaller")
        if (!isSensitive) return false
        if (!ChildStore.isPaired(this)) return false
        if (!DeviceLockdown.isAdminActive(this)) return false
        // Scrolling a Settings page fires a stream of content-changed events;
        // walking the whole tree for each of them was the single most expensive
        // thing we did per event. A short throttle keeps detection effectively
        // instant while cutting the repeat scans.
        val now = System.currentTimeMillis()
        if (now - lastTamperScan < SCAN_THROTTLE_MS) return false
        lastTamperScan = now

        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return false

        val text = collectText(root, StringBuilder(), 0).toString().lowercase()
        // Only act when this screen is clearly about GuardNest AND offers a
        // deactivate / uninstall / disable action.
        val mentionsUs = text.contains("maryada")
        val dangerous = DANGER_KEYWORDS.any { text.contains(it) }
        if (mentionsUs && dangerous) {
            // Self-heal: confirm the device is still linked. If the parent has
            // removed it, release device admin so uninstall is allowed instead
            // of blocking it.
            verifyStillLinked()
            performGlobalAction(GLOBAL_ACTION_BACK)
            AlertLog.log(
                this, "tamper",
                "Tried to remove or disable protection",
                throttleKey = "tamper:attempt",
            )
            val now = System.currentTimeMillis()
            if (now - lastTamperToast > 1500) {
                lastTamperToast = now
                Toast.makeText(
                    this,
                    "Ask your parent to remove this device before changing this.",
                    Toast.LENGTH_LONG
                ).show()
            }
            return true
        }
        return false
    }

    /**
     * Confirms with the server that this device is still in the family. If it
     * was removed, the local pairing is cleared and device admin released so the
     * child can uninstall the app (throttled to avoid excessive reads).
     */
    private fun verifyStillLinked() {
        val now = System.currentTimeMillis()
        if (now - lastPairingVerify < 4000) return
        lastPairingVerify = now
        val fid = ChildStore.familyId(this) ?: return
        val cid = ChildStore.childId(this) ?: return
        FirebaseFirestore.getInstance()
            .collection("families").document(fid)
            .collection("children").document(cid)
            .get()
            .addOnSuccessListener { doc ->
                // Only unlock on a definitive server answer. A cached miss (the
                // device is offline) must NOT release protection, or a child
                // could turn off the network and uninstall the app.
                if (!doc.exists() && !doc.metadata.isFromCache) {
                    ChildStore.clear(this)
                    DeviceLockdown.releaseForRemoval(this)
                    WebFilterVpnService.stop(this)
                }
            }
            .addOnFailureListener { e ->
                // Fail closed: protection stays on and the attempt is recorded.
                Diag.warn(this, "verifyStillLinked", e)
            }
    }

    private fun collectText(
        node: AccessibilityNodeInfo?,
        out: StringBuilder,
        depth: Int,
    ): StringBuilder {
        if (node == null || depth > 40 || out.length > 4000) return out
        node.text?.let { out.append(it).append(' ') }
        node.contentDescription?.let { out.append(it).append(' ') }
        for (i in 0 until node.childCount) {
            collectText(node.getChild(i), out, depth + 1)
        }
        return out
    }

    private var lastContactToast = 0L
    private var lastAppMgmtScan = 0L

    /**
     * Blocks the child from reaching Maryada's own "App info" / "Uninstall"
     * screen — including the launcher's long-press menu, which the tamper guard
     * never sees because it only watches Settings and the package installer.
     * Every other app can be managed normally.
     *
     * Returns true if it acted (the event is consumed).
     */
    private fun guardAppManagementScreens(pkg: String, type: Int): Boolean {
        val isUninstaller = pkg.contains("packageinstaller")
        val isSettings = pkg.contains("settings")
        val isLauncher = Pkgs.isLauncher(pkg)
        if (!isUninstaller && !isSettings && !isLauncher) return false
        if (!ChildStore.isPaired(this)) return false
        // For the launcher, only inspect when a new window/popup appears (the
        // long-press menu), not on every home-screen content change.
        if (isLauncher && type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return false
        }
        // Same throttle as the tamper scan: this also walks the whole tree.
        val scanAt = System.currentTimeMillis()
        if (scanAt - lastAppMgmtScan < SCAN_THROTTLE_MS) return false
        lastAppMgmtScan = scanAt

        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return false
        val text = collectText(root, StringBuilder(), 0).toString().lowercase()

        // The uninstall confirmation clearly says "uninstall"; the Settings
        // app-info page and the launcher long-press menu show a cluster of app
        // actions (app info / uninstall / force stop / …). Require two markers
        // to avoid catching unrelated Settings or home screens.
        val isAppManagement = if (isUninstaller) {
            text.contains("uninstall")
        } else {
            APP_INFO_MARKERS.count { text.contains(it) } >= 2
        }
        if (!isAppManagement) return false
        // Only Maryada's own management screen is off-limits. Blocking every
        // app's meant the child (and the parent holding the phone) could not
        // uninstall anything at all, which was never the intent.
        if (!text.contains("maryada")) return false

        performGlobalAction(GLOBAL_ACTION_BACK)
        val now = System.currentTimeMillis()
        if (now - lastContactToast > 2000) {
            lastContactToast = now
            Toast.makeText(
                this,
                "Ask your parent to remove Maryada.",
                Toast.LENGTH_LONG
            ).show()
        }
        return true
    }

    /**
     * Pause / bedtime: the home screen stays usable, but the moment the child
     * opens any app the lock screen covers it (showing the schedule). Doesn't
     * bounce or freeze the phone — the child can go back to the home screen.
     * Returns true if it acted (the lock screen is covering an app).
     */
    private fun guardScreenTimeLock(pkg: String): Boolean {
        if (!ScreenGuard.locked) return false
        // Home screen → the device stays accessible, so drop the lock screen.
        if (Pkgs.isLauncher(pkg)) {
            LockOverlay.hide(this)
            return false
        }
        // Our own windows (the overlay / the Maryada app) and transient system
        // windows (status bar, system dialogs) must NOT toggle the overlay —
        // hiding/showing on those made it flicker on some apps. Leave it as-is.
        if (pkg == packageName || pkg == "android" || pkg.contains("systemui")) {
            return false
        }
        // A real app is open → cover it with the lock screen.
        LockOverlay.show(this, ScreenGuard.lockTitle, ScreenGuard.lockSubtitle)
        return true
    }

    /**
     * Covers an app the parent blocked with the same block screen the browser
     * shows for a blocked site. Bouncing the child to the home screen is only
     * the fallback for when the overlay permission has been revoked.
     */
    private fun blockApp(pkg: String) {
        if (LockOverlay.canShow(this)) {
            LockOverlay.show(
                this,
                LockOverlay.APP_BLOCKED_TITLE,
                LockOverlay.APP_BLOCKED_MESSAGE,
                AlertLog.appLabel(this, pkg),
            )
            return
        }
        performGlobalAction(GLOBAL_ACTION_HOME)
        val now = System.currentTimeMillis()
        if (now - lastToast > 2000) {
            lastToast = now
            Toast.makeText(
                this, "This app is blocked by your parent.", Toast.LENGTH_SHORT
            ).show()
        }
    }

    /**
     * When the device is linked but a required protection has been switched off,
     * the child may only use GuardNest and the system screens needed to restore
     * it (Settings, permission dialogs, launcher). Any other app is bounced to
     * the GuardNest permission screen — so the phone is unusable for normal apps
     * until protection is fixed, while the fix path stays open.
     *
     * Returns true if it acted (the event is consumed).
     */
    private fun guardPermissionLockdown(pkg: String): Boolean {
        if (!ChildStore.isPaired(this)) return false
        if (Permissions.allGrantedCached(this)) return false
        if (isAllowedDuringLockdown(pkg)) return false

        // Kick out of the disallowed app and surface the permission screen.
        performGlobalAction(GLOBAL_ACTION_HOME)
        try {
            startActivity(
                Intent(this, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            )
        } catch (_: Exception) {
        }
        val now = System.currentTimeMillis()
        if (now - lastLockToast > 2500) {
            lastLockToast = now
            Toast.makeText(
                this,
                "Turn Maryada's permissions back on to use your apps.",
                Toast.LENGTH_LONG
            ).show()
        }
        return true
    }

    private fun isAllowedDuringLockdown(pkg: String): Boolean {
        if (pkg == packageName) return true
        return Pkgs.isEssentialSystem(pkg) ||
            pkg.contains("packageinstaller") ||
            pkg.contains("vpndialogs")
    }

    /** Reads visible chat messages from a messaging app's conversation view. */
    private fun captureChatText(pkg: String) {
        val ids = CHAT_SCRAPE[pkg] ?: return
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return
        try {
            val chatName = firstText(root, ids.titleId) ?: return
            // The header subtitle sometimes carries the phone number (unsaved
            // contacts / business chats); keep it only if it looks like one.
            val number = phoneLike(firstText(root, ids.subtitleId))
                ?: phoneLike(chatName) ?: ""
            // Collect date anchors and message rows together, each tagged with
            // its vertical screen position. WhatsApp's conversation is a
            // recycling, reverse-laid-out list, so the accessibility tree's own
            // order doesn't match the visual order — sorting by position is the
            // only reliable way to know which date a message sits under.
            val rows = ArrayList<ChatRow>()
            scanChatRows(root, ids, 0, rows, intArrayOf(6000))
            // Visual top-to-bottom. A stable sort keeps the floating date pill
            // (which overlaps the top message) ahead of that message.
            rows.sortBy { it.top }
            // Each message inherits the nearest date anchor above it: the pill
            // dates the top of the window (where the inline separator has already
            // scrolled off), and inline separators date everything below them.
            var currentDay = 0L
            // How many times each text has already been seen in this pass — the
            // only trustworthy way to tell a genuinely repeated message from
            // the same message being read again.
            val seen = HashMap<String, Int>()
            for (row in rows) {
                val node = row.node
                if (node == null) {
                    if (row.day > 0L) currentDay = row.day
                    continue
                }
                val text = node.text?.toString()?.trim()
                if (text.isNullOrBlank()) continue
                // Isolate this one message's row so the time and the send/read
                // ticks can't be confused with a neighbouring message.
                val bubble = tightBubble(node, ids.messageId)
                val timeLabel = bubbleTime(bubble, ids.dateId)
                // WhatsApp right-aligns the child's own messages; the delivery
                // ticks only back that up when they're present.
                val outgoing = bubbleSide(bubble, node, ids.statusId)
                val occurrence = seen[text] ?: 0
                seen[text] = occurrence + 1
                MessageStore.record(
                    appLabel(pkg), chatName, text, outgoing, timeLabel, number,
                    currentDay, occurrence,
                )
                ContentWatch.message(
                    this, appLabel(pkg), chatName, text, outgoing == true,
                )
            }
        } catch (e: Exception) {
            Diag.warn(this, "captureChatText", e)
        }
    }

    /**
     * The clock label WhatsApp prints in the corner of the bubble ("10:24 pm").
     *
     * Only text that actually looks like a time is accepted: the date view also
     * carries things like "Yesterday" or a sender name on some builds, and
     * taking the first non-blank line stamped those onto the message. Builds
     * that don't expose the id at all are handled by scanning the bubble for the
     * same short line.
     */
    private fun bubbleTime(bubble: AccessibilityNodeInfo?, dateId: String): String {
        if (bubble == null) return ""
        bubble.findAccessibilityNodeInfosByViewId(dateId)
            ?.mapNotNull { it.text?.toString()?.trim() }
            ?.firstOrNull { CLOCK_RE.matches(it) }
            ?.let { return it }
        val texts = ArrayList<String>()
        collectTexts(bubble, texts, 0)
        return texts.firstOrNull { CLOCK_RE.matches(it) } ?: ""
    }

    /** A scanned conversation row: either a message ([node] set, [day] 0) or a
     *  date anchor ([node] null, [day] the resolved day). [top] is its vertical
     *  screen position, used to order rows the way they actually appear. */
    private class ChatRow(val top: Int, val node: AccessibilityNodeInfo?, val day: Long)

    /**
     * Depth-first walk collecting message rows and date anchors. Anchors are the
     * inline day separators *and* WhatsApp's floating scroll-date pill — the pill
     * isn't the separator's view id and its id varies by build, so it's matched
     * by its content (a bare date label) rather than by id.
     */
    private fun scanChatRows(
        node: AccessibilityNodeInfo?,
        ids: ChatIds,
        depth: Int,
        out: MutableList<ChatRow>,
        budget: IntArray,
    ) {
        // WhatsApp nests a conversation row ~25-60 levels deep, so a shallow
        // depth cap silently found no rows at all. The node budget is what
        // actually bounds the walk.
        if (node == null || depth > CHAT_SCAN_MAX_DEPTH || out.size > 240) return
        if (--budget[0] < 0) return
        when (node.viewIdResourceName) {
            ids.dividerId -> {
                val day = dividerText(node)?.let { resolveDay(it) } ?: 0L
                out.add(ChatRow(topOf(node), null, day))
                return
            }

            ids.messageId -> {
                out.add(ChatRow(topOf(node), node, 0L))
                return
            }
        }
        // The floating scroll-date pill (and any other standalone date label): a
        // leaf whose entire text is a date. resolveDay returns 0 for a bubble
        // time like "10:24 PM", so per-message times are never mistaken for it,
        // and a message that merely reads "Monday" is caught by the messageId
        // branch above before it can reach here.
        if (node.childCount == 0) {
            val t = node.text?.toString()?.trim()
            if (!t.isNullOrEmpty() && t.length <= 24) {
                val day = resolveDay(t)
                if (day > 0L) {
                    out.add(ChatRow(topOf(node), null, day))
                    return
                }
            }
        }
        for (i in 0 until node.childCount) {
            scanChatRows(node.getChild(i), ids, depth + 1, out, budget)
        }
    }

    /** Screen-space top of [node], for ordering rows the way they appear. */
    private fun topOf(node: AccessibilityNodeInfo): Int {
        val r = Rect()
        node.getBoundsInScreen(r)
        return r.top
    }

    /** The divider's date text — on the node itself or a text child under it. */
    private fun dividerText(node: AccessibilityNodeInfo, depth: Int = 0): String? {
        node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        if (depth >= 4) return null
        for (i in 0 until node.childCount) {
            val c = node.getChild(i) ?: continue
            dividerText(c, depth + 1)?.let { return it }
        }
        return null
    }

    /**
     * Turns a separator label into the start of that day in millis, or 0 when it
     * can't be read. Resolved at capture time so the stored value stays put:
     * "Today" becomes "Yesterday" tomorrow, and keying anything off the label
     * itself would make the same message look new.
     */
    private fun resolveDay(label: String): Long {
        val l = label.trim().lowercase(Locale.ROOT)
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (l == "today") return cal.timeInMillis
        if (l == "yesterday") {
            cal.add(Calendar.DAY_OF_YEAR, -1)
            return cal.timeInMillis
        }
        // WhatsApp shows a weekday name for the past week; that means the most
        // recent one before today.
        val weekday = WEEKDAYS.indexOf(l)
        if (weekday >= 0) {
            // WEEKDAYS is Monday-first (0..6); Calendar is Sunday-first (1..7).
            // The old `weekday + Calendar.MONDAY` mapped Sunday to 8, which no
            // Calendar day ever equals, so every "Sunday" separator failed to
            // resolve and its messages lost their date.
            val target = ((weekday + 1) % 7) + 1
            var guard = 0
            do {
                cal.add(Calendar.DAY_OF_YEAR, -1)
                guard++
            } while (cal.get(Calendar.DAY_OF_WEEK) != target && guard < 8)
            return if (guard < 8) cal.timeInMillis else 0L
        }
        val m = Regex("^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})$").find(l) ?: return 0L
        val day = m.groupValues[1].toIntOrNull() ?: return 0L
        val month = m.groupValues[2].toIntOrNull() ?: return 0L
        var year = m.groupValues[3].toIntOrNull() ?: return 0L
        if (year < 100) year += 2000
        return try {
            cal.set(year, month - 1, day, 0, 0, 0)
            cal.set(Calendar.MILLISECOND, 0)
            cal.timeInMillis
        } catch (_: Exception) {
            0L
        }
    }

    /**
     * Which side of the conversation this row sits on: true outgoing, false
     * incoming, null when the row gave nothing to go on.
     *
     * Delivery ticks come first because only the child's own messages have
     * them. Alignment is the fallback, compared as a *ratio* of the two side
     * gaps rather than a fixed margin: a long message nearly fills the width, so
     * an absolute margin read it as centred and the row lost its side. Nothing
     * is guessed — a row that reads as neither must stay unknown, because the
     * store uses the side to tell apart the same short text sent by both people.
     */
    private fun bubbleSide(
        bubble: AccessibilityNodeInfo?,
        textNode: AccessibilityNodeInfo,
        statusId: String,
    ): Boolean? {
        if (bubble != null) {
            if (bubble.findAccessibilityNodeInfosByViewId(statusId)
                    ?.isNotEmpty() == true
            ) {
                return true
            }
            if (hasStatusDescription(bubble, 0)) return true
        }
        sideOf(textNode)?.let { return it }
        return bubble?.let { sideOf(it) }
    }

    /**
     * True when [node] sits clearly to the right, false clearly to the left, and
     * null when the two gaps are too close to call.
     */
    private fun sideOf(node: AccessibilityNodeInfo): Boolean? {
        val screenWidth = resources.displayMetrics.widthPixels
        if (screenWidth <= 0) return null
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        if (bounds.width() <= 0) return null
        // +1 keeps the ratio finite when a bubble touches the screen edge.
        val leftGap = bounds.left + 1
        val rightGap = (screenWidth - bounds.right) + 1
        return when {
            leftGap > rightGap * SIDE_RATIO -> true
            rightGap > leftGap * SIDE_RATIO -> false
            else -> null
        }
    }

    /** Recursively checks a bubble for a delivery-status content-description. */
    private fun hasStatusDescription(node: AccessibilityNodeInfo, depth: Int): Boolean {
        if (depth > 6) return false
        val cd = node.contentDescription?.toString()?.lowercase(java.util.Locale.ROOT)
        if (cd != null && STATUS_WORDS.any { cd.contains(it) }) return true
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (hasStatusDescription(child, depth + 1)) return true
        }
        return false
    }

    /**
     * Returns the widest ancestor of [node] that still contains exactly one
     * message — i.e. this single message's row — so its date / status ticks
     * belong only to it. Returns null if none is found.
     */
    private fun tightBubble(
        node: AccessibilityNodeInfo,
        messageId: String,
    ): AccessibilityNodeInfo? {
        var cur: AccessibilityNodeInfo? = node.parent
        var best: AccessibilityNodeInfo? = null
        var depth = 0
        while (cur != null && depth < 4) {
            val msgs = cur.findAccessibilityNodeInfosByViewId(messageId)
            if (msgs != null && msgs.size > 1) break // ancestor spans >1 message
            best = cur
            cur = cur.parent
            depth++
        }
        return best
    }

    /** Returns the trimmed string if it looks like a phone number, else null. */
    private fun phoneLike(s: String?): String? {
        val t = s?.trim() ?: return null
        if (t.count { it.isDigit() } < 7) return null
        if (!Regex("^[+]?[0-9 ()\\-]{7,}$").matches(t)) return null
        return t
    }

    /**
     * Takes a screenshot of the current WhatsApp chat and OCRs it to text,
     * feeding any message-like lines into the store. This is a fallback for
     * content the node scrape misses (e.g. obfuscated views, image captions).
     *
     * Uses the accessibility screenshot API (no MediaProjection consent / cast
     * icon). Requires API 30+ and is heavily throttled.
     */
    private fun captureChatShot(pkg: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val now = System.currentTimeMillis()
        if (shotInFlight || now - lastShot < SHOT_INTERVAL_MS) return
        val chatName = try {
            rootInActiveWindow?.let { firstText(it, CHAT_SCRAPE[pkg]!!.titleId) }
        } catch (_: Exception) {
            null
        } ?: return // only inside an open conversation
        lastShot = now
        shotInFlight = true
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        onShot(screenshot, appLabel(pkg), chatName)
                    }

                    override fun onFailure(errorCode: Int) {
                        shotInFlight = false
                    }
                }
            )
        } catch (_: Exception) {
            shotInFlight = false
        }
    }

    /** Converts a screenshot to a software bitmap and runs OCR on it. */
    private fun onShot(screenshot: ScreenshotResult, app: String, chatName: String) {
        val buffer = screenshot.hardwareBuffer
        try {
            val hw = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
            if (hw == null) {
                shotInFlight = false
                return
            }
            // ML Kit needs a readable (software) bitmap.
            val bmp = hw.copy(Bitmap.Config.ARGB_8888, false)
            hw.recycle()
            if (bmp == null) {
                shotInFlight = false
                return
            }
            textRecognizer.process(InputImage.fromBitmap(bmp, 0))
                .addOnSuccessListener { result ->
                    for (block in result.textBlocks) {
                        for (line in block.lines) {
                            val text = line.text.trim()
                            if (isMessageLine(text)) {
                                MessageStore.record(app, chatName, text)
                                ContentWatch.message(
                                    this, app, chatName, text, false,
                                )
                            }
                        }
                    }
                    bmp.recycle()
                    shotInFlight = false
                }
                .addOnFailureListener {
                    bmp.recycle()
                    shotInFlight = false
                }
        } catch (_: Exception) {
            shotInFlight = false
        } finally {
            try {
                buffer.close()
            } catch (_: Exception) {
            }
        }
    }

    /** Filters out UI chrome / timestamps so only message-like text is kept. */
    private fun isMessageLine(text: String): Boolean {
        if (text.length < 2 || text.length > 400) return false
        // Drop bare timestamps like "10:24", "10:24 PM".
        if (Regex("^\\d{1,2}:\\d{2}(\\s?[AaPp][Mm])?$").matches(text)) return false
        // Must contain at least one letter or digit.
        if (!text.any { it.isLetterOrDigit() }) return false
        return true
    }

    private fun firstText(
        root: android.view.accessibility.AccessibilityNodeInfo,
        viewId: String,
    ): String? {
        return try {
            root.findAccessibilityNodeInfosByViewId(viewId)
                ?.firstOrNull { !it.text.isNullOrBlank() }
                ?.text?.toString()?.trim()
        } catch (_: Exception) {
            null
        }
    }

    private fun appLabel(pkg: String): String {
        return try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(pkg, 0)
            ).toString()
        } catch (_: Exception) {
            pkg.substringAfterLast('.').replaceFirstChar { it.uppercase() }
        }
    }

    private var lastIncognitoAction = 0L

    /**
     * Best-effort incognito/private-browsing block for devices that aren't
     * Device Owner (on Device Owner, incognito is disabled outright via a
     * managed config, so this never triggers). Detects the incognito indicator
     * and bounces the child out. Returns true if it acted.
     */
    private fun guardIncognito(): Boolean {
        if (!ChildStore.isPaired(this)) return false
        val now = System.currentTimeMillis()
        if (now - lastIncognitoAction < 1500) return false
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return false
        if (!isIncognito(root)) return false
        lastIncognitoAction = now
        showBlockPage(
            null,
            "Hare Krishna, private browsing is turned off on this phone.",
            title = "Incognito Disabled",
        )
        return true
    }

    /**
     * Detects an incognito/private session from the browser UI: the toolbar's
     * "incognito" indicator (content description) or the private New-Tab page
     * text. Bounded scan; precise markers to avoid false positives from page
     * content.
     */
    private fun isIncognito(root: AccessibilityNodeInfo): Boolean {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var scanned = 0
        while (queue.isNotEmpty() && scanned < 300) {
            val node = queue.removeFirst()
            scanned++
            // The toolbar's incognito/private badge has a SHORT content
            // description ("Incognito"). Match it exactly so the "New incognito
            // tab" MENU ITEM (which merely offers it) doesn't count.
            val cd = node.contentDescription?.toString()?.trim()?.lowercase()
            if (cd != null && cd in INCOGNITO_BADGES) {
                return true
            }
            // The private/incognito New-Tab page shows a distinctive sentence
            // that never appears in a menu.
            val t = node.text?.toString()?.lowercase()
            if (t != null && PRIVATE_MARKERS.any { t.contains(it) }) {
                return true
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return false
    }

    /** Reads the browser's URL/omnibox field and records the host it shows. */
    private fun captureBrowserUrl(pkg: String) {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return
        try {
            val addr = readBrowserAddress(root, pkg) ?: return
            if (!isEditingAddressBar()) enforceWebFilter(addr)
            maybeCaptureBrowserYoutube(root, addr)
        } catch (_: Exception) {
        }
    }

    /** Reads the browser's current address-bar text (URL-bar id first, then a
     *  generic URL-like node fallback). */
    private fun readBrowserAddress(root: AccessibilityNodeInfo, pkg: String): String? {
        // Each findAccessibilityNodeInfosByViewId is a binder round-trip, and
        // this used to try all ten ids on every window of every read. Remember
        // the one that worked for this browser and try it first.
        val known = urlBarIdCache[pkg]
        if (known != null) {
            textOfViewId(root, known)?.let { return it }
        }
        for (id in URL_BAR_IDS) {
            val viewId = if (id.contains(":")) id else "$pkg:id/$id"
            if (viewId == known) continue
            val text = textOfViewId(root, viewId)
            if (text != null) {
                urlBarIdCache[pkg] = viewId
                return text
            }
        }
        return findUrlLikeHost(root)
    }

    private fun textOfViewId(root: AccessibilityNodeInfo, viewId: String): String? {
        val nodes = root.findAccessibilityNodeInfosByViewId(viewId)
        if (nodes.isNullOrEmpty()) return null
        for (node in nodes) {
            val text = node.text?.toString()
            if (!text.isNullOrBlank()) return text
        }
        return null
    }

    /**
     * Reads the browser address bar across ALL accessibility windows. Chrome
     * (and most browsers) render the toolbar/URL-bar and the web content as
     * SEPARATE windows, so [rootInActiveWindow] often returns only the web page
     * — which is why a blocked site previously wasn't caught until a refresh
     * shifted the active window. Scanning every window makes blocking immediate.
     */
    private fun readAnyBrowserAddress(pkg: String): String? {
        try {
            for (w in windows) {
                val root = w.root ?: continue
                val addr = readBrowserAddress(root, pkg)
                if (addr != null) return addr
            }
        } catch (_: Exception) {
        }
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return null
        return readBrowserAddress(root, pkg)
    }

    /**
     * Fast, continuous browser guard: while a browser is foreground, re-reads
     * the address bar (across all windows) and blocks a filtered site
     * immediately — so protection is near-instant instead of waiting for an
     * accessibility event (which is why it previously only triggered on a
     * manual refresh).
     */
    /**
     * Updates [ForegroundApp] from the currently active/focused window. Relying
     * only on TYPE_WINDOW_STATE_CHANGED events is unreliable on some OEMs (e.g.
     * ColorOS/Realme), where opening an app can emit only content-changed events
     * — leaving the foreground stuck on the previous app so the web guards never
     * run. Reading the active window keeps the foreground package correct.
     */
    private fun refreshForegroundFromActiveWindow() {
        val pkg = try {
            windows?.firstOrNull { it.isActive }?.root?.packageName?.toString()
                ?: windows?.firstOrNull { it.isFocused }?.root?.packageName?.toString()
                ?: rootInActiveWindow?.packageName?.toString()
        } catch (_: Exception) {
            null
        }
        if (!pkg.isNullOrEmpty() && pkg != packageName) {
            ForegroundApp.set(pkg)
        }
    }

    /**
     * True while the child is typing in the address bar.
     *
     * The omnibox holds input focus then, so its text is a half-typed guess and
     * the suggestion list below it echoes those keystrokes back. Acting on
     * either blocked the child mid-word, before any page had been opened. A
     * field focused inside the page (a site's own search box) is deliberately
     * not counted: it sits below the toolbar, and blocking must keep working
     * while the child types there.
     */
    private fun isEditingAddressBar(): Boolean {
        val toolbarBottom = resources.displayMetrics.heightPixels * 0.18
        val rect = Rect()
        try {
            for (w in windows) {
                val root = w.root ?: continue
                val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                    ?: continue
                if (!focused.isEditable) continue
                val id = focused.viewIdResourceName
                if (id != null && URL_BAR_IDS.any { id == it || id.endsWith(":id/$it") }) {
                    return true
                }
                focused.getBoundsInScreen(rect)
                if (rect.top <= toolbarBottom) return true
            }
        } catch (_: Exception) {
        }
        return false
    }

    /** Returns true while a browser is foreground (so the caller polls fast). */
    private fun guardBrowserNow(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (pm != null && !pm.isInteractive) {
            WebHistoryStore.endVisit()
            return false
        }
        refreshForegroundFromActiveWindow()
        val pkg = ForegroundApp.packageName
        if (pkg.isEmpty() || !ForegroundApp.isBrowserForeground()) {
            WebHistoryStore.endVisit()
            return false
        }
        // Nothing is judged until the child has actually opened a page.
        if (isEditingAddressBar()) return true
        val addr = readAnyBrowserAddress(pkg)
        if (addr != null) {
            WebHistoryStore.recordVisit(addr)
            WebHistoryStore.recordSearch(addr)
            enforceWebFilter(addr)
        }
        // Also scan the page text for blocked keywords (throttled internally).
        scanPageContent()
        return true
    }

    /**
     * When the child is watching YouTube in a *browser* (youtube.com) rather
     * than the app, records the video into the YouTube history. The video title
     * is taken from the browser tab/page title (e.g. "Video Title - YouTube").
     */
    private fun maybeCaptureBrowserYoutube(
        root: AccessibilityNodeInfo,
        addressText: String,
    ) {
        val h = hostOf(addressText) ?: return
        if (h != "youtube.com" && !h.endsWith(".youtube.com") && h != "youtu.be") {
            return
        }
        val raw = (activeWindowTitle() ?: browserPageTitle(root))?.trim() ?: return
        // YouTube page titles look like "Video Title - YouTube". Anything else
        // (home feed, a channel, search) usually isn't a single watched video.
        val lower = raw.lowercase()
        if (!lower.endsWith("- youtube") && !lower.endsWith("- youtube.com")) return
        var name = raw
        val dash = name.lastIndexOf('-')
        if (dash > 0) name = name.substring(0, dash)
        name = name.trim().trimEnd('-', ' ')
        // Drop the notification-count prefix Chrome adds, e.g. "(3) Title".
        name = name.replace(Regex("^\\(\\d+\\)\\s*"), "").trim()
        if (name.length < 2 || name.equals("youtube", ignoreCase = true)) return
        // recordYt (not a bare record) so repeated captures of the same title
        // accrue watch time — otherwise a browser-watched video could never
        // cross the minimum-watched threshold and would stay invisible.
        recordYt(name, "")
    }

    /** The active window's accessibility title (Chrome sets this to the page
     *  title). Null if unavailable. */
    private fun activeWindowTitle(): String? {
        return try {
            windows?.firstOrNull { it.isActive }?.title?.toString()
                ?: windows?.firstOrNull { it.isFocused }?.title?.toString()
        } catch (_: Exception) {
            null
        }
    }

    /** Falls back to the WebView node's title/description when the window title
     *  isn't available. */
    private fun browserPageTitle(root: AccessibilityNodeInfo): String? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var steps = 0
        while (queue.isNotEmpty() && steps < 400) {
            steps++
            val n = queue.removeFirst()
            val cn = n.className?.toString() ?: ""
            if (cn.contains("WebView")) {
                val t = n.contentDescription?.toString() ?: n.text?.toString()
                if (!t.isNullOrBlank()) return t
            }
            for (i in 0 until n.childCount) {
                n.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    /**
     * Scans the view tree for a node whose text looks like a web address,
     * preferring the editable omnibox or a node in the top toolbar (so we don't
     * mistake an on-page link for the visited site). Bounded for performance.
     */
    private fun findUrlLikeHost(root: AccessibilityNodeInfo): String? {
        val toolbarBottom = resources.displayMetrics.heightPixels * 0.18
        var fallback: String? = null
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var scanned = 0
        val rect = Rect()
        while (queue.isNotEmpty() && scanned < 400) {
            val node = queue.removeFirst()
            scanned++
            val text = node.text?.toString()
            if (!text.isNullOrBlank() && !text.contains(' ')) {
                val host = hostOf(text)
                if (host != null) {
                    node.getBoundsInScreen(rect)
                    // The omnibox is editable or sits in the top toolbar.
                    if (node.isEditable || rect.top <= toolbarBottom) {
                        return host
                    }
                    if (fallback == null) fallback = host
                }
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return fallback
    }

    /** Blocks the page (leaves the site) when the address-bar host is filtered
     *  by the parent's rule, contains a blocked brand keyword (e.g.
     *  parimatch.com, pornhub.com), or is YouTube (always blocked in the browser
     *  — the child should use the YouTube app instead). */
    private fun enforceWebFilter(addressBarText: String) {
        val host = hostOf(addressBarText) ?: return
        val youtubeWeb = WebFilter.isYoutubeWeb(host)
        val brandHit = ContentFilter.matchHost(host)
        val filterReason = WebFilter.reasonFor(host)
        if (!youtubeWeb && filterReason == null && brandHit == null) return
        // Show the block page (it bounces off the unsafe page first).
        showBlockPage(
            host,
            if (youtubeWeb) "YouTube works in the app, not the browser."
            else "Hare Krishna, this website may not be safe for you"
        )
        // Prefer a real category over "the parent listed it", so a gambling site
        // reads as Gambling however it was caught.
        val brandCategory = brandHit?.let { ContentFilter.categoryOf(it) }
        val category = when {
            youtubeWeb -> WebFilter.REASON_YOUTUBE
            filterReason != null &&
                filterReason != WebFilter.REASON_BLOCKLIST -> filterReason
            brandCategory != null -> brandCategory
            else -> WebFilter.categoryHint(host)
                ?: filterReason
                ?: WebFilter.REASON_KEYWORD
        }
        WebHistoryStore.recordBlocked(host, category)
        val reason = when {
            youtubeWeb -> "YouTube is only allowed in the app"
            brandHit != null -> "matched \u201C$brandHit\u201D"
            else -> "on your block list"
        }
        AlertLog.log(
            this, "blockedWebsite",
            "Blocked $host ($reason)",
            throttleKey = "site:$host",
            category = category,
        )
    }

    /** Shows the block message as a brief floating notice, throttled so repeated
     *  scans of the same page don't spam it. Uses an overlay (not a system toast)
     *  so it shows even while GuardNest is backgrounded. */
    /**
     * Sends the browser back off the unsafe page and shows the full-screen
     * [BlockActivity] block page. Throttled so a burst of detections doesn't
     * relaunch it (the singleTask activity dedupes anyway). The bounce happens
     * while the browser is still foreground, so it's hidden behind the block
     * page and closing the page returns the child to the previous safe page.
     */
    private fun showBlockPage(
        host: String?,
        message: String,
        title: String = "",
    ) {
        val now = System.currentTimeMillis()
        if (now - lastBlockPageAt < 1200) return
        lastBlockPageAt = now
        performGlobalAction(GLOBAL_ACTION_BACK)
        try {
            startActivity(
                Intent(this, BlockActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    .putExtra(BlockActivity.EXTRA_HOST, host ?: "")
                    .putExtra(BlockActivity.EXTRA_MESSAGE, message)
                    .putExtra(BlockActivity.EXTRA_TITLE, title)
            )
        } catch (_: Exception) {
        }
    }

    private var lastContentScan = 0L

    /**
     * Scans the browser's *visible page text* for unsafe content and bounces
     * out of the page if it matches ([ContentFilter]). This is content-based
     * blocking that works on HTTPS (it reads the rendered text, not the network)
     * and complements the URL/host filter. Reads text across ALL windows — the
     * browser toolbar and the web page are separate windows, so reading only the
     * active window would miss the page's own text. Throttled for performance.
     */
    private fun scanPageContent() {
        val now = System.currentTimeMillis()
        if (now - lastContentScan < 250L) return
        lastContentScan = now
        // Only scan an actually-loaded web page. When there's no clear host the
        // child is typing in the search bar / on a new-tab or suggestions view —
        // never block that. Also skip search-engine result pages (link lists).
        val curHost = hostOf(readAnyBrowserAddress(ForegroundApp.packageName) ?: "")
        if (curHost == null || WebFilter.isSearchEngine(curHost)) return
        // Match each window's text independently so one text-heavy window can't
        // use up the character budget before the page's own window is scanned.
        var hit: String? = null
        try {
            for (w in windows) {
                val r = w.root ?: continue
                val t = collectText(r, StringBuilder(), 0).toString().lowercase()
                hit = ContentFilter.match(t)
                if (hit != null) break
            }
        } catch (_: Exception) {
        }
        if (hit == null) {
            val root = try {
                rootInActiveWindow
            } catch (_: Exception) {
                null
            } ?: return
            hit = ContentFilter.match(
                collectText(root, StringBuilder(), 0).toString().lowercase()
            )
        }
        val matched = hit ?: return
        val host = hostOf(readAnyBrowserAddress(ForegroundApp.packageName) ?: "")
        val category = ContentFilter.categoryOf(matched)
            ?: WebFilter.categoryHint(host ?: "")
            ?: WebFilter.REASON_CONTENT
        showBlockPage(host, "Hare Krishna, this website may not be safe for you")
        if (host != null) {
            WebHistoryStore.recordBlocked(host, category)
        }
        AlertLog.log(
            this, "blockedWebsite",
            "Blocked ${host ?: "a page"} (unsafe content: \u201C$matched\u201D)",
            throttleKey = "content:${host ?: matched}",
            category = category,
        )
    }

    /**
     * Captures the browser screen for OCR in [onImageShot], which reads the
     * words rendered on the page (text the accessibility tree hides) and blocks
     * on any unsafe word. Runs only while a browser is foreground and the screen
     * is on, is heavily throttled, and uses the accessibility screenshot API
     * (API 30+), so there's no MediaProjection consent / cast icon.
     */
    private fun guardBrowserImageNow(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        if (!ChildStore.isPaired(this)) return false
        val pkg = ForegroundApp.packageName
        if (pkg.isEmpty() || !ForegroundApp.isBrowserForeground()) {
            lastFrameSig = 0L
            return false
        }
        val now = System.currentTimeMillis()
        if (imgShotInFlight || now - lastImgShot < IMAGE_GUARD_MS) return true
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (pm != null && !pm.isInteractive) return false // screen off — nothing to scan
        lastImgShot = now
        imgShotInFlight = true
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        onImageShot(screenshot)
                    }

                    override fun onFailure(errorCode: Int) {
                        imgShotInFlight = false
                    }
                }
            )
        } catch (_: Exception) {
            imgShotInFlight = false
        }
        return true
    }

    /**
     * Converts the screenshot to a software bitmap and OCRs it, reading the
     * words actually rendered on the page — catching unsafe text the
     * accessibility tree never exposes (image text, canvas- or WebGL-drawn
     * pages, obfuscated views), which is why some sites slipped past the
     * node-text scan. It only runs here (browser foreground) — never
     * system-wide.
     */
    private fun onImageShot(screenshot: ScreenshotResult) {
        val buffer = screenshot.hardwareBuffer
        val bmp: Bitmap? = try {
            val hw = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
            val copy = hw?.copy(Bitmap.Config.ARGB_8888, false)
            hw?.recycle()
            copy
        } catch (_: Exception) {
            null
        } finally {
            try {
                buffer.close()
            } catch (_: Exception) {
            }
        }
        if (bmp == null) {
            imgShotInFlight = false
            return
        }

        // Skip the OCR when the screen is unchanged since the last scan (a static
        // page) so the costly text recognition runs only on new content.
        val sig = ImageContentFilter.signature(bmp)
        if (sig != 0L && sig == lastFrameSig) {
            bmp.recycle()
            imgShotInFlight = false
            return
        }
        lastFrameSig = sig

        // OCR the rendered page and block on any unsafe word ([ContentFilter]).
        try {
            textRecognizer.process(InputImage.fromBitmap(bmp, 0))
                .addOnSuccessListener { result ->
                    try {
                        val hit = ContentFilter.match(result.text.lowercase())
                        if (hit != null) blockOcrContent(hit)
                    } catch (_: Exception) {
                    }
                    bmp.recycle()
                    imgShotInFlight = false
                }
                .addOnFailureListener {
                    bmp.recycle()
                    imgShotInFlight = false
                }
        } catch (_: Exception) {
            bmp.recycle()
            imgShotInFlight = false
        }
    }

    /** Leaves the current page and logs an alert after OCR reads an unsafe word
     *  that the on-screen accessibility text tree didn't expose. */
    private fun blockOcrContent(matched: String) {
        val host = hostOf(readAnyBrowserAddress(ForegroundApp.packageName) ?: "")
        // Only block a real loaded page — not the search bar / suggestions (no
        // host) and not search-engine result pages (they only list links).
        if (host == null || WebFilter.isSearchEngine(host)) return
        val category = ContentFilter.categoryOf(matched)
            ?: WebFilter.categoryHint(host)
            ?: WebFilter.REASON_CONTENT
        showBlockPage(host, "Hare Krishna, this website may not be safe for you")
        WebHistoryStore.recordBlocked(host, category)
        AlertLog.log(
            this, "blockedWebsite",
            "Blocked $host (unsafe content: \u201C$matched\u201D)",
            throttleKey = "content:$host",
            category = category,
        )
    }

    /** Extracts a bare host from an address-bar value, or null if it's a query. */
    private fun hostOf(raw: String): String? {
        var s = raw.trim().lowercase()
        if (s.isEmpty() || s.contains(' ')) return null // a search query, not a URL
        s = s.removePrefix("https://").removePrefix("http://")
        s = s.substringBefore('/').substringBefore('?').substringBefore('#')
        s = s.substringBefore(':') // strip any port
        s = s.removePrefix("www.")
        return if (s.isEmpty() || !s.contains('.')) null else s
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        AccessibilityController.service = this
        // The stall clock has to stop the moment events flow again, or a kill
        // that repaired itself would still trip the lockbox 10 minutes later.
        ChildStore.setAccessibilityStallSince(this, 0L)
        Permissions.invalidateCache()
        // If the child is coming back from Temporary Access, re-enabling
        // accessibility is the "restore protection" signal — lift the call-log/
        // SMS denials right away so monitoring resumes without waiting for a tick.
        EnforcementService.restoreTempAccessIfRecovered(this)
        ytHandler.postDelayed(ytPump, YT_PUMP_MS)
        ytHandler.postDelayed(browserGuard, BROWSER_GUARD_MS)
        ytHandler.postDelayed(imageGuard, IMAGE_GUARD_MS)
    }

    override fun onDestroy() {
        WebHistoryStore.endVisit()
        AccessibilityController.service = null
        ytHandler.removeCallbacks(ytPump)
        ytHandler.removeCallbacks(browserGuard)
        ytHandler.removeCallbacks(imageGuard)
        super.onDestroy()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        WebHistoryStore.endVisit()
        AccessibilityController.service = null
        ytHandler.removeCallbacks(ytPump)
        ytHandler.removeCallbacks(browserGuard)
        ytHandler.removeCallbacks(imageGuard)
        return super.onUnbind(intent)
    }

    private companion object {
        /** Minimum gap between OCR screenshots of a chat (ms). */
        const val SHOT_INTERVAL_MS = 4000L

        /** Minimum gap between full view-tree scans for tamper / app-management
         *  screens. Keeps detection near-instant without re-walking the tree for
         *  every content-changed event while the child scrolls. */
        const val SCAN_THROTTLE_MS = 300L

        /** Minimum gap between the per-event chat / YouTube tree scans. */
        const val CAPTURE_THROTTLE_MS = 500L

        /** Faster chat scan while the child is actively scrolling WhatsApp. The
         *  floating date pill only shows during a scroll and fades ~1s after it
         *  stops, so a quicker cadence catches it before it disappears; it
         *  applies to scroll events only, so there's no cost while idle. */
        const val CHAT_SCROLL_THROTTLE_MS = 200L

        /** Conversation rows sit far deeper than a typical view tree — WhatsApp
         *  nests them 25-60 levels down. */
        const val CHAT_SCAN_MAX_DEPTH = 80

        /** Weekday separator labels, Monday first to match Calendar.MONDAY. */
        val WEEKDAYS = listOf(
            "monday", "tuesday", "wednesday", "thursday", "friday",
            "saturday", "sunday",
        )

        /** Search-box ids used by YouTube and its forks, newest first. */
        val YT_SEARCH_IDS = listOf(
            "search_edit_text", "search_bar_text", "search_box_text",
            "search_query", "search_term",
        )

        /** How much wider one side gap must be to call a chat bubble's side. */
        const val SIDE_RATIO = 1.6f

        /** A chat bubble's own time label, e.g. "10:24 pm" or "22:04". */
        val CLOCK_RE = Regex("^\\d{1,2}:\\d{2}\\s?([AaPp][Mm])?$")

        /** Max gap between YouTube captures still counted as continuous watching. */
        const val YT_MAX_GAP_MS = 15_000L
        /** How often the watch-time pump ticks while a video plays full-screen. */
        const val YT_PUMP_MS = 8_000L
        /** How often the browser guard re-checks the address bar for blocked sites. */
        const val BROWSER_GUARD_MS = 400L
        /** How often it looks again while no browser is open. */
        const val BROWSER_IDLE_MS = 2_000L
        /** How often the browser OCR guard screenshots the browser (ms). A
         *  static page skips the OCR pass (see the frame signature), so this can
         *  stay responsive without a real battery cost. */
        const val IMAGE_GUARD_MS = 2_000L
        /** How long a feed video must stay centred before it counts as watched
         *  — only videos actually watched (>30s), not scrolled past, are logged. */
        const val FEED_DWELL_MS = 30_000L
        /** How long a Short must stay on screen before it counts as watched. */
        const val SHORT_DWELL_MS = 3_000L

        /** Delivery-status words (in a bubble's description) that mark it outgoing. */
        val STATUS_WORDS = listOf("delivered", "read", "sent", "pending")

        /** YouTube UI labels that aren't actual video titles. */
        val YT_NOISE = setOf(
            "home", "shorts", "subscriptions", "library", "you", "search",
            "explore", "trending", "notifications", "downloads", "history",
        )

        /** YouTube Shorts (reel) container view ids — presence means Shorts. */
        val REEL_IDS = listOf(
            "reel_player_page_container",
            "reel_recycler",
            "reel_watch_player",
            "reel_player_underlay",
            "shorts_video_cell",
        )

        /** Matches like/view/comment/subscriber counts so they aren't taken as
         *  a Shorts caption/title. */
        val YT_COUNT = Regex(
            "\\d+([.,]\\d+)?\\s*[kmb]?\\s*(likes?|views?|comments?|subscribers?|shares?)",
            RegexOption.IGNORE_CASE,
        )

        // Address-bar view ids across common browsers. Bare ids are prefixed
        // with the current package; fully-qualified ids are used as-is.
        val URL_BAR_IDS = listOf(
            "url_bar", // Chrome, Brave, Edge, most Chromium browsers
            "com.android.chrome:id/url_bar",
            "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
            "org.mozilla.focus:id/mozac_browser_toolbar_url_view",
            "com.sec.android.app.sbrowser:id/location_bar_edit_text",
            "com.opera.browser:id/url_field",
            "com.opera.mini.native:id/url_field",
            "com.microsoft.emmx:id/url_bar",
            "location_bar_edit_text",
            "url_field",
        )

        /** Conversation-view ids used to scrape visible chat text per app. */
        data class ChatIds(
            val messageId: String,
            val titleId: String,
            val dateId: String,
            val subtitleId: String,
            val statusId: String,
            val dividerId: String,
        )

        val CHAT_SCRAPE: Map<String, ChatIds> = mapOf(
            "com.whatsapp" to ChatIds(
                "com.whatsapp:id/message_text",
                "com.whatsapp:id/conversation_contact_name",
                "com.whatsapp:id/date",
                "com.whatsapp:id/conversation_contact_status",
                "com.whatsapp:id/status",
                "com.whatsapp:id/conversation_row_date_divider",
            ),
            "com.whatsapp.w4b" to ChatIds(
                "com.whatsapp.w4b:id/message_text",
                "com.whatsapp.w4b:id/conversation_contact_name",
                "com.whatsapp.w4b:id/date",
                "com.whatsapp.w4b:id/conversation_contact_status",
                "com.whatsapp.w4b:id/status",
                "com.whatsapp.w4b:id/conversation_row_date_divider",
            ),
        )

        /** Settings / installer packages where tamper screens can appear. */
        val SENSITIVE_PACKAGES = setOf(
            "com.android.settings",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.miui.packageinstaller",
            "com.oplus.packageinstaller",
            "com.coloros.packageinstaller",
            "com.samsung.android.packageinstaller",
        )

        /** Words that mark a deactivate-admin / uninstall / disable screen. */
        val DANGER_KEYWORDS = listOf(
            "deactivate", "uninstall", "device admin", "device administrator",
            "turn off", "disable", "remove", "force stop",
        )

        /** Exact toolbar badge content-descriptions shown ONLY in an active
         *  private/incognito tab (not in menus). */
        val INCOGNITO_BADGES = setOf(
            "incognito", "private", "private tab", "secret mode",
        )

        /** Sentences that appear only on a private/incognito New-Tab page —
         *  never in a menu — so we detect a real private session, not the
         *  "New incognito tab" menu item. */
        val PRIVATE_MARKERS = listOf(
            "you’ve gone incognito", "you've gone incognito",
            "you have gone incognito",
            "you’re browsing privately", "you're browsing privately",
            "you’re in a private", "you're in a private",
            "now you can browse privately", "you can browse privately",
            "you are browsing privately",
        )

        /** Markers of the Settings "App info" page (any app). Two+ ⇒ app-info. */
        val APP_INFO_MARKERS = listOf(
            "uninstall", "force stop", "app info", "app details",
            "storage & cache", "storage and cache", "clear data",
            "clear storage", "open by default", "disable app",
        )
    }
}

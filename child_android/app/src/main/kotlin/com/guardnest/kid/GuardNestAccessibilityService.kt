package com.guardnest.kid

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import com.google.firebase.firestore.FirebaseFirestore
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

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
    private var lastBlockToast = 0L
    private var lastShot = 0L
    @Volatile private var shotInFlight = false
    // YouTube watch-time tracking (current video + last capture time).
    private var lastYtTitle: String? = null
    private var lastYtTickAt = 0L
    private val textRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val type = event?.eventType ?: return
        val pkg = event.packageName?.toString() ?: return

        // Anti-tamper first: block deactivate-admin / uninstall of GuardNest.
        if (guardTamperScreens(pkg)) return

        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            ForegroundApp.set(pkg)
            // If a required protection was turned off, only let the child use the
            // apps needed to fix it — everything else is bounced to GuardNest.
            if (guardPermissionLockdown(pkg)) return
            if (pkg != packageName && BlockedApps.isBlocked(pkg)) {
                // Kick the child out of the blocked app.
                performGlobalAction(GLOBAL_ACTION_HOME)
                val now = System.currentTimeMillis()
                if (now - lastToast > 2000) {
                    lastToast = now
                    Toast.makeText(
                        this, "This app is blocked by your parent.", Toast.LENGTH_SHORT
                    ).show()
                }
                return
            }
        }

        // For a browser, read the address bar and record the visited site.
        if (pkg != packageName && ForegroundApp.isBrowserForeground()) {
            captureBrowserUrl(pkg)
        }

        // For a messaging app (WhatsApp only), read the visible on-screen chat text.
        if (pkg != packageName && CHAT_SCRAPE.containsKey(pkg)) {
            captureChatText(pkg)
            // Note: OCR screenshot capture is intentionally NOT used for chats —
            // it can't tell a message's side or time, which mangled the display.
        }

        // In the YouTube app (official, Vanced or ReVanced), record the video
        // the child is watching.
        if (pkg in YOUTUBE_PKGS) {
            captureYoutube(pkg)
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
        } ?: return
        try {
            val meta = root
                .findAccessibilityNodeInfosByViewId("$pkg:id/video_metadata_layout")
                ?.firstOrNull() ?: return
            val texts = ArrayList<String>()
            collectTexts(meta, texts, 0)
            // The first substantial, non-UI line is the video title.
            val title = texts.firstOrNull {
                it.length >= 2 && it.lowercase() !in YT_NOISE
            } ?: return
            // Channel: prefer an "@handle"; else the line right after the title
            // (skipping the like/view/date summary line).
            val channel = texts.firstOrNull { it.startsWith("@") }
                ?: texts.getOrNull(texts.indexOf(title) + 1)
                    ?.takeIf { !it.contains("views", true) && it.lowercase() !in YT_NOISE }
                ?: ""
            // Accumulate watch time: add the gap since the last capture of the
            // SAME video (ignoring big gaps that mean the child was away/paused).
            val now = System.currentTimeMillis()
            val addMs = if (title == lastYtTitle) {
                val d = now - lastYtTickAt
                if (d in 1..YT_MAX_GAP_MS) d else 0L
            } else 0L
            lastYtTitle = title
            lastYtTickAt = now
            YoutubeStore.record(title, channel, addMs)
        } catch (_: Exception) {
        }
    }

    /** Depth-first collects up to a few visible text lines from a node subtree. */
    private fun collectTexts(node: AccessibilityNodeInfo, out: MutableList<String>, depth: Int) {
        if (depth > 8 || out.size > 12) return
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
    private fun guardTamperScreens(pkg: String): Boolean {
        if (!ChildStore.isPaired(this)) return false
        if (!DeviceLockdown.isAdminActive(this)) return false
        val isSensitive = pkg in SENSITIVE_PACKAGES ||
            pkg.contains("settings") || pkg.contains("packageinstaller")
        if (!isSensitive) return false

        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return false

        val text = collectText(root, StringBuilder(), 0).toString().lowercase()
        // Only act when this screen is clearly about GuardNest AND offers a
        // deactivate / uninstall / disable action.
        val mentionsUs = text.contains("guardnest")
        val dangerous = DANGER_KEYWORDS.any { text.contains(it) }
        if (mentionsUs && dangerous) {
            // Self-heal: confirm the device is still linked. If the parent has
            // removed it, release device admin so uninstall is allowed instead
            // of blocking it.
            verifyStillLinked()
            performGlobalAction(GLOBAL_ACTION_BACK)
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
                if (!doc.exists()) {
                    ChildStore.clear(this)
                    DeviceLockdown.releaseForRemoval(this)
                    WebFilterVpnService.stop(this)
                }
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
        if (Permissions.allGranted(this)) return false
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
                "Turn GuardNest's permissions back on to use your apps.",
                Toast.LENGTH_LONG
            ).show()
        }
        return true
    }

    private fun isAllowedDuringLockdown(pkg: String): Boolean {
        if (pkg == packageName || pkg == "android") return true
        return pkg.contains("settings") ||
            pkg.contains("packageinstaller") ||
            pkg.contains("permissioncontroller") ||
            pkg.contains("launcher") ||
            pkg.contains("systemui") ||
            pkg.contains("vpndialogs") ||
            pkg.endsWith(".home")
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
            // Only scrape inside an actual conversation (title present), not the
            // chat list, so we don't log contact names as messages.
            val nodes = root.findAccessibilityNodeInfosByViewId(ids.messageId)
                ?: return
            for (node in nodes) {
                val text = node.text?.toString()?.trim()
                if (text.isNullOrBlank()) continue
                // Isolate this one message's row so the time and the send/read
                // ticks can't be confused with a neighbouring message.
                val bubble = tightBubble(node, ids.messageId)
                val timeLabel = bubble
                    ?.findAccessibilityNodeInfosByViewId(ids.dateId)
                    ?.firstOrNull { !it.text.isNullOrBlank() }
                    ?.text?.toString()?.trim().orEmpty()
                // WhatsApp draws the delivery/read status ticks only on the
                // child's OWN (outgoing) messages — the definitive side signal.
                val outgoing = bubbleOutgoing(bubble, ids.statusId)
                MessageStore.record(
                    appLabel(pkg), chatName, text, outgoing, timeLabel, number
                )
            }
        } catch (_: Exception) {
        }
    }

    /**
     * True if this message row is the child's own (outgoing). Detected by the
     * send/read tick icon — first by its view id, then (since icon views are
     * often excluded from the accessibility tree) by any node whose
     * content-description reports a delivery status.
     */
    private fun bubbleOutgoing(
        bubble: AccessibilityNodeInfo?,
        statusId: String,
    ): Boolean {
        if (bubble == null) return false
        if (bubble.findAccessibilityNodeInfosByViewId(statusId)?.isNotEmpty() == true) {
            return true
        }
        return hasStatusDescription(bubble, 0)
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
                            if (isMessageLine(text)) MessageStore.record(app, chatName, text)
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

    /** Reads the browser's URL/omnibox field and records the host it shows. */
    private fun captureBrowserUrl(pkg: String) {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return
        try {
            for (id in URL_BAR_IDS) {
                val viewId = if (id.contains(":")) id else "$pkg:id/$id"
                val nodes = root.findAccessibilityNodeInfosByViewId(viewId)
                if (nodes.isNullOrEmpty()) continue
                for (node in nodes) {
                    val text = node.text?.toString()
                    if (!text.isNullOrBlank()) {
                        WebHistoryStore.recordVisit(text)
                        enforceWebFilter(text)
                        return
                    }
                }
            }
        } catch (_: Exception) {
        }
    }

    /** Blocks the page (leaves the site) when the address-bar host is filtered. */
    private fun enforceWebFilter(addressBarText: String) {
        val host = hostOf(addressBarText) ?: return
        if (!WebFilter.isBlocked(host)) return
        // Leave the blocked site.
        performGlobalAction(GLOBAL_ACTION_BACK)
        val now = System.currentTimeMillis()
        if (now - lastBlockToast > 1500) {
            lastBlockToast = now
            Toast.makeText(
                this, "This site is blocked by your parent.", Toast.LENGTH_SHORT
            ).show()
        }
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

    private companion object {
        /** YouTube app packages: official plus the common Vanced/ReVanced forks. */
        val YOUTUBE_PKGS = setOf(
            "com.google.android.youtube",
            "app.vanced.android.youtube",
            "app.revanced.android.youtube",
            "app.rvx.android.youtube",
        )

        /** Minimum gap between OCR screenshots of a chat (ms). */
        const val SHOT_INTERVAL_MS = 4000L

        /** Max gap between YouTube captures still counted as continuous watching. */
        const val YT_MAX_GAP_MS = 15_000L

        /** Delivery-status words (in a bubble's description) that mark it outgoing. */
        val STATUS_WORDS = listOf("delivered", "read", "sent", "pending")

        /** YouTube UI labels that aren't actual video titles. */
        val YT_NOISE = setOf(
            "home", "shorts", "subscriptions", "library", "you", "search",
            "explore", "trending", "notifications", "downloads", "history",
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
        )

        val CHAT_SCRAPE: Map<String, ChatIds> = mapOf(
            "com.whatsapp" to ChatIds(
                "com.whatsapp:id/message_text",
                "com.whatsapp:id/conversation_contact_name",
                "com.whatsapp:id/date",
                "com.whatsapp:id/conversation_contact_status",
                "com.whatsapp:id/status",
            ),
            "com.whatsapp.w4b" to ChatIds(
                "com.whatsapp.w4b:id/message_text",
                "com.whatsapp.w4b:id/conversation_contact_name",
                "com.whatsapp.w4b:id/date",
                "com.whatsapp.w4b:id/conversation_contact_status",
                "com.whatsapp.w4b:id/status",
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
    }
}

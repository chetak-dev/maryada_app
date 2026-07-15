package com.guardnest.kid

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Always-on enforcement. Keeps the family's screen-time rule applied locally so
 * bedtime/pause work even offline. The rule is kept fresh by a Firestore
 * snapshot listener (which also serves cached data when offline); a timer
 * re-evaluates by local clock and locks the device when it should be locked.
 *
 * Runs as a foreground service so the OS won't kill it. Transparent by design —
 * the persistent notification tells the child GuardNest is active.
 */
class EnforcementService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var listener: ListenerRegistration? = null
    private var appRulesListener: ListenerRegistration? = null
    private var webFilterListener: ListenerRegistration? = null
    private var childDocListener: ListenerRegistration? = null
    private var currentBlocked: Set<String> = emptySet()

    @Volatile
    private var rule = ScreenTimeRule()

    private val tick = object : Runnable {
        override fun run() {
            // Heartbeat first, and wrap everything so one failing task can never
            // kill the loop (which would make the parent show the child offline).
            try {
                heartbeat()
                enforce()
                reportLocation()
                reportUsage()
                reportWebHistory()
                reportCallHistory()
                reportSmsHistory()
                reportMessages()
                reportYoutubeHistory()
                promptForMissingPermissions()
            } catch (_: Throwable) {
                // Ignore — always reschedule below.
            } finally {
                handler.postDelayed(this, EVAL_INTERVAL_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        startAsForeground()
        attachRuleListener()
        attachAppRulesListener()
        attachWebFilterListener()
        attachChildDocListener()
        registerPackageChanges()
        DeviceLockdown.applyTamperProtection(this)
        reportInstalledApps()
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY // restart if the OS kills us
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        listener?.remove()
        appRulesListener?.remove()
        webFilterListener?.remove()
        childDocListener?.remove()
        unregisterPackageChanges()
        LockOverlay.hide(this)
        super.onDestroy()
    }

    /**
     * Re-reports the installed app list when an app is installed or uninstalled,
     * so the parent's app list stays in sync (e.g. removed apps disappear).
     */
    private var packageReceiver: BroadcastReceiver? = null

    private fun registerPackageChanges() {
        if (packageReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                reportInstalledApps()
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_FULLY_REMOVED)
            addDataScheme("package")
        }
        try {
            registerReceiver(receiver, filter)
            packageReceiver = receiver
        } catch (_: Exception) {
        }
    }

    private fun unregisterPackageChanges() {
        packageReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        packageReceiver = null
    }

    /**
     * Watches this device's own child doc. If the parent removes the device (the
     * doc is deleted), the child unpairs itself. The heartbeat's permission-denied
     * failure is the reliable backstop when rules hide the delete event.
     */
    private fun attachChildDocListener() {
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        childDocListener = FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .addSnapshotListener { snap, _ ->
                if (snap != null && !snap.exists() && !snap.metadata.isFromCache) {
                    unpair()
                }
            }
    }

    /** Clears local pairing, stops the filter, and shuts the service down. */
    private fun unpair() {
        handler.removeCallbacks(tick)
        listener?.remove()
        appRulesListener?.remove()
        webFilterListener?.remove()
        childDocListener?.remove()
        unregisterPackageChanges()
        LockOverlay.hide(this)
        // The parent removed this device -> allow it to be uninstalled again.
        DeviceLockdown.releaseForRemoval(this)
        WebFilterVpnService.stop(this)
        ChildStore.clear(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun attachRuleListener() {
        val familyId = ChildStore.familyId(this) ?: return
        listener = FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("rules").document("screenTime")
            .addSnapshotListener { snap, _ ->
                if (snap != null && snap.exists()) {
                    fun i(k: String, d: Int) = (snap.get(k) as? Number)?.toInt() ?: d
                    rule = ScreenTimeRule(
                        dailyLimitMinutes = i("dailyLimitMinutes", 120),
                        bedtimeEnabled = snap.getBoolean("bedtimeEnabled") ?: false,
                        bedtimeStart = i("bedtimeStart", 21 * 60),
                        bedtimeEnd = i("bedtimeEnd", 7 * 60),
                        paused = snap.getBoolean("paused") ?: false,
                    )
                    // React immediately when the parent pauses/unpauses.
                    enforce()
                }
            }
    }

    private fun enforce() {
        val lock = ScreenGuard.shouldLock(
            rule.paused, rule.bedtimeEnabled, rule.bedtimeStart, rule.bedtimeEnd
        )
        if (lock) {
            val title = if (rule.paused) "Paused" else "Bedtime"
            val subtitle = if (rule.paused)
                "Your device is paused by your parent."
            else
                "It’s bedtime. Your device is resting."
            LockOverlay.show(this, title, subtitle)
        } else {
            LockOverlay.hide(this)
        }
    }

    private var lastHeartbeat = 0L

    /** Periodically tells the parent this device is online (throttled). */
    private fun heartbeat() {
        val now = System.currentTimeMillis()
        if (now - lastHeartbeat < HEARTBEAT_MS) return
        lastHeartbeat = now
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .set(
                mapOf(
                    "online" to true,
                    "lastSeenAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
            .addOnFailureListener { e ->
                // The parent removed this device -> our write is rejected. Unpair.
                if (e is FirebaseFirestoreException &&
                    e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED
                ) {
                    unpair()
                }
            }
    }

    private var lastLocationReport = 0L
    private var lastLocationHistory = 0L

    /**
     * Reports the device's location to the parent (throttled). Uses the
     * framework LocationManager (no extra libraries). Silently skips when the
     * location permission isn't granted or device location is off.
     */
    private fun reportLocation() {
        val now = System.currentTimeMillis()
        if (now - lastLocationReport < LOCATION_MS) return
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) return

        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager

        // 1) Report any cached fix right away.
        val cached: Location? = try {
            lm.getProviders(true)
                .mapNotNull { p -> runCatching { lm.getLastKnownLocation(p) }.getOrNull() }
                .maxByOrNull { it.time }
        } catch (_: SecurityException) {
            null
        }
        if (cached != null) writeLocation(cached)

        // 2) Also request a fresh fix (covers the case where there's no cache yet).
        requestFreshFix(lm)
    }

    /** Asks the OS for a single fresh location and reports it when it arrives. */
    private fun requestFreshFix(lm: LocationManager) {
        val providers = lm.getProviders(true).filter {
            it == LocationManager.GPS_PROVIDER || it == LocationManager.NETWORK_PROVIDER
        }
        if (providers.isEmpty()) return
        try {
            val listener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    writeLocation(location)
                    try {
                        lm.removeUpdates(this)
                    } catch (_: Exception) {
                    }
                }

                @Deprecated("Required on older APIs")
                override fun onStatusChanged(p: String?, status: Int, extras: Bundle?) {}
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
            }
            for (provider in providers) {
                lm.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            }
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }
    }

    /** Writes a location fix to the child doc + history (throttled by [LOCATION_MS]). */
    private fun writeLocation(loc: Location) {
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        lastLocationReport = System.currentTimeMillis()
        val lat = loc.latitude
        val lng = loc.longitude
        val acc = loc.accuracy.toDouble()

        Thread {
            val address = reverseGeocode(lat, lng)
            val childRef = FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("children").document(childId)

            val current = hashMapOf<String, Any>(
                "lat" to lat,
                "lng" to lng,
                "locationAccuracy" to acc,
                "locationUpdatedAt" to FieldValue.serverTimestamp(),
            )
            if (address != null) current["address"] = address
            childRef.set(current, SetOptions.merge())

            // Append to the history trail at most once every 30 minutes so it
            // stays a coarse timeline rather than a dense stream of points.
            val now = System.currentTimeMillis()
            if (now - lastLocationHistory >= LOCATION_HISTORY_MS) {
                lastLocationHistory = now
                val point = hashMapOf<String, Any>(
                    "lat" to lat,
                    "lng" to lng,
                    "locationAccuracy" to acc,
                    "at" to FieldValue.serverTimestamp(),
                )
                if (address != null) point["address"] = address
                childRef.collection("locationHistory").add(point)
            }
        }.start()
    }

    /** Turns coordinates into a short human-readable place name (best effort). */
    private fun reverseGeocode(lat: Double, lng: Double): String? {
        return try {
            @Suppress("DEPRECATION")
            val results = Geocoder(this, Locale.getDefault()).getFromLocation(lat, lng, 1)
            val addr = results?.firstOrNull() ?: return null
            val parts = listOfNotNull(
                addr.thoroughfare ?: addr.featureName,
                addr.subLocality ?: addr.locality,
            ).distinct()
            if (parts.isNotEmpty()) parts.joinToString(", ") else addr.getAddressLine(0)
        } catch (_: Exception) {
            null
        }
    }

    private var lastUsageReport = 0L

    /**
     * Reports screen-time usage (last 7 days + today's top apps) to the parent,
     * throttled. Needs the "Usage access" grant; silently skips otherwise.
     */
    private fun reportUsage() {
        val now = System.currentTimeMillis()
        if (now - lastUsageReport < USAGE_MS) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val summary = UsageReporter.build(this) ?: return
        lastUsageReport = now

        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("usage").document("summary")
            .set(
                mapOf(
                    "week" to summary.week.map {
                        mapOf("day" to it.label, "minutes" to it.minutes)
                    },
                    "topApps" to summary.topApps.map {
                        mapOf(
                            "packageName" to it.packageName,
                            "appName" to it.label,
                            "minutes" to it.minutes,
                        )
                    },
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    private var lastWebHistoryReport = 0L

    /**
     * Reports the child's web history (real sites visited from the browser
     * address bar + blocked attempts from the DNS filter). Throttled, and only
     * when there's new data.
     */
    private fun reportWebHistory() {
        val now = System.currentTimeMillis()
        if (now - lastWebHistoryReport < WEBHISTORY_MS) return
        if (!WebHistoryStore.hasChanges()) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val (visited, blocked) = WebHistoryStore.snapshot()
        if (visited.isEmpty() && blocked.isEmpty()) return
        lastWebHistoryReport = now
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("webHistory").document("current")
            .set(
                mapOf(
                    "visited" to visited,
                    "blocked" to blocked,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    private var lastPermPrompt = 0L

    /**
     * If the child has turned off a required protection after setup, bring the
     * permission screen to the front so they're prompted to re-grant it.
     */
    private fun promptForMissingPermissions() {
        if (!ChildStore.isPaired(this)) return
        if (Permissions.allGranted(this)) return
        val now = System.currentTimeMillis()
        if (now - lastPermPrompt < PERM_PROMPT_MS) return
        lastPermPrompt = now
        try {
            startActivity(
                Intent(this, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            )
        } catch (_: Exception) {
        }
    }

    private var lastCallReport = 0L

    /**
     * Reports the child's recent call log to the parent (throttled). Needs the
     * READ_CALL_LOG grant; silently skips otherwise.
     */
    private fun reportCallHistory() {
        val now = System.currentTimeMillis()
        if (now - lastCallReport < CALLS_MS) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val calls = CallLogReporter.recent(this) ?: return
        lastCallReport = now
        val payload = calls.map {
            mapOf(
                "number" to it.number,
                "name" to (it.name ?: ""),
                "type" to it.type,
                "at" to it.date,
                "duration" to it.durationSeconds,
            )
        }
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("callHistory").document("current")
            .set(
                mapOf(
                    "calls" to payload,
                    "count" to payload.size,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    private var lastSmsReport = 0L

    /**
     * Reports the child's recent SMS inbox/sent to the parent (throttled). Needs
     * the READ_SMS grant; silently skips otherwise.
     */
    private fun reportSmsHistory() {
        val now = System.currentTimeMillis()
        if (now - lastSmsReport < SMS_MS) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val messages = SmsReader.recent(this) ?: return
        lastSmsReport = now
        val payload = messages.map {
            mapOf(
                "address" to it.address,
                "body" to it.body,
                "type" to it.type,
                "at" to it.date,
            )
        }
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("smsHistory").document("current")
            .set(
                mapOf(
                    "messages" to payload,
                    "count" to payload.size,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    private var lastMessagesReport = 0L

    /**
     * Flushes queued chat messages captured from messaging apps. Each message
     * is written as its own document under a per-contact thread, plus a small
     * summary doc per contact for the parent's chat list. Throttled, and only
     * when there's new data.
     */
    private fun reportMessages() {
        val now = System.currentTimeMillis()
        if (now - lastMessagesReport < MESSAGES_MS) return
        if (!MessageStore.hasChanges()) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val pending = MessageStore.drain()
        if (pending.isEmpty()) return
        lastMessagesReport = now

        val db = FirebaseFirestore.getInstance()
        val threads = db.collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("chatThreads")
        val batch = db.batch()
        // Track the newest message per contact for the summary row.
        val latest = HashMap<String, MessageStore.Msg>()
        val latestAt = HashMap<String, Long>()
        for (m in pending) {
            val key = hash("${m.app}\u0000${m.sender}")
            // Chat-time label used for both display and a stable, dedup-safe id
            // (so notification + scrape + OCR of one message become one doc).
            val timeLabel = m.timeLabel.ifBlank { chatTimeFmt.format(Date(m.at)) }
            val timeKey = timeLabel.uppercase(Locale.ROOT).replace(" ", "")
            val sortAt = chatSortAt(timeLabel, m.at)
            val msgId = hash("${m.app}\u0000${m.sender}\u0000${m.text}\u0000$timeKey")
            val doc = threads.document(key).collection("messages").document(msgId)
            batch.set(
                doc,
                mapOf(
                    "sender" to m.sender,
                    "app" to m.app,
                    "text" to m.text,
                    "outgoing" to m.outgoing,
                    "time" to timeLabel,
                    "at" to sortAt,
                    "createdAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
            if (latestAt[key] == null || sortAt >= latestAt[key]!!) {
                latest[key] = m
                latestAt[key] = sortAt
            }
        }
        for ((key, m) in latest) {
            val summary = hashMapOf<String, Any>(
                "sender" to m.sender,
                "app" to m.app,
                "senderKey" to key,
                "lastText" to m.text,
                "lastOutgoing" to m.outgoing,
                "lastTime" to m.timeLabel.ifBlank { chatTimeFmt.format(Date(m.at)) },
                "at" to (latestAt[key] ?: m.at),
                "updatedAt" to FieldValue.serverTimestamp(),
            )
            if (m.number.isNotBlank()) summary["number"] = m.number
            batch.set(threads.document(key), summary, SetOptions.merge())
        }
        batch.commit().addOnFailureListener { MessageStore.requeue(pending) }
    }

    private val chatTimeFmt = SimpleDateFormat("h:mm a", Locale.getDefault())

    /** Builds a sortable epoch-millis from a chat time label like "10:24 PM". */
    private fun chatSortAt(label: String, fallback: Long): Long {
        val match = Regex("^(\\d{1,2}):(\\d{2})\\s*([AaPp][Mm])?").find(label)
            ?: return fallback
        var h = match.groupValues[1].toIntOrNull() ?: return fallback
        val min = match.groupValues[2].toIntOrNull() ?: return fallback
        val ap = match.groupValues[3].uppercase(Locale.ROOT)
        if (ap == "PM" && h != 12) h += 12
        if (ap == "AM" && h == 12) h = 0
        return Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h)
            set(Calendar.MINUTE, min)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    /** Stable hex hash used for deterministic (dedup-safe) Firestore doc ids. */
    private fun hash(s: String): String {
        return try {
            java.security.MessageDigest.getInstance("MD5")
                .digest(s.toByteArray())
                .joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            s.hashCode().toString()
        }
    }

    private var lastYoutubeReport = 0L

    /**
     * Reports YouTube videos captured from the on-screen title. Throttled, and
     * only when there's new data.
     */
    private fun reportYoutubeHistory() {
        val now = System.currentTimeMillis()
        if (now - lastYoutubeReport < YOUTUBE_MS) return
        if (!YoutubeStore.hasChanges()) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val payload = YoutubeStore.snapshot()
        if (payload.isEmpty()) return
        lastYoutubeReport = now
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("youtubeHistory").document("current")
            .set(
                mapOf(
                    "videos" to payload,
                    "count" to payload.size,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    /**
     * Reports the device's launchable apps to the parent (once per service
     * start), so the family's App Rules screen lists the real installed apps.
     * Writes to children/{cid}/reports/installedApps — the child device is
     * allowed to write its own subtree by the security rules.
     */
    private fun reportInstalledApps() {
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val apps = AppBlocker.launchableApps(this).map {
            mapOf("packageName" to it.packageName, "appName" to it.label)
        }
        if (apps.isEmpty()) return
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("reports").document("installedApps")
            .set(
                mapOf(
                    "apps" to apps,
                    "count" to apps.size,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    /**
     * Listens to the family's app rules and applies blocks locally. Blocked
     * packages are suspended (Device Owner); removed ones are un-suspended.
     * Doc id == package name (written by the parent app).
     */
    private fun attachAppRulesListener() {
        val familyId = ChildStore.familyId(this) ?: return
        appRulesListener = FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("appRules")
            .addSnapshotListener { snaps, _ ->
                if (snaps == null) return@addSnapshotListener
                val blocked = snaps.documents
                    .filter { it.getBoolean("blocked") == true }
                    .map { it.id }
                    .toSet()
                // Feed the accessibility blocker (works without Device Owner).
                BlockedApps.packages = blocked
                val toUnblock = currentBlocked - blocked
                if (toUnblock.isNotEmpty()) {
                    AppBlocker.clearBlocked(this, toUnblock.toList())
                }
                if (blocked.isNotEmpty()) {
                    AppBlocker.setBlocked(this, blocked.toList())
                }
                currentBlocked = blocked
            }
    }

    /**
     * Watches the family's web-filter rule and keeps [WebFilter] in memory so
     * the accessibility service can block bad sites from the browser address
     * bar — no VPN, so browsing stays fast. Enabled category lists are fetched
     * by [CategoryFeed] in the background.
     */
    private fun attachWebFilterListener() {
        val familyId = ChildStore.familyId(this) ?: return
        webFilterListener = FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("rules").document("webFilter")
            .addSnapshotListener { snap, _ ->
                val enabled = snap != null && snap.exists() &&
                    snap.getBoolean("enabled") != false
                val sites = (snap?.get("blockedSites") as? List<*>)
                    ?.mapNotNull { (it as? String)?.lowercase()?.removePrefix("www.") }
                    ?.toSet() ?: emptySet()
                val cats = (snap?.get("blockedCategories") as? List<*>)
                    ?.mapNotNull { it as? String }?.toSet() ?: emptySet()
                WebFilter.enabled = enabled
                WebFilter.blockedSites = sites
                WebFilter.enabledCategories = cats
                if (enabled && cats.isNotEmpty()) {
                    // Load category domain lists (off the main thread) for matching.
                    Thread { runCatching { CategoryFeed.loadCache(applicationContext) } }
                        .apply { isDaemon = true }.start()
                    CategoryFeed.ensure(applicationContext, cats)
                }
                // The old DNS-filter VPN is no longer used.
                WebFilterVpnService.stop(this)
            }
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Protection", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Keeps GuardNest protection active." }
            nm.createNotificationChannel(channel)
        }
        val notification: Notification =
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, CHANNEL_ID)
            else
                @Suppress("DEPRECATION") Notification.Builder(this))
                .setContentTitle("GuardNest is active")
                .setContentText("Family protection is on.")
                .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIF_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    companion object {
        private const val CHANNEL_ID = "guardnest_protection"
        private const val NOTIF_ID = 1001
        private const val EVAL_INTERVAL_MS = 30_000L
        private const val HEARTBEAT_MS = 120_000L
        private const val USAGE_MS = 300_000L
        private const val LOCATION_MS = 120_000L
        private const val LOCATION_HISTORY_MS = 1_800_000L
        private const val WEBHISTORY_MS = 45_000L
        private const val CALLS_MS = 120_000L
        private const val PERM_PROMPT_MS = 60_000L
        private const val SMS_MS = 120_000L
        private const val MESSAGES_MS = 30_000L
        private const val YOUTUBE_MS = 30_000L

        /** Starts the service if this device is paired. */
        fun start(ctx: Context) {
            if (!ChildStore.isPaired(ctx)) return
            val intent = Intent(ctx, EnforcementService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        }
    }
}

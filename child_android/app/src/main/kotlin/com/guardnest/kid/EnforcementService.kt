package com.guardnest.kid

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
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
import com.google.firebase.auth.FirebaseAuth
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

    /**
     * Every Firestore snapshot listener we hold. Registering here (instead of a
     * field per listener) means [detachListeners] can never miss one — a missed
     * listener used to keep firing against a cleared [ChildStore] after the
     * parent unpaired the device.
     */
    private val listeners = mutableListOf<ListenerRegistration>()
    private var currentBlocked: Set<String> = emptySet()

    // App rules come from two places, kept separate so they can be merged:
    //  - family-wide "common" rules: families/{fid}/appRules
    //  - this child's own rules:     families/{fid}/children/{cid}/appRules
    // An app is blocked if EITHER blocks it; banking-allow is the union too.
    private var familyBlocked: Set<String> = emptySet()
    private var childBlocked: Set<String> = emptySet()
    private var familyBankingAllowed: Set<String> = emptySet()
    private var childBankingAllowed: Set<String> = emptySet()

    @Volatile
    private var rule = ScreenTimeRule()

    private val tick = object : Runnable {
        override fun run() {
            // Heartbeat first, and wrap everything so one failing task can never
            // kill the loop (which would make the parent show the child offline).
            try {
                Pairing.ensureDeviceRegistered(this@EnforcementService)
                guardAccessibility()
                heartbeat()
                enforce()
                reportLocation()
                reportWebHistory()
                reportCallHistory()
                reportSmsHistory()
                reportMessages()
                reportYoutubeHistory()
                reportAppCalls()
                restoreTempAccessIfRecovered(this@EnforcementService)
                TempAccessNotice.sync(this@EnforcementService)
                SetupNotice.sync(this@EnforcementService)
                enforceLockbox()
                checkForUpdate()
            } catch (t: Throwable) {
                // Never let one failing task kill the loop, but do record it — a
                // silent failure here used to be invisible on a remote device.
                Diag.warn(this@EnforcementService, "tick", t)
            } finally {
                handler.postDelayed(this, EVAL_INTERVAL_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        startAsForeground()
        YoutubeStore.init(this)
        WebHistoryStore.init(this)
        MessageStore.init(this)
        AppCallStore.init(this)
        // Devices paired by an older build have no `devices/{uid}` record, which
        // the security rules now require before this device may read the
        // family's rules. Register before attaching the listeners.
        Pairing.ensureDeviceRegistered(this)
        attachRuleListener()
        attachAppRulesListener()
        attachChildAppRulesListener()
        attachWebFilterListener()
        attachContentFilterListener()
        attachWebPolicyListener()
        attachChildDocListener()
        attachReportingListener()
        registerPackageChanges()
        DeviceLockdown.applyTamperProtection(this)
        reportInstalledApps()
        migrateLegacyReports()
        handler.post(tick)
        handler.post(lockGuard)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY // restart if the OS kills us
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        handler.removeCallbacks(lockGuard)
        detachListeners()
        unregisterPackageChanges()
        LockOverlay.hide(this, force = true)
        super.onDestroy()
    }

    /** Removes every registered snapshot listener. Safe to call more than once. */
    @Synchronized
    private fun detachListeners() {
        for (registration in listeners) {
            try {
                registration.remove()
            } catch (e: Exception) {
                Diag.warn(this, "detachListener", e)
            }
        }
        listeners.clear()
    }

    /** Tracks a listener so [detachListeners] will tear it down. */
    @Synchronized
    private fun track(registration: ListenerRegistration) {
        listeners.add(registration)
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
        } catch (e: Exception) {
            Diag.warn(this, "registerPackageChanges", e)
        }
    }

    private fun unregisterPackageChanges() {
        packageReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                Diag.warn(this, "unregisterPackageChanges", e)
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
        track(
            FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("children").document(childId)
                .addSnapshotListener { snap, e ->
                    if (e != null) {
                        Diag.warn(this, "childDocListener", e)
                        return@addSnapshotListener
                    }
                    if (snap != null && !snap.exists() && !snap.metadata.isFromCache) {
                        unpair()
                        return@addSnapshotListener
                    }
                    // The parent removed this installation. Their revoke marks
                    // our entry in the profile's devices map.
                    val uid = FirebaseAuth.getInstance().currentUser?.uid
                    if (uid != null &&
                        snap?.get("devices.$uid.revoked") == true
                    ) {
                        unpair()
                        return@addSnapshotListener
                    }
                    // A site-admin wipe stamps the child doc. Honour it locally:
                    // drop buffered history and the chat dedup set, so on-screen
                    // chats are re-captured and deleted history isn't resurrected
                    // from this device's local copies on the next flush.
                    val clearedAt =
                        snap?.getTimestamp("historyClearedAt")?.toDate()?.time ?: 0L
                    if (clearedAt > 0L &&
                        clearedAt != ChildStore.historyClearedAt(this)
                    ) {
                        ChildStore.setHistoryClearedAt(this, clearedAt)
                        MessageStore.resetForClear()
                        WebHistoryStore.clearAll()
                        YoutubeStore.clearAll()
                        AppCallStore.clearAll()
                        android.util.Log.i(
                            "Maryada", "history wipe honoured ($clearedAt)")
                    }
                    // The parent tapped Sync. Nothing can wake a device that is
                    // asleep, but one that is reachable should report now
                    // instead of at the end of its next throttle window.
                    val syncAt =
                        snap?.getTimestamp("syncRequestedAt")?.toDate()?.time ?: 0L
                    if (syncAt > 0L && syncAt != ChildStore.syncRequestedAt(this)) {
                        ChildStore.setSyncRequestedAt(this, syncAt)
                        reportEverythingNow()
                    }
                }
        )
    }

    /** Drops every reporting throttle so the next tick sends a full update. */
    private fun reportEverythingNow() {
        lastHeartbeat = 0L
        lastWebHistoryReport = 0L
        lastCallReport = 0L
        lastSmsReport = 0L
        lastMessagesReport = 0L
        lastYoutubeReport = 0L
        lastAppCallReport = 0L
        lastLocationReport = 0L
        // A sync is the parent asking to see everything now, so the
        // unchanged-content guards must not hold the last state back.
        lastCallDigest = 0
        lastSmsDigest = 0
        handler.post {
            try {
                heartbeat()
                reportInstalledApps()
                reportWebHistory()
                reportCallHistory()
                reportSmsHistory()
                reportMessages()
                reportYoutubeHistory()
                reportAppCalls()
            } catch (t: Throwable) {
                Diag.warn(this, "syncNow", t)
            }
        }
    }

    /** Clears local pairing, stops the filter, and shuts the service down. */
    private fun unpair() {
        handler.removeCallbacks(tick)
        handler.removeCallbacks(lockGuard)
        detachListeners()
        unregisterPackageChanges()
        LockOverlay.hide(this, force = true)
        // The parent removed this device -> allow it to be uninstalled again.
        DeviceLockdown.releaseForRemoval(this)
        Pairing.unregisterDevice(this)
        WebFilterVpnService.stop(this)
        ChildStore.clear(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun attachRuleListener() {
        val familyId = ChildStore.familyId(this) ?: return
        track(
            FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("rules").document("screenTime")
                .addSnapshotListener { snap, e ->
                    if (e != null) {
                        Diag.warn(this, "ruleListener", e)
                        return@addSnapshotListener
                    }
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
        )
    }

    /** Follows the heartbeat cadence the parent derives from the family size. */
    private fun attachReportingListener() {
        heartbeatMs = ChildStore.heartbeatMs(this, DEFAULT_HEARTBEAT_MS)
            .coerceIn(MIN_HEARTBEAT_MS, MAX_HEARTBEAT_MS)
        val familyId = ChildStore.familyId(this) ?: return
        track(
            FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("rules").document("reporting")
                .addSnapshotListener { snap, e ->
                    if (e != null) {
                        Diag.warn(this, "reportingListener", e)
                        return@addSnapshotListener
                    }
                    val published = (snap?.get("heartbeatMs") as? Number)?.toLong()
                        ?: return@addSnapshotListener
                    val next = published.coerceIn(MIN_HEARTBEAT_MS, MAX_HEARTBEAT_MS)
                    if (next == heartbeatMs) return@addSnapshotListener
                    heartbeatMs = next
                    ChildStore.setHeartbeatMs(this, next)
                }
        )
    }

    private fun enforce() {
        val lock = ScreenGuard.shouldLock(
            rule.paused, rule.bedtimeEnabled, rule.bedtimeStart, rule.bedtimeEnd
        )
        // Pause / bedtime block ALL apps (enforced live by the accessibility
        // service) but leave the phone usable for emergency calls — we no longer
        // freeze the whole device behind a full-screen overlay.
        ScreenGuard.locked = lock
        ScreenGuard.label = if (rule.paused) "paused" else "resting (bedtime)"
        ScreenGuard.lockTitle = if (rule.paused) "Paused" else "Bedtime"
        ScreenGuard.lockSubtitle = if (rule.paused) {
            "Your device is paused by your parent."
        } else {
            "It's rest time \uD83C\uDF19\n" +
                "Bedtime: ${fmtTime(rule.bedtimeStart)} \u2013 ${fmtTime(rule.bedtimeEnd)}\n" +
                "Ask your parent if you need the phone."
        }
        if (!lock && !ChildStore.lockboxActive(this)) {
            LockOverlay.hide(this, force = true)
        }
    }

    private var lastHeartbeat = 0L

    /**
     * How often to report being alive. The parent derives this from how many
     * profiles share the family's daily write allowance, so a small household
     * gets a fresh screen and a large one still fits inside the free tier.
     */
    @Volatile
    private var heartbeatMs = DEFAULT_HEARTBEAT_MS

    /** Periodically tells the parent this device is online (throttled). */
    private fun heartbeat() {
        val now = System.currentTimeMillis()
        if (now - lastHeartbeat < heartbeatMs) return
        lastHeartbeat = now
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val payload = mutableMapOf<String, Any?>(
            "online" to true,
            "lastSeenAt" to FieldValue.serverTimestamp(),
            // Live protection status, so the parent always knows whether
            // monitoring is intact — even between the once-in-a-few-days
            // check-ins. permissionsOk was previously only set at pairing.
            "protections" to protectionsMap(),
            "permissionsOk" to Permissions.allGranted(this),
            // Installed app version, so the parent can spot devices that
            // haven't taken the latest OTA update.
            "appVersionCode" to appVersionCode(),
            "appVersionName" to appVersionName(),
            // Exactly what the child's own screen shows, so both agree.
            "appVersionLabel" to AppUpdater.versionLabel(this),
        )
        // Surface the most recent internal failure so a device that has quietly
        // stopped working is visible in the admin app instead of just looking OK.
        val lastError = Diag.lastError(this)
        val reportedAt = Diag.lastErrorAt(this)
        if (lastError != null) {
            payload["lastError"] = lastError
            payload["lastErrorAt"] = Date(reportedAt)
        } else {
            // A merge write does not remove old fields unless we explicitly
            // clear them, which left resolved errors visible forever.
            payload["lastError"] = null
            payload["lastErrorAt"] = null
        }
        // The current position rides along here instead of paying for its own
        // write; the map's "updated" time stays honest because this runs on a
        // timer whether the child has moved or not.
        val lat = fixLat
        val lng = fixLng
        if (lat != null && lng != null) {
            payload["lat"] = lat
            payload["lng"] = lng
            payload["locationAccuracy"] = fixAccuracy
            payload["locationUpdatedAt"] = FieldValue.serverTimestamp()
            fixAddress?.let { payload["address"] = it }
        }
        // This device's own copy, under its uid, so a profile can hold several
        // devices without them overwriting each other's state. It rides in the
        // same write as the profile fields: a merge only touches `devices.<uid>`,
        // so one heartbeat is one write instead of two.
        deviceRecord(payload)?.let { (uid, record) ->
            payload["devices"] = mapOf(uid to record)
        }
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .set(payload, SetOptions.merge())
            .addOnSuccessListener {
                // This write reaching Firestore is proof the device is fine, so
                // the failure it just reported is history: drop it and the next
                // heartbeat clears it on the parent's side too.
                Diag.clearResolved(this, reportedAt)
            }
            .addOnFailureListener { e ->
                // The parent removed this device -> our write is rejected. Unpair.
                if (e is FirebaseFirestoreException &&
                    e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED
                ) {
                    unpair()
                } else {
                    Diag.warn(this, "heartbeat", e)
                }
            }
    }

    /**
     * This device's entry for the profile's `devices` map: the heartbeat fields
     * plus what identifies the machine. Null before the device has signed in.
     */
    private fun deviceRecord(payload: Map<String, Any?>): Pair<String, Map<String, Any?>>? {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return null
        val record = payload.toMutableMap()
        record["platform"] = "android"
        record["deviceUid"] = uid
        record["deviceModel"] = "${Build.MANUFACTURER} ${Build.MODEL}"
        val displayName = ChildStore.deviceName(this)
        if (displayName.isNotEmpty()) record["displayName"] = displayName
        return uid to record
    }

    /** Live grant state of each required protection (true == granted). */
    private fun protectionsMap(): Map<String, Boolean> = mapOf(
        "accessibility" to Permissions.hasAccessibility(this),
        // Granted but not running. Vivo/Oppo/Xiaomi kill the accessibility
        // service without clearing its switch, so monitoring is dead while the
        // parent's screen still says "Protected". Only reported once the repair
        // attempts have had their grace period — a kill that heals in seconds
        // is not something to put in front of a parent.
        "monitoring" to Permissions.accessibilityOk(this),
        "notificationAccess" to Permissions.hasNotificationAccess(this),
        "usageAccess" to Permissions.hasUsageAccess(this),
        "callLog" to Permissions.hasCallLog(this),
        "sms" to Permissions.hasSms(this),
        "battery" to Permissions.hasBatteryExemption(this),
        "deviceAdmin" to Permissions.hasDeviceAdmin(this),
        "overlay" to Permissions.hasOverlay(this),
    )

    /**
     * Puts a killed accessibility service back. The stall clock itself is kept
     * by [Permissions.accessibilityOk], which every enforcement path already
     * consults; this is only the repair attempt.
     */
    private fun guardAccessibility() {
        if (!ChildStore.isPaired(this)) return
        if (!Permissions.hasAccessibility(this)) return
        if (Permissions.accessibilityBound()) return
        if (ChildStore.tempAccess(this)) return
        // Silent repair when the install was granted WRITE_SECURE_SETTINGS at
        // provisioning; otherwise the grace period runs out and the lockbox
        // makes the child fix it.
        if (AccessibilityGuard.recover(this)) {
            Permissions.invalidateCache()
        }
    }

    /** The installed app's versionCode (reported to the parent via heartbeat). */
    private fun appVersionCode(): Long = try {
        val info = packageManager.getPackageInfo(packageName, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()
    } catch (_: Exception) {
        0L
    }

    /** The installed app's versionName, e.g. "1.0.4". */
    private fun appVersionName(): String = try {
        packageManager.getPackageInfo(packageName, 0).versionName ?: ""
    } catch (_: Exception) {
        ""
    }

    private fun offProtections(): List<String> =
        protectionsMap().filterValues { !it }.keys.toList()

    private var lastLocationReport = 0L
    private var lastUpdateCheck = 0L

    // Latest fix, written out with the next heartbeat rather than as a write of
    // its own. A stationary child would otherwise cost a write every cycle to
    // say nothing had changed.
    @Volatile private var fixLat: Double? = null
    @Volatile private var fixLng: Double? = null
    @Volatile private var fixAccuracy: Double = 0.0
    @Volatile private var fixAddress: String? = null

    /** Periodically checks for a remotely-published app update (OTA). */
    private fun checkForUpdate() {
        val now = System.currentTimeMillis()
        if (now - lastUpdateCheck < UPDATE_CHECK_MS) return
        lastUpdateCheck = now
        AppUpdater.checkAndUpdate(this)
    }

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

    /**
     * Takes a location fix. The current position is NOT written here — it rides
     * along with the next heartbeat, which already writes the child document,
     * so tracking costs no writes of its own. Only a genuine new place is
     * appended to the trail.
     */
    private fun writeLocation(loc: Location) {
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        lastLocationReport = System.currentTimeMillis()
        val lat = loc.latitude
        val lng = loc.longitude
        val acc = loc.accuracy.toDouble()

        Thread {
            val address = reverseGeocode(lat, lng)
            fixLat = lat
            fixLng = lng
            fixAccuracy = acc
            fixAddress = address
            val childRef = FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("children").document(childId)

            if (shouldRecordPlace(lat, lng, loc.accuracy)) {
                ChildStore.setLastTrailPoint(this, lat, lng, System.currentTimeMillis())
                ChildStore.clearPendingPlace(this)
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

    /**
     * Whether this fix is a place worth keeping, rather than another reading of
     * somewhere already recorded.
     *
     * A plain "every 30 minutes, if it moved" rule filled the trail with the
     * same place over and over: GPS drifts, a network fix can be a kilometre
     * wide, and a child passing a road on the bus is not somewhere they went.
     * So a new place has to be BOTH far enough away AND somewhere they actually
     * stayed — the child has to still be there on a later fix before it counts.
     * A large jump is recorded straight away, because waiting to confirm a
     * different town would just lose the journey.
     */
    private fun shouldRecordPlace(lat: Double, lng: Double, accuracy: Float): Boolean {
        val last = ChildStore.lastTrailPoint(this)
        if (last == null) {
            ChildStore.clearPendingPlace(this)
            return true
        }
        val moved = distanceTo(last.first, last.second, lat, lng)
        // Never trust a move smaller than the fix's own margin of error.
        val threshold = maxOf(HISTORY_MIN_DISTANCE_M, accuracy)
        if (moved <= threshold) {
            ChildStore.clearPendingPlace(this)
            return false
        }
        if (moved >= HISTORY_TELEPORT_M) return true

        val now = System.currentTimeMillis()
        val pending = ChildStore.pendingPlace(this)
        // Somewhere new, or somewhere different from the last candidate: start
        // the clock rather than recording a place still being passed through.
        if (pending == null ||
            distanceTo(pending.first, pending.second, lat, lng) > threshold
        ) {
            ChildStore.setPendingPlace(this, lat, lng, now)
            return false
        }
        return now - pending.third >= HISTORY_DWELL_MS
    }

    private fun distanceTo(
        fromLat: Double,
        fromLng: Double,
        toLat: Double,
        toLng: Double,
    ): Float {
        val results = FloatArray(1)
        Location.distanceBetween(fromLat, fromLng, toLat, toLng, results)
        return results[0]
    }

    /** Turns coordinates into a short human-readable place name (best effort). */
    private fun reverseGeocode(lat: Double, lng: Double): String? {
        return try {
            @Suppress("DEPRECATION")
            val results = Geocoder(this, Locale.getDefault()).getFromLocation(lat, lng, 3)
                ?: return null
            // Prefer the result that yields real place words — the first one is
            // often just a Plus Code ("34WG+P26") with no street or area.
            for (addr in results) {
                val feature = addr.featureName
                    ?.takeUnless { isPlusCode(it) || it == addr.thoroughfare }
                val parts = listOfNotNull(
                    feature,
                    addr.thoroughfare,
                    addr.subLocality,
                    addr.locality ?: addr.subAdminArea,
                ).map { it.trim() }.filter { it.isNotEmpty() }.distinct()
                if (parts.isNotEmpty()) return parts.take(3).joinToString(", ")
            }
            val line = results.firstOrNull()?.getAddressLine(0) ?: return null
            // Last resort: strip the leading Plus Code token from the full line
            // ("34WG+P26 Hyderabad, Telangana" -> "Hyderabad, Telangana").
            line.split(' ')
                .dropWhile { isPlusCode(it.trim(',')) }
                .joinToString(" ")
                .ifBlank { line }
        } catch (_: Exception) {
            null
        }
    }

    /** True for Open Location Codes like "34WG+P26" — not a place name. */
    private fun isPlusCode(s: String): Boolean =
        Regex("^[23456789CFGHJMPQRVWX]{4,8}\\+[23456789CFGHJMPQRVWX]{2,4}$", RegexOption.IGNORE_CASE)
            .matches(s.trim())

    private var lastWebHistoryReport = 0L

    /**
     * Reports the child's web history (real sites visited from the browser
     * address bar + blocked attempts from the DNS filter). Throttled, and only
     * when there's new data.
     */
    /**
     * This device's document for an activity feed. Every device used to share
     * one `current` doc per feed, so a second device silently overwrote the
     * first's history — and the parent could never tell them apart.
     */
    private fun reportDoc(
        familyId: String,
        childId: String,
        collection: String,
    ) = FirebaseFirestore.getInstance()
        .collection("families").document(familyId)
        .collection("children").document(childId)
        .collection(collection)
        .document(FirebaseAuth.getInstance().currentUser?.uid ?: "current")

    /** Moves any legacy shared `current` feed onto this device, once. */
    private fun migrateLegacyReports() {
        if (ChildStore.reportsMigrated(this)) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        ChildStore.setReportsMigrated(this, true)
        val db = FirebaseFirestore.getInstance()
        for (feed in REPORT_FEEDS) {
            val col = db.collection("families").document(familyId)
                .collection("children").document(childId)
                .collection(feed)
            col.document("current").get()
                .addOnSuccessListener { snap ->
                    val data = snap.data ?: return@addOnSuccessListener
                    col.document(uid).set(data, SetOptions.merge())
                        .addOnSuccessListener { col.document("current").delete() }
                }
                .addOnFailureListener { Diag.warn(this, "migrateReports:$feed", it) }
        }
    }

    private fun reportWebHistory() {
        val now = System.currentTimeMillis()
        if (now - lastWebHistoryReport < WEBHISTORY_MS) return
        if (!WebHistoryStore.hasChanges()) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val (visited, blocked, searches) = WebHistoryStore.snapshot()
        if (visited.isEmpty() && blocked.isEmpty() && searches.isEmpty()) return
        lastWebHistoryReport = now
        reportDoc(familyId, childId, "webHistory")
            .set(
                mapOf(
                    "visited" to visited,
                    "blocked" to blocked,
                    "searches" to searches,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    private var lastPermPrompt = 0L

    /**
     * "Banking mode" / lockbox — the core of GuardNest's tamper handling.
     *
     * While every required protection is granted, the child uses the phone
     * normally. The moment one is turned off — e.g. the child disables the
     * accessibility service so a strict banking / UPI app will run — we suspend
     * every app except the parent's allow-list ([SensitiveApps]) plus the
     * essentials needed to navigate and re-grant permissions. Turning the
     * protections back on restores everything automatically.
     *
     * This runs in the always-on foreground service and enforces via Device
     * Owner app-suspension, so it keeps working even when accessibility is off
     * (which is exactly when the child would otherwise escape monitoring).
     */
    private fun enforceLockbox() {
        if (!ChildStore.isPaired(this)) return
        val allOk = Permissions.allGranted(this)
        val active = ChildStore.lockboxActive(this)
        when {
            !allOk -> applyLockbox(firstEntry = !active)
            active -> releaseLockbox()
        }
    }

    /**
     * Suspends every non-allowed app. Idempotent: safe to re-assert each tick,
     * which self-heals against a newly installed app or an app-rules race.
     */
    private fun applyLockbox(firstEntry: Boolean) {
        val launchable = AppBlocker.launchableApps(this).map { it.packageName }
        val toSuspend = launchable
            .filterNot {
                it == packageName ||
                    isEssential(it) ||
                    SensitiveApps.isSensitive(it)
            }
            .toSet()

        if (toSuspend.isNotEmpty()) {
            AppBlocker.setBlocked(this, toSuspend.toList())
        }

        if (firstEntry) {
            val since = System.currentTimeMillis()
            ChildStore.enterLockbox(this, toSuspend, since)
            reportLockbox(active = true, since = since)
            writeProtectionAlert(type = "protection_disabled")
        } else if (toSuspend != ChildStore.lockboxSuspended(this)) {
            // Keep the persisted set current so exit stays precise.
            ChildStore.enterLockbox(this, toSuspend, ChildStore.lockboxSince(this))
        }

        // Only pull GuardNest to the front when the child is actually in a
        // non-allowed app. In Temporary Access mode the child intentionally opens
        // an allowed (e.g. banking) app, so we must NOT keep bouncing them back
        // to GuardNest while they use it.
        val fg = foregroundPackage()
        val fgAllowed = fg == null ||
            fg == packageName ||
            isEssential(fg) ||
            SensitiveApps.isSensitive(fg)
        if (!fgAllowed) bringSelfToFront()
    }

    /**
     * Restores normal use once every protection is granted again. Un-suspends
     * only what lockbox suspended, leaving any app the parent has separately
     * blocked (via app rules) still suspended.
     */
    private fun releaseLockbox() {
        val toRelease = ChildStore.lockboxSuspended(this) - currentBlocked
        if (toRelease.isNotEmpty()) {
            AppBlocker.clearBlocked(this, toRelease.toList())
        }
        ChildStore.exitLockbox(this)
        lastForeground = null
        LockOverlay.hide(this, force = true)
        reportLockbox(active = false, since = 0L)
        writeProtectionAlert(type = "protection_restored")
    }

    private fun isEssential(pkg: String): Boolean {
        if (pkg == packageName) return true
        // Note: the package installer is deliberately NOT essential, so opening
        // an app's uninstall screen while a protection is off gets covered by
        // the lock overlay (the child must ask the parent to remove apps).
        return Pkgs.isEssentialSystem(pkg)
    }

    /** Home screen — the pause/bedtime lock screen leaves this (and the Maryada
     *  app) accessible and only covers real apps the child opens. Transient
     *  system windows aren't included so the overlay doesn't flicker. */
    private fun isHomeOrSystem(pkg: String): Boolean =
        pkg == packageName || Pkgs.isLauncher(pkg)

    /** Formats "minutes from midnight" as a 12-hour clock, e.g. 1290 -> "9:30 PM". */
    private fun fmtTime(minutes: Int): String {
        val h24 = ((minutes / 60) % 24 + 24) % 24
        val m = ((minutes % 60) + 60) % 60
        var h = h24 % 12
        if (h == 0) h = 12
        val ampm = if (h24 < 12) "AM" else "PM"
        return String.format(java.util.Locale.US, "%d:%02d %s", h, m, ampm)
    }

    // ---- Fallback enforcement (no Device Owner) ---------------------------

    private var lastForeground: String? = null
    private var lastForegroundQuery = 0L

    /**
     * Fast loop that enforces the lockbox on devices that are NOT Device Owner
     * (where app-suspension is unavailable). While a protection is off, it
     * covers any non-allowed foreground app with the lock overlay, leaving the
     * parent's banking allow-list usable. Needs usage access + overlay to stay
     * granted; on Device Owner devices the app-suspension already handles this
     * and the overlay simply never triggers because allowed apps stay open.
     */
    private val lockGuard = object : Runnable {
        override fun run() {
            var enforcing = false
            try {
                enforcing = guardForeground()
            } catch (t: Throwable) {
                Diag.warn(this@EnforcementService, "lockGuard", t)
            } finally {
                // Polling every 700ms all day was a large part of why the phone
                // felt slow. The fast rate only matters while something is
                // actually being blocked; otherwise idle along.
                handler.postDelayed(
                    this,
                    if (enforcing) LOCKGUARD_INTERVAL_MS else LOCKGUARD_IDLE_MS,
                )
            }
        }
    }

    /** Returns true while it is actively enforcing (so the loop stays fast). */
    private fun guardForeground(): Boolean {
        if (!ChildStore.isPaired(this)) return false
        // Pause / bedtime: show the full lock screen with the real schedule. Let
        // emergency calls through by hiding it while a phone/dialer app is up.
        if (ScreenGuard.shouldLock(
                rule.paused, rule.bedtimeEnabled, rule.bedtimeStart, rule.bedtimeEnd
            )
        ) {
            // The device stays usable on the home screen; the lock screen only
            // appears when the child actually opens a (non-home) app.
            // Prefer the accessibility service's evented foreground over the
            // UsageStats poll — the two briefly disagree around app switches,
            // and acting on the laggy one made the overlay flicker.
            val axFg = ForegroundApp.packageName
            val axFresh =
                System.currentTimeMillis() - ForegroundApp.changedAt < 10_000L
            val fg = if (axFg.isNotEmpty() && axFresh) axFg else foregroundPackage()
            if (fg == null || isHomeOrSystem(fg)) {
                LockOverlay.hide(this)
            } else {
                LockOverlay.show(this, ScreenGuard.lockTitle, ScreenGuard.lockSubtitle)
            }
            return true
        }

        // Live check so enforcement reacts within a second, without waiting for
        // the 30s state machine (which still does the parent reporting/alerts).
        if (Permissions.allGrantedCached(this)) {
            // A blocked app keeps its block screen for as long as it is open;
            // the accessibility service raises it, this keeps it there.
            val open = foregroundPackage()
            if (open != null && open != packageName && BlockedApps.isBlocked(open)) {
                LockOverlay.show(
                    this,
                    LockOverlay.APP_BLOCKED_TITLE,
                    LockOverlay.APP_BLOCKED_MESSAGE,
                    AlertLog.appLabel(this, open),
                )
                return true
            }
            // Protections are intact — drop our fallback overlay if we raised it.
            if (LockOverlay.isShowing()) LockOverlay.hide(this, force = true)
            return false
        }

        val fg = foregroundPackage() ?: return true
        val allowed = fg == packageName ||
            isEssential(fg) ||
            SensitiveApps.isSensitive(fg)
        if (allowed) {
            LockOverlay.hide(this)
        } else {
            LockOverlay.show(
                this,
                "App locked",
                "Turn your Maryada protections back on to use this app.",
            )
        }
        return true
    }

    /**
     * The current foreground app package via UsageStats (works without the
     * accessibility service). Remembers the last seen value so it stays correct
     * while the child sits in one app with no new events. Null if usage access
     * isn't granted.
     */
    private fun foregroundPackage(): String? {
        // The accessibility service already tracks this from window events, so
        // prefer its answer and skip the UsageStats query entirely — that query
        // parses the usage DB on every call and was running twice a second.
        val fromEvents = ForegroundApp.packageName
        if (fromEvents.isNotEmpty() &&
            System.currentTimeMillis() - ForegroundApp.changedAt < FOREGROUND_FRESH_MS
        ) {
            lastForeground = fromEvents
            return fromEvents
        }
        if (!Permissions.hasUsageAccess(this)) return null
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return lastForeground
        val now = System.currentTimeMillis()
        if (now - lastForegroundQuery < FOREGROUND_QUERY_MS) return lastForeground
        lastForegroundQuery = now
        val events = usm.queryEvents(now - 3_000, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                e.eventType == UsageEvents.Event.ACTIVITY_RESUMED
            ) {
                lastForeground = e.packageName
            }
        }
        return lastForeground
    }

    /** Reports the current banking-mode state onto the child doc for the parent. */
    private fun reportLockbox(active: Boolean, since: Long) {
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val data = hashMapOf<String, Any?>(
            "lockboxActive" to active,
            "lockboxSince" to if (active && since > 0) Date(since) else null,
        )
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .set(data, SetOptions.merge())
    }

    /** Logs a tamper-evident alert the parent sees on their next check-in. */
    private fun writeProtectionAlert(type: String) {
        // Only a tamper event (a protection being turned off) is surfaced as an
        // alert. Restoring protection is not alerted.
        if (type != "protection_disabled") return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("alerts").add(
                mapOf(
                    "type" to "tamper",
                    "detail" to "Protection was turned off",
                    "childId" to childId,
                    "protections" to offProtections(),
                    "at" to FieldValue.serverTimestamp(),
                )
            )
    }

    /**
     * Brings the permission screen to the front so the child is prompted to
     * re-grant a protection they turned off (throttled).
     */
    private fun bringSelfToFront() {
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
        } catch (e: Exception) {
            Diag.warn(this, "bringSelfToFront", e)
        }
    }

    private var lastCallReport = 0L
    private var lastCallDigest = 0

    /**
     * Reports the child's recent call log to the parent (throttled). Needs the
     * READ_CALL_LOG grant; silently skips otherwise.
     *
     * The log changes a handful of times a day, so the write only happens when
     * the contents actually differ — re-sending an identical list every cycle
     * burned most of this device's daily write budget saying nothing.
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
        val digest = payload.hashCode()
        if (digest == lastCallDigest) return
        lastCallDigest = digest
        reportDoc(familyId, childId, "callHistory")
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
    private var lastSmsDigest = 0

    /**
     * Reports the child's recent SMS inbox/sent to the parent (throttled). Needs
     * the READ_SMS grant; silently skips otherwise. Only written when the
     * contents changed — see [reportCallHistory].
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
        val digest = payload.hashCode()
        if (digest == lastSmsDigest) return
        lastSmsDigest = digest
        reportDoc(familyId, childId, "smsHistory")
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

    /** Newest message time already written per chat, so the chat list's order
     *  can't be dragged backwards by a re-sent old message. */
    private val threadLatestAt = HashMap<String, Long>()

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
        val deviceUid = FirebaseAuth.getInstance().currentUser?.uid ?: ""
        val threads = db.collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("chatThreads")
        val batch = db.batch()
        // Track the newest message per contact for the summary row.
        val latest = HashMap<String, MessageStore.Msg>()
        val latestAt = HashMap<String, Long>()
        for (m in pending) {
            val key = hash("${m.app}\u0000${m.sender}")
            // Only ever the bubble's own clock label. Falling back to the time
            // we happened to scrape it at showed the parent a time the message
            // was never sent at; an unreadable label now shows none.
            val timeLabel = m.timeLabel
            val sortAt = chatSortAt(timeLabel, m.at, m.slot, m.dayStart)
            val messages = threads.document(key).collection("messages")
            // MessageStore owns the id: it remembers what was already uploaded
            // for a message, so a later sighting that finally reveals the day or
            // the bubble's time supersedes that document instead of adding a
            // second copy of the same message.
            if (m.replaces.isNotBlank()) {
                batch.delete(messages.document(hash(m.replaces)))
            }
            val doc = messages.document(hash(m.docKey))
            batch.set(
                doc,
                mapOf(
                    "sender" to m.sender,
                    "app" to m.app,
                    "text" to m.text,
                    "outgoing" to m.outgoing,
                    "time" to timeLabel,
                    "at" to sortAt,
                    "deviceUid" to deviceUid,
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
            val at = latestAt[key] ?: m.at
            // The chat list is ordered by this. Re-uploading an older message
            // (one that only just revealed its date) used to overwrite it with
            // that older time and drop a live conversation down the list, so a
            // thread's time only ever moves forward.
            if (at < (threadLatestAt[key] ?: 0L)) continue
            threadLatestAt[key] = at
            val summary = hashMapOf<String, Any>(
                "sender" to m.sender,
                "app" to m.app,
                "senderKey" to key,
                "lastText" to m.text,
                "lastOutgoing" to m.outgoing,
                "lastTime" to m.timeLabel,
                "at" to at,
                "deviceUid" to deviceUid,
                "updatedAt" to FieldValue.serverTimestamp(),
            )
            if (m.number.isNotBlank()) summary["number"] = m.number
            batch.set(threads.document(key), summary, SetOptions.merge())
        }
        batch.commit().addOnFailureListener {
            MessageStore.requeue(pending)
            Diag.warn(this, "reportMessages", it)
        }
    }

    private val chatTimeFmt = SimpleDateFormat("h:mm a", Locale.getDefault())

    /**
     * Builds a sortable epoch-millis from a chat time label like "10:24 PM".
     *
     * [dayStart] is the day the message's date separator resolved to. Without
     * it only the time of day is known, so messages from different days
     * interleaved — yesterday's 4pm sorting after today's 3pm.
     *
     * [ordinal] separates messages that share a minute. The label has no
     * seconds, so they used to collide on the same millisecond and Firestore
     * fell back to ordering them by their (hashed, effectively random) id.
     */
    private fun chatSortAt(
        label: String,
        fallback: Long,
        ordinal: Int = 0,
        dayStart: Long = 0L,
    ): Long {
        val slot = ordinal.coerceIn(0, 999)
        val match = Regex("^(\\d{1,2}):(\\d{2})\\s*([AaPp][Mm])?").find(label)
            ?: return (if (dayStart > 0L) dayStart else fallback) + slot
        var h = match.groupValues[1].toIntOrNull()
            ?: return (if (dayStart > 0L) dayStart else fallback) + slot
        val min = match.groupValues[2].toIntOrNull()
            ?: return (if (dayStart > 0L) dayStart else fallback) + slot
        val ap = match.groupValues[3].uppercase(Locale.ROOT)
        if (ap == "PM" && h != 12) h += 12
        if (ap == "AM" && h == 12) h = 0
        // A known day is exact; anchor to it and skip the guesswork below.
        if (dayStart > 0L) {
            return dayStart + h * 3_600_000L + min * 60_000L + slot
        }
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h)
            set(Calendar.MINUTE, min)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, slot)
        }
        // No separator was visible, so the day is inferred: a time that would
        // land in the future can't be from today. Slack absorbs the label's
        // missing seconds and any clock skew.
        if (cal.timeInMillis > System.currentTimeMillis() + FUTURE_SLACK_MS) {
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }
        return cal.timeInMillis
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
        reportDoc(familyId, childId, "youtubeHistory")
            .set(
                mapOf(
                    "videos" to payload,
                    "count" to payload.size,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    private var lastAppCallReport = 0L

    /**
     * Reports WhatsApp voice and video calls. They never reach the system call
     * log, so the parent's call history was blind to them; these come from the
     * ongoing-call notification instead.
     */
    private fun reportAppCalls() {
        val now = System.currentTimeMillis()
        if (now - lastAppCallReport < APP_CALLS_MS) return
        if (!AppCallStore.hasChanges()) return
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val payload = AppCallStore.snapshot()
        if (payload.isEmpty()) return
        lastAppCallReport = now
        reportDoc(familyId, childId, "appCalls")
            .set(
                mapOf(
                    "calls" to payload,
                    "count" to payload.size,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
    }

    /**
     * Reports the device's launchable apps to the parent (once per service
     * start), so the family's App Rules screen lists the real installed apps.
     * Written to children/{cid}/reports/installedApps-{uid}: a phone and a PC
     * on one profile hold different apps, and a shared document meant whoever
     * reported last decided which app list the parent saw.
     */
    private fun reportInstalledApps() {
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val apps = AppBlocker.launchableApps(this).map {
            mapOf("packageName" to it.packageName, "appName" to it.label)
        }
        if (apps.isEmpty()) return
        val reports = FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
            .collection("reports")
        reports.document("installedApps-$uid")
            .set(
                mapOf(
                    "apps" to apps,
                    "count" to apps.size,
                    "platform" to "android",
                    "deviceUid" to uid,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
            // The shared document this device used to write would otherwise
            // keep showing its apps against every other device on the profile.
            .addOnSuccessListener { reports.document("installedApps").delete() }
    }

    /**
     * Listens to the family-wide ("common") app rules and applies blocks
     * locally. These apply to every child in the family. Merged with this
     * child's own rules in [applyMergedAppRules]. Doc id == package name.
     */
    private fun attachAppRulesListener() {
        val familyId = ChildStore.familyId(this) ?: return
        track(
            FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("appRules")
                .addSnapshotListener { snaps, e ->
                    if (e != null) {
                        Diag.warn(this, "appRulesListener", e)
                        return@addSnapshotListener
                    }
                    if (snaps == null) return@addSnapshotListener
                    familyBlocked = snaps.documents
                        .filter { it.getBoolean("blocked") == true }
                        .map { it.id }
                        .toSet()
                    familyBankingAllowed = snaps.documents
                        .filter { it.getBoolean("bankingAllowed") == true }
                        .map { it.id }
                        .toSet()
                    applyMergedAppRules()
                }
        )
    }

    /**
     * Listens to THIS child's own app rules (set from the child's screen in the
     * parent app), so a block chosen for one child doesn't affect siblings.
     * Merged with the family-wide rules in [applyMergedAppRules].
     */
    private fun attachChildAppRulesListener() {
        val familyId = ChildStore.familyId(this) ?: return
        val childId = ChildStore.childId(this) ?: return
        track(
            FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("children").document(childId)
                .collection("appRules")
                .addSnapshotListener { snaps, e ->
                    if (e != null) {
                        Diag.warn(this, "childAppRulesListener", e)
                        return@addSnapshotListener
                    }
                    if (snaps == null) return@addSnapshotListener
                    childBlocked = snaps.documents
                        .filter { it.getBoolean("blocked") == true }
                        .map { it.id }
                        .toSet()
                    childBankingAllowed = snaps.documents
                        .filter { it.getBoolean("bankingAllowed") == true }
                        .map { it.id }
                        .toSet()
                    applyMergedAppRules()
                }
        )
    }

    /**
     * Combines the family-wide and per-child rules (an app is blocked if EITHER
     * blocks it) and applies them: blocked packages are suspended (Device
     * Owner); removed ones are un-suspended. Also feeds the accessibility
     * blocker and the banking-mode allow-list.
     */
    private fun applyMergedAppRules() {
        val blocked = familyBlocked + childBlocked
        val bankingAllowed = familyBankingAllowed + childBankingAllowed
        // Publish the banking allow-list BEFORE the block list. Both are read by
        // the accessibility service and the lockbox, and applying them in this
        // order means a rule change can never leave a moment where an app is
        // blocked but not yet known to be banking-allowed.
        SensitiveApps.packages = SensitiveApps.DEFAULTS + bankingAllowed
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

    /**
     * Watches the family's web-filter rule and keeps [WebFilter] in memory so
     * the accessibility service can block bad sites from the browser address
     * bar — no VPN, so browsing stays fast. Enabled category lists are fetched
     * by [CategoryFeed] in the background.
     */
    private fun attachWebFilterListener() {
        val familyId = ChildStore.familyId(this) ?: return
        track(
            FirebaseFirestore.getInstance()
                .collection("families").document(familyId)
                .collection("rules").document("webFilter")
                .addSnapshotListener { snap, e ->
                    if (e != null) {
                        Diag.warn(this, "webFilterListener", e)
                        return@addSnapshotListener
                    }
                    // Only the per-family custom blocked sites live here now. The
                    // safe-browsing master, blocked categories, browser lock and
                    // content keywords are all global (site-admin) settings — see
                    // attachWebPolicyListener / attachContentFilterListener.
                    WebFilter.updateSites(
                        (snap?.get("blockedSites") as? List<*>)
                            ?.mapNotNull { (it as? String)?.lowercase()?.removePrefix("www.") }
                            ?.toSet() ?: emptySet()
                    )
                    // The old DNS-filter VPN is no longer used.
                    WebFilterVpnService.stop(this)
                }
        )
    }

    /**
     * Watches the global content-filter config (`appConfig/contentFilter`): the
     * site admin's per-category keyword lists plus any flat `keywords`. All are
     * unioned into the page-content block set and applied on every device.
     */
    private fun attachContentFilterListener() {
        track(
            FirebaseFirestore.getInstance()
                .collection("appConfig").document("contentFilter")
                .addSnapshotListener { snap, e ->
                    if (e != null) {
                        Diag.warn(this, "contentFilterListener", e)
                        return@addSnapshotListener
                    }
                    val words = HashSet<String>()
                    fun collect(list: Any?): Set<String> {
                        val out = HashSet<String>()
                        (list as? List<*>)?.forEach { item ->
                            (item as? String)?.trim()?.lowercase()
                                ?.takeIf { it.length >= 3 }?.let { out.add(it) }
                        }
                        words.addAll(out)
                        return out
                    }
                    collect(snap?.get("keywords"))
                    val byCategory = HashMap<String, Set<String>>()
                    (snap?.get("categories") as? Map<*, *>)?.forEach { (cat, list) ->
                        val name = (cat as? String)?.trim()?.lowercase()
                        val terms = collect(list)
                        if (!name.isNullOrEmpty() && terms.isNotEmpty()) {
                            byCategory[name] = terms
                        }
                    }
                    ContentFilter.backendKeywords = words
                    ContentFilter.backendByCategory = byCategory
                }
        )
    }

    /**
     * Watches the site admin's global browser / safe-browsing policy
     * (`appConfig/webPolicy`): the safe-browsing master switch, whether browsers
     * other than Chrome are blocked, and whether incognito is allowed.
     */
    private fun attachWebPolicyListener() {
        track(
            FirebaseFirestore.getInstance()
                .collection("appConfig").document("webPolicy")
                .addSnapshotListener { snap, e ->
                    if (e != null) {
                        Diag.warn(this, "webPolicyListener", e)
                        return@addSnapshotListener
                    }
                    // Safe browsing is permanent: nobody, not even the site
                    // admin, can switch off the filter that makes this app
                    // worth installing. Only the extras below are configurable.
                    val allowIncognito = snap?.getBoolean("allowIncognito") == true
                    DeviceLockdown.setIncognitoAllowed(this, allowIncognito)
                    // The protective categories are as permanent as the filter
                    // itself: whatever the policy doc says, they stay blocked.
                    val cats = WebFilter.PROTECTIVE_CATEGORIES
                    // One atomic swap, so a decision can never see the new
                    // categories alongside the old safe-browsing flag.
                    WebFilter.updatePolicy(
                        enabled = true,
                        blockOtherBrowsers = snap?.getBoolean("blockOtherBrowsers") == true,
                        categories = cats,
                    )
                    if (cats.isNotEmpty()) {
                        Thread {
                            try {
                                CategoryFeed.loadCache(applicationContext)
                            } catch (t: Throwable) {
                                Diag.warn(this, "categoryFeedCache", t)
                            }
                        }.apply { isDaemon = true }.start()
                        CategoryFeed.ensure(applicationContext, cats)
                    }
                }
        )
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // MIN keeps it out of the status bar and at the bottom of the
            // shade. Android won't let a foreground service run with no
            // notification at all, so this is as quiet as it gets — the only
            // notice the child should actually notice is the setup one.
            val channel = NotificationChannel(
                CHANNEL_ID, "Protection", NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps Maryada protection active."
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
            // The old LOW channel would keep its status-bar icon forever;
            // importance can't be lowered once a channel exists.
            try {
                nm.deleteNotificationChannel(LEGACY_CHANNEL_ID)
            } catch (_: Exception) {
            }
        }
        val notification: Notification =
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, CHANNEL_ID)
            else
                @Suppress("DEPRECATION") Notification.Builder(this))
                .setContentTitle("Maryada is active")
                .setContentText("Family protection is on.")
                .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setOngoing(true)
                .apply {
                    @Suppress("DEPRECATION")
                    setPriority(Notification.PRIORITY_MIN)
                }
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
        private const val CHANNEL_ID = "guardnest_protection_min"
        private const val LEGACY_CHANNEL_ID = "guardnest_protection"
        private const val NOTIF_ID = 1001
        private const val EVAL_INTERVAL_MS = 30_000L
        private const val LOCKGUARD_INTERVAL_MS = 700L
        private const val LOCKGUARD_IDLE_MS = 3_000L

        /** Activity feeds stored as one array document per device. */
        private val REPORT_FEEDS = listOf(
            "webHistory", "callHistory", "smsHistory", "youtubeHistory",
            "appCalls",
        )
        private const val FOREGROUND_FRESH_MS = 10_000L
        private const val FOREGROUND_QUERY_MS = 1_500L
        // Every one of these costs a Firestore write, and the free tier allows
        // 20,000 a day for the WHOLE family. At 50 children that is a budget of
        // 400 writes per device per day, so nothing here reports on a timer
        // unless it has something new to say.
        //
        // The heartbeat is the exception: the parent publishes an interval
        // derived from the profile count (see rules/reporting), and this is
        // only the fallback for a device that has not read one yet.
        private const val DEFAULT_HEARTBEAT_MS = 1_200_000L // 20 min
        // A published value is still clamped: too small would burn the family's
        // whole allowance, and past an hour of silence the parent would start
        // calling a healthy phone "not reporting".
        private const val MIN_HEARTBEAT_MS = 300_000L // 5 min
        private const val MAX_HEARTBEAT_MS = 1_800_000L // 30 min
        private const val LOCATION_MS = 300_000L
        private const val LOCATION_HISTORY_MS = 1_800_000L
        // A new place must be at least this far from the last one recorded, and
        // further than the fix's own accuracy.
        private const val HISTORY_MIN_DISTANCE_M = 250f
        // How long the child must still be there before it counts as a visit
        // rather than somewhere they were passing through.
        private const val HISTORY_DWELL_MS = 10 * 60 * 1000L
        // Far enough that it is plainly a different place; recorded at once so
        // a journey isn't lost waiting for a dwell to confirm it.
        private const val HISTORY_TELEPORT_M = 3_000f
        private const val WEBHISTORY_MS = 300_000L
        private const val CALLS_MS = 300_000L
        private const val PERM_PROMPT_MS = 60_000L
        private const val SMS_MS = 300_000L
        private const val MESSAGES_MS = 120_000L
        private const val YOUTUBE_MS = 300_000L
        private const val APP_CALLS_MS = 300_000L
        private const val UPDATE_CHECK_MS = 3 * 60 * 60 * 1000L // 3 hours
        /** Tolerance before a chat time is treated as belonging to yesterday. */
        private const val FUTURE_SLACK_MS = 5 * 60 * 1000L

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

        /**
         * After Temporary Access, the child restores protection by turning the
         * accessibility service back on. When they do, lift the call-log/SMS
         * denials we applied for the banking session so monitoring fully resumes
         * and the lockbox can release. Safe to call often — it no-ops unless a
         * Temporary Access session is active and accessibility is back on.
         */
        fun restoreTempAccessIfRecovered(ctx: Context) {
            if (!ChildStore.tempAccess(ctx)) return
            if (Permissions.hasAccessibility(ctx)) {
                DeviceLockdown.setSensitivePermissions(ctx, granted = true)
                // Re-enable the notification-listener component so the child can
                // allow Notification access again from the setup screen.
                DeviceLockdown.setNotificationListenerEnabled(ctx, enabled = true)
                ChildStore.setTempAccess(ctx, false)
            }
        }
    }
}

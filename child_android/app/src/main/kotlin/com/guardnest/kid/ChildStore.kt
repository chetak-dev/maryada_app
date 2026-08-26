package com.guardnest.kid

import android.content.Context

/**
 * Remembers which family/child this device is paired to, so it stays paired
 * across relaunches without re-entering a code.
 */
object ChildStore {
    private const val PREFS = "guardnest_kid"
    private const val KEY_FAMILY = "familyId"
    private const val KEY_CHILD = "childId"
    private const val KEY_FAMILY_NAME = "familyName"

    // "Banking mode" / lockbox state. When a required protection is off we
    // suspend every app except the allow-list; these keys let the state survive
    // a service restart so we can precisely undo it when protections return.
    private const val KEY_LOCKBOX = "lockboxActive"
    private const val KEY_LOCKBOX_SINCE = "lockboxSince"
    private const val KEY_LOCKBOX_SUSPENDED = "lockboxSuspended"

    // Set while the child has tapped "Temporary Access": we deliberately turned
    // monitoring off (and, as Device Owner, denied our own call-log/SMS) for a
    // banking session. The flag lets the enforcement service restore those
    // permissions automatically once protection is turned back on.
    private const val KEY_TEMP_ACCESS = "tempAccess"
    private const val KEY_TEMP_NOTICE = "tempAccessNotice"

    // UI theme: "system" (default), "light" or "dark".
    private const val KEY_THEME = "themeMode"

    // Set once this device's `devices/{uid}` registration has been accepted.
    private const val KEY_DEVICE_REGISTERED = "deviceRegistered"

    // The last server-side history wipe this device has honoured locally.
    private const val KEY_HISTORY_CLEARED = "historyClearedAt"

    // The name the parent gave this device when generating the pairing code.
    private const val KEY_DEVICE_NAME = "deviceName"

    // Set once the legacy shared `current` activity feeds have been moved onto
    // this device's own per-device documents.
    private const val KEY_REPORTS_MIGRATED = "reportsMigrated"

    // The last point appended to the location trail. Held on disk because the
    // OS restarts the service constantly, and an in-memory copy meant every
    // restart recorded the child's current place again as if it were new.
    private const val KEY_TRAIL_LAT = "trailLat"
    private const val KEY_TRAIL_LNG = "trailLng"
    private const val KEY_TRAIL_AT = "trailAt"

    // When the accessibility service was first seen granted but not running.
    // On disk because an OEM kill usually takes our own service with it.
    private const val KEY_AX_STALL_SINCE = "accessibilityStallSince"

    // The last parent-triggered sync this device has already acted on.
    private const val KEY_SYNC_REQUESTED = "syncRequestedAt"

    // Heartbeat interval the family last published, so a restart keeps the
    // agreed cadence instead of falling back to the default for a cycle.
    private const val KEY_HEARTBEAT_MS = "heartbeatMs"

    // A place the child has arrived at but not yet stayed long enough for it to
    // count as a visit.
    private const val KEY_PENDING_LAT = "pendingLat"
    private const val KEY_PENDING_LNG = "pendingLng"
    private const val KEY_PENDING_AT = "pendingAt"

    // Set once the shared pre-per-device usage document has been cleaned up.
    private const val KEY_LEGACY_USAGE_DROPPED = "legacyUsageDropped"

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun themeMode(ctx: Context): String =
        prefs(ctx).getString(KEY_THEME, "system") ?: "system"

    fun setThemeMode(ctx: Context, mode: String) {
        prefs(ctx).edit().putString(KEY_THEME, mode).apply()
    }

    fun save(ctx: Context, familyId: String, childId: String) {
        prefs(ctx).edit()
            .putString(KEY_FAMILY, familyId)
            .putString(KEY_CHILD, childId)
            .apply()
    }

    fun familyId(ctx: Context): String? = prefs(ctx).getString(KEY_FAMILY, null)
    fun childId(ctx: Context): String? = prefs(ctx).getString(KEY_CHILD, null)

    fun deviceRegistered(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_DEVICE_REGISTERED, false)

    fun setDeviceRegistered(ctx: Context, value: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_DEVICE_REGISTERED, value).apply()
    }

    fun historyClearedAt(ctx: Context): Long =
        prefs(ctx).getLong(KEY_HISTORY_CLEARED, 0L)

    fun setHistoryClearedAt(ctx: Context, at: Long) {
        prefs(ctx).edit().putLong(KEY_HISTORY_CLEARED, at).apply()
    }

    fun deviceName(ctx: Context): String =
        prefs(ctx).getString(KEY_DEVICE_NAME, "") ?: ""

    fun setDeviceName(ctx: Context, name: String) {
        prefs(ctx).edit().putString(KEY_DEVICE_NAME, name).apply()
    }

    fun reportsMigrated(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_REPORTS_MIGRATED, false)

    fun setReportsMigrated(ctx: Context, value: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_REPORTS_MIGRATED, value).apply()
    }

    /** The last point written to the location trail: lat, lng and when. */
    fun lastTrailPoint(ctx: Context): Triple<Double, Double, Long>? {
        val p = prefs(ctx)
        if (!p.contains(KEY_TRAIL_LAT)) return null
        return Triple(
            java.lang.Double.longBitsToDouble(p.getLong(KEY_TRAIL_LAT, 0L)),
            java.lang.Double.longBitsToDouble(p.getLong(KEY_TRAIL_LNG, 0L)),
            p.getLong(KEY_TRAIL_AT, 0L),
        )
    }

    fun setLastTrailPoint(ctx: Context, lat: Double, lng: Double, at: Long) {
        prefs(ctx).edit()
            .putLong(KEY_TRAIL_LAT, java.lang.Double.doubleToRawLongBits(lat))
            .putLong(KEY_TRAIL_LNG, java.lang.Double.doubleToRawLongBits(lng))
            .putLong(KEY_TRAIL_AT, at)
            .apply()
    }

    /** 0 when the accessibility service is running normally. */
    fun accessibilityStallSince(ctx: Context): Long =
        prefs(ctx).getLong(KEY_AX_STALL_SINCE, 0L)

    fun setAccessibilityStallSince(ctx: Context, at: Long) {
        prefs(ctx).edit().putLong(KEY_AX_STALL_SINCE, at).apply()
    }

    fun syncRequestedAt(ctx: Context): Long =
        prefs(ctx).getLong(KEY_SYNC_REQUESTED, 0L)

    fun setSyncRequestedAt(ctx: Context, at: Long) {
        prefs(ctx).edit().putLong(KEY_SYNC_REQUESTED, at).apply()
    }

    /** Published heartbeat interval, or [fallback] before one has arrived. */
    fun heartbeatMs(ctx: Context, fallback: Long): Long =
        prefs(ctx).getLong(KEY_HEARTBEAT_MS, fallback)

    fun setHeartbeatMs(ctx: Context, ms: Long) {
        prefs(ctx).edit().putLong(KEY_HEARTBEAT_MS, ms).apply()
    }

    /** Candidate place awaiting a dwell, or null when the child is settled. */
    fun pendingPlace(ctx: Context): Triple<Double, Double, Long>? {
        val p = prefs(ctx)
        if (!p.contains(KEY_PENDING_AT)) return null
        return Triple(
            java.lang.Double.longBitsToDouble(p.getLong(KEY_PENDING_LAT, 0L)),
            java.lang.Double.longBitsToDouble(p.getLong(KEY_PENDING_LNG, 0L)),
            p.getLong(KEY_PENDING_AT, 0L),
        )
    }

    fun setPendingPlace(ctx: Context, lat: Double, lng: Double, at: Long) {
        prefs(ctx).edit()
            .putLong(KEY_PENDING_LAT, java.lang.Double.doubleToRawLongBits(lat))
            .putLong(KEY_PENDING_LNG, java.lang.Double.doubleToRawLongBits(lng))
            .putLong(KEY_PENDING_AT, at)
            .apply()
    }

    fun clearPendingPlace(ctx: Context) {
        prefs(ctx).edit()
            .remove(KEY_PENDING_LAT)
            .remove(KEY_PENDING_LNG)
            .remove(KEY_PENDING_AT)
            .apply()
    }

    fun legacyUsageDropped(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_LEGACY_USAGE_DROPPED, false)

    fun setLegacyUsageDropped(ctx: Context, value: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_LEGACY_USAGE_DROPPED, value).apply()
    }

    /** The family's display name (shown on the status screen), if known. */
    fun familyName(ctx: Context): String? =
        prefs(ctx).getString(KEY_FAMILY_NAME, null)?.takeIf { it.isNotBlank() }

    fun setFamilyName(ctx: Context, name: String) {
        prefs(ctx).edit().putString(KEY_FAMILY_NAME, name.trim()).apply()
    }

    fun isPaired(ctx: Context): Boolean =
        familyId(ctx) != null && childId(ctx) != null

    fun clear(ctx: Context) {
        prefs(ctx).edit().clear().apply()
    }

    // ----- Lockbox / banking-mode state -----

    fun lockboxActive(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_LOCKBOX, false)

    fun lockboxSince(ctx: Context): Long =
        prefs(ctx).getLong(KEY_LOCKBOX_SINCE, 0L)

    /** The exact packages we suspended when entering lockbox, so exit is precise. */
    fun lockboxSuspended(ctx: Context): Set<String> =
        prefs(ctx).getStringSet(KEY_LOCKBOX_SUSPENDED, emptySet()) ?: emptySet()

    fun enterLockbox(ctx: Context, suspended: Set<String>, since: Long) {
        prefs(ctx).edit()
            .putBoolean(KEY_LOCKBOX, true)
            .putLong(KEY_LOCKBOX_SINCE, since)
            .putStringSet(KEY_LOCKBOX_SUSPENDED, suspended)
            .apply()
    }

    fun exitLockbox(ctx: Context) {
        prefs(ctx).edit()
            .putBoolean(KEY_LOCKBOX, false)
            .remove(KEY_LOCKBOX_SINCE)
            .remove(KEY_LOCKBOX_SUSPENDED)
            .apply()
    }

    // ----- Temporary Access (banking) state -----

    fun tempAccess(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_TEMP_ACCESS, false)

    fun setTempAccess(ctx: Context, on: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_TEMP_ACCESS, on).apply()
    }

    /**
     * Whether the banking-mode notice is still owed. Outlives [tempAccess],
     * which clears as soon as accessibility is back on: the notice has to stay
     * until *every* protection the session switched off is granted again.
     */
    fun tempAccessNotice(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_TEMP_NOTICE, false)

    fun setTempAccessNotice(ctx: Context, on: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_TEMP_NOTICE, on).apply()
    }
}

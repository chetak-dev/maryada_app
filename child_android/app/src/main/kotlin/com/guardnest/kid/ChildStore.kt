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

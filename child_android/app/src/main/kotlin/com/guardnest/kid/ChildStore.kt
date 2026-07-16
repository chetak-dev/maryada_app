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

    // "Banking mode" / lockbox state. When a required protection is off we
    // suspend every app except the allow-list; these keys let the state survive
    // a service restart so we can precisely undo it when protections return.
    private const val KEY_LOCKBOX = "lockboxActive"
    private const val KEY_LOCKBOX_SINCE = "lockboxSince"
    private const val KEY_LOCKBOX_SUSPENDED = "lockboxSuspended"

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(ctx: Context, familyId: String, childId: String) {
        prefs(ctx).edit()
            .putString(KEY_FAMILY, familyId)
            .putString(KEY_CHILD, childId)
            .apply()
    }

    fun familyId(ctx: Context): String? = prefs(ctx).getString(KEY_FAMILY, null)
    fun childId(ctx: Context): String? = prefs(ctx).getString(KEY_CHILD, null)

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
}

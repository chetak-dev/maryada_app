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
}

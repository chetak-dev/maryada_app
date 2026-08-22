package com.guardnest.kid

import android.content.Context
import android.util.Log

/**
 * Diagnostics for a fleet we can't reach.
 *
 * Child devices are installed once and never touched again, so a silently
 * swallowed exception used to be invisible — enforcement could stop working
 * with no way to find out. Every failure that matters is funnelled through
 * here: it goes to logcat (for a device in hand) and the most recent one is
 * kept so [EnforcementService]'s heartbeat can report it onto the child doc,
 * where the parent/admin app can see it.
 *
 * Never throws: callers use this from inside catch blocks and enforcement
 * paths, where a secondary failure would be worse than the original one.
 */
object Diag {

    private const val TAG = "Maryada"
    private const val PREFS = "guardnest_diag"
    private const val KEY_LAST = "lastError"
    private const val KEY_LAST_AT = "lastErrorAt"

    /** Errors are only worth reporting once per key per this interval. */
    private const val THROTTLE_MS = 60_000L

    private val lock = Any()
    private val lastByKey = HashMap<String, Long>()

    @Volatile private var lastMessage: String? = null
    @Volatile private var lastAt: Long = 0L

    /**
     * Records a non-fatal failure. [where] is a short stable location tag (e.g.
     * "heartbeat", "reportUsage") — it's also the throttle key, so a failure
     * that repeats every tick is only recorded once a minute.
     */
    fun warn(ctx: Context?, where: String, error: Throwable? = null, detail: String? = null) {
        try {
            val now = System.currentTimeMillis()
            synchronized(lock) {
                val last = lastByKey[where] ?: 0L
                if (now - last < THROTTLE_MS) return
                lastByKey[where] = now
            }
            val reason = detail
                ?: error?.let { "${it.javaClass.simpleName}: ${it.message}" }
                ?: "failed"
            Log.w(TAG, "$where: $reason", error)
            val message = "$where: $reason".take(300)
            lastMessage = message
            lastAt = now
            ctx?.applicationContext
                ?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                ?.edit()
                ?.putString(KEY_LAST, message)
                ?.putLong(KEY_LAST_AT, now)
                ?.apply()
        } catch (_: Throwable) {
            // Diagnostics must never break the caller.
        }
    }

    /** The most recent recorded failure, or null if none this install. */
    fun lastError(ctx: Context): String? = try {
        lastMessage ?: ctx.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_LAST, null)
    } catch (_: Throwable) {
        null
    }

    /** When [lastError] happened (epoch millis), or 0. */
    fun lastErrorAt(ctx: Context): Long = try {
        if (lastAt != 0L) lastAt
        else ctx.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_LAST_AT, 0L)
    } catch (_: Throwable) {
        0L
    }

    /** Clears the breadcrumb only when it came from [where]. */
    fun clearIf(ctx: Context, where: String): Boolean = try {
        val prefix = "$where:"
        val prefs = ctx.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = lastMessage ?: prefs.getString(KEY_LAST, null)
        if (current?.startsWith(prefix) != true) {
            false
        } else {
            lastMessage = null
            lastAt = 0L
            synchronized(lock) { lastByKey.remove(where) }
            prefs.edit().remove(KEY_LAST).remove(KEY_LAST_AT).apply()
            true
        }
    } catch (_: Throwable) {
        false
    }

    /**
     * Drops the breadcrumb if nothing new has been recorded since [asOf].
     *
     * Called when a heartbeat write succeeds: reaching Firestore proves the
     * device is working, so whatever failed before it has passed. Without this
     * the last failure stuck in prefs forever and the parent kept seeing "the
     * device reported a problem" for a blip that had long since resolved.
     */
    fun clearResolved(ctx: Context, asOf: Long) {
        try {
            if (asOf <= 0L) return
            val prefs = ctx.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val storedAt = if (lastAt != 0L) lastAt else prefs.getLong(KEY_LAST_AT, 0L)
            if (storedAt > asOf) return
            lastMessage = null
            lastAt = 0L
            synchronized(lock) { lastByKey.clear() }
            prefs.edit().remove(KEY_LAST).remove(KEY_LAST_AT).apply()
        } catch (_: Throwable) {
        }
    }
}

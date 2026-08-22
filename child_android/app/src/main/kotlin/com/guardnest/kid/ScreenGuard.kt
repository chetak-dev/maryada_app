package com.guardnest.kid

import android.content.Context
import java.util.Calendar

/**
 * Screen-time enforcement: pause and bedtime. Bedtime is evaluated by local
 * clock time so it works fully offline. When the device should be locked
 * (paused, or inside the bedtime window) we lock the screen.
 *
 * Times are "minutes from midnight" (0..1439), matching the parent app's rule
 * model, so the two sides speak the same language.
 */
object ScreenGuard {

    /** True while pause or bedtime is in effect (all apps blocked except
     *  emergency calls). Set by [EnforcementService], read by the accessibility
     *  service to bounce the child out of non-essential apps in real time. */
    @Volatile var locked = false

    /** "paused" / "resting (bedtime)" — for the on-screen message. */
    @Volatile var label = "paused"

    /** Title + message for the lock screen shown when the child opens an app
     *  during pause/bedtime. Set by [EnforcementService] so both the enforcement
     *  loop and the accessibility service show the same text (with the real
     *  bedtime schedule). */
    @Volatile var lockTitle = "Paused"
    @Volatile var lockSubtitle = "Your device is paused by your parent."

    /** True if [now] (minutes from midnight) is within [start, end), handling
     *  overnight windows like 21:00 -> 07:00. */
    fun isWithinWindow(now: Int, start: Int, end: Int): Boolean {
        if (start == end) return false
        return if (start < end) now in start until end else (now >= start || now < end)
    }

    fun nowMinutes(): Int {
        val c = Calendar.getInstance()
        return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
    }

    /**
     * Decides whether the device should currently be locked, from the family's
     * screen-time rule.
     */
    fun shouldLock(
        paused: Boolean,
        bedtimeEnabled: Boolean,
        bedtimeStart: Int,
        bedtimeEnd: Int,
        now: Int = nowMinutes(),
    ): Boolean {
        if (paused) return true
        if (!bedtimeEnabled) return false
        return isWithinWindow(now, bedtimeStart, bedtimeEnd)
    }

    /** Applies the lock decision: locks the screen now when it should be locked. */
    fun enforce(
        ctx: Context,
        paused: Boolean,
        bedtimeEnabled: Boolean,
        bedtimeStart: Int,
        bedtimeEnd: Int,
    ): String {
        val lock = shouldLock(paused, bedtimeEnabled, bedtimeStart, bedtimeEnd)
        return if (lock) DeviceLockdown.lockNow(ctx) else "Unlocked (rules allow use)."
    }
}

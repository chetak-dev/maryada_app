package com.guardnest.kid

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Process
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Reads on-device usage (screen time) via the framework [UsageStatsManager] and
 * shapes it for the guardian's Activity screen. Requires the "Usage access"
 * special permission, which the user grants in Settings (there's no runtime
 * dialog for it). No third-party libraries.
 */
object UsageReporter {

    /** One day's total foreground time. */
    data class DayUsage(val label: String, val minutes: Int)

    /** A single app's foreground time today. */
    data class AppUsage(val packageName: String, val label: String, val minutes: Int)

    /** A shaped summary ready to write to Firestore. */
    data class Summary(val week: List<DayUsage>, val topApps: List<AppUsage>)

    /** Whether the user has granted Usage Access to this app. */
    fun hasAccess(ctx: Context): Boolean {
        val appOps = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            ctx.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Opens the system "Usage access" settings screen for this app. */
    fun openSettings(ctx: Context) {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            ctx.startActivity(intent)
        } catch (_: Exception) {
            ctx.startActivity(
                Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /**
     * Today's total foreground minutes and top apps, from real foreground
     * sessions (see [foregroundMsByPackage]) so it only reflects apps the child
     * actually opened. Cheap enough to call on the main thread for the child's
     * own status screen. Returns null if access isn't granted.
     */
    fun today(ctx: Context): Pair<Int, List<AppUsage>>? {
        if (!hasAccess(ctx)) return null
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = ctx.packageManager
        val byPkg = usableApps(
            pm, ctx.packageName,
            foregroundMsByPackage(usm, startOfTodayMs(), System.currentTimeMillis())
        )
        val totalMin = (byPkg.values.sum() / 60000L).toInt()
        return totalMin to toAppUsage(pm, byPkg)
    }

    /**
     * Builds the last-7-days daily totals and today's top apps. Returns null if
     * access isn't granted (nothing to report yet).
     */
    fun build(ctx: Context): Summary? {
        if (!hasAccess(ctx)) return null
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = ctx.packageManager
        val dayFmt = SimpleDateFormat("EEE", Locale.getDefault())
        val now = System.currentTimeMillis()

        val week = ArrayList<DayUsage>(7)
        var todayApps: Map<String, Long> = emptyMap()

        for (dayOffset in 6 downTo 0) {
            val cal = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -dayOffset)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val startMs = cal.timeInMillis
            val endMs = minOf(startMs + 24L * 60 * 60 * 1000, now)
            val byPkg = usableApps(
                pm, ctx.packageName,
                foregroundMsByPackage(usm, startMs, endMs)
            )
            week.add(DayUsage(dayFmt.format(cal.time), (byPkg.values.sum() / 60000L).toInt()))
            if (dayOffset == 0) todayApps = byPkg
        }
        return Summary(week, toAppUsage(pm, todayApps))
    }

    // ----- Real foreground-time calculation (from UsageEvents) -----

    private fun startOfTodayMs(): Long = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /**
     * Real per-app foreground time in [startMs, endMs), computed by pairing
     * ACTIVITY_RESUMED / ACTIVITY_PAUSED (MOVE_TO_FOREGROUND/BACKGROUND) events.
     * This counts only time an app was actually on screen — unlike
     * queryAndAggregateUsageStats, whose totalTimeInForeground over-reports
     * (background/service foreground time, stale sessions), which made apps the
     * child never opened show minutes.
     */
    @Suppress("DEPRECATION")
    private fun foregroundMsByPackage(
        usm: UsageStatsManager, startMs: Long, endMs: Long
    ): Map<String, Long> {
        if (endMs <= startMs) return emptyMap()
        val totals = HashMap<String, Long>()
        val resumedAt = HashMap<String, Long>()
        val events = try {
            usm.queryEvents(startMs, endMs)
        } catch (_: Exception) {
            return emptyMap()
        }
        val ev = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            val pkg = ev.packageName ?: continue
            when (ev.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> resumedAt[pkg] = ev.timeStamp
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val from = resumedAt.remove(pkg) ?: continue
                    if (ev.timeStamp > from) {
                        totals[pkg] = (totals[pkg] ?: 0L) + (ev.timeStamp - from)
                    }
                }
            }
        }
        // Whatever is still in the foreground at the end of the window.
        for ((pkg, from) in resumedAt) {
            if (endMs > from) totals[pkg] = (totals[pkg] ?: 0L) + (endMs - from)
        }
        return totals
    }

    /**
     * Keeps only apps the child can actually open (launchable), dropping our own
     * app, home launchers, and anything under a minute so the list stays real.
     */
    private fun usableApps(
        pm: PackageManager, ownPkg: String, raw: Map<String, Long>
    ): Map<String, Long> {
        val launchers = launcherPackages(pm)
        return raw.filter { (pkg, ms) ->
            ms >= 60_000L &&
                pkg != ownPkg &&
                pkg !in launchers &&
                pm.getLaunchIntentForPackage(pkg) != null
        }
    }

    /** Home-screen launcher packages, excluded so "home" isn't shown as an app. */
    private fun launcherPackages(pm: PackageManager): Set<String> {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return try {
            pm.queryIntentActivities(home, 0)
                .mapNotNull { it.activityInfo?.packageName }
                .toSet()
        } catch (_: Exception) {
            emptySet()
        }
    }

    /** Sorts by time, takes the top 6, and resolves display labels. */
    private fun toAppUsage(pm: PackageManager, byPkg: Map<String, Long>): List<AppUsage> =
        byPkg.entries
            .sortedByDescending { it.value }
            .take(6)
            .map { (pkg, ms) ->
                val label = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                } catch (_: Exception) {
                    pkg
                }
                AppUsage(pkg, label, (ms / 60000L).toInt())
            }
}

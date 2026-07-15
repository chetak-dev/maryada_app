package com.guardnest.kid

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
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
     * Builds the last-7-days daily totals and today's top apps. Returns null if
     * access isn't granted (nothing to report yet).
     */
    fun build(ctx: Context): Summary? {
        if (!hasAccess(ctx)) return null
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = ctx.packageManager
        val dayFmt = SimpleDateFormat("EEE", Locale.getDefault())

        val week = ArrayList<DayUsage>(7)
        var todayTop: List<AppUsage> = emptyList()

        for (dayOffset in 6 downTo 0) {
            val start = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -dayOffset)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val startMs = start.timeInMillis
            val endMs = startMs + 24L * 60 * 60 * 1000

            val stats = try {
                usm.queryAndAggregateUsageStats(startMs, endMs)
            } catch (_: Exception) {
                emptyMap()
            }

            var dayTotalMs = 0L
            for (s in stats.values) dayTotalMs += s.totalTimeInForeground
            week.add(DayUsage(dayFmt.format(start.time), (dayTotalMs / 60000L).toInt()))

            if (dayOffset == 0) {
                todayTop = stats.values
                    .filter { it.totalTimeInForeground > 0 && it.packageName != ctx.packageName }
                    .sortedByDescending { it.totalTimeInForeground }
                    .take(6)
                    .map { s ->
                        val label = try {
                            pm.getApplicationLabel(
                                pm.getApplicationInfo(s.packageName, 0)
                            ).toString()
                        } catch (_: Exception) {
                            s.packageName
                        }
                        AppUsage(s.packageName, label, (s.totalTimeInForeground / 60000L).toInt())
                    }
            }
        }
        return Summary(week, todayTop)
    }
}

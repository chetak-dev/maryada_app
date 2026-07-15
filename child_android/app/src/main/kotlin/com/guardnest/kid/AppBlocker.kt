package com.guardnest.kid

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/**
 * App-blocking enforcement. As a **Device Owner**, GuardNest can suspend apps
 * (they can't be opened and are greyed out) without any accessibility hacks.
 *
 * These are the mechanisms the child app will drive from the family's rules
 * (screen time / app rules), enforced locally so they work fully offline.
 */
object AppBlocker {

    /** A launchable app on the device. */
    data class InstalledApp(val label: String, val packageName: String)

    /** Suspends the given packages (Device Owner required). */
    fun setBlocked(ctx: Context, packages: List<String>): String {
        val dpm = DeviceLockdown.dpm(ctx)
        val admin = DeviceLockdown.admin(ctx)
        if (!dpm.isDeviceOwnerApp(ctx.packageName)) return "Need Device Owner."
        return try {
            dpm.setPackagesSuspended(admin, packages.toTypedArray(), true)
            "Blocked ${packages.size} app(s)."
        } catch (e: Exception) {
            "Failed to block: ${e.message}"
        }
    }

    /** Un-suspends the given packages. */
    fun clearBlocked(ctx: Context, packages: List<String>): String {
        val dpm = DeviceLockdown.dpm(ctx)
        val admin = DeviceLockdown.admin(ctx)
        if (!dpm.isDeviceOwnerApp(ctx.packageName)) return "Need Device Owner."
        return try {
            dpm.setPackagesSuspended(admin, packages.toTypedArray(), false)
            "Unblocked ${packages.size} app(s)."
        } catch (e: Exception) {
            "Failed to unblock: ${e.message}"
        }
    }

    /** Whether a package is currently suspended (blocked). */
    fun isBlocked(ctx: Context, packageName: String): Boolean {
        return try {
            DeviceLockdown.dpm(ctx)
                .isPackageSuspended(DeviceLockdown.admin(ctx), packageName)
        } catch (e: Exception) {
            false
        }
    }

    /** The user-launchable apps installed on the device (for the app-rules UI). */
    fun launchableApps(ctx: Context): List<InstalledApp> {
        val pm = ctx.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val flags = PackageManager.MATCH_ALL
        val resolved = pm.queryIntentActivities(intent, flags)
        return resolved
            .mapNotNull { ri ->
                val pkg = ri.activityInfo?.packageName ?: return@mapNotNull null
                if (pkg == ctx.packageName) return@mapNotNull null // never list ourselves
                InstalledApp(ri.loadLabel(pm).toString(), pkg)
            }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
    }
}

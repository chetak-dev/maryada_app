package com.guardnest.kid

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.UserManager

/**
 * The tamper-proof core. When the app is a **Device Owner** (enrolled on a
 * factory-reset device — for testing: `adb shell dpm set-device-owner
 * com.guardnest.kid/.GuardNestAdminReceiver`), it can hard-block its own
 * uninstall and disable the escape hatches (factory reset, safe mode).
 *
 * These calls no-op unless the app is Device Owner, so they're safe to call.
 */
object DeviceLockdown {

    fun dpm(ctx: Context): DevicePolicyManager =
        ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    fun admin(ctx: Context): ComponentName =
        ComponentName(ctx, GuardNestAdminReceiver::class.java)

    fun isDeviceOwner(ctx: Context): Boolean =
        dpm(ctx).isDeviceOwnerApp(ctx.packageName)

    fun isAdminActive(ctx: Context): Boolean =
        dpm(ctx).isAdminActive(admin(ctx))

    /**
     * Applies the "can't be removed" protections. Requires Device Owner.
     * Note: we deliberately do NOT set DISALLOW_DEBUGGING_FEATURES during
     * testing (it would kill adb). Add it for production hardening.
     */
    fun applyProtection(ctx: Context): String {
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        if (!dpm.isDeviceOwnerApp(ctx.packageName)) {
            return "Not a Device Owner — enroll via adb first (see the app’s note)."
        }
        try {
            // The core: block this app's uninstall.
            dpm.setUninstallBlocked(admin, ctx.packageName, true)
            // Close the escape hatches.
            dpm.addUserRestriction(admin, UserManager.DISALLOW_FACTORY_RESET)
            dpm.addUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)
            dpm.addUserRestriction(admin, UserManager.DISALLOW_ADD_USER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                dpm.addUserRestriction(admin, UserManager.DISALLOW_REMOVE_USER)
            }
            return "Protection ON — app can’t be uninstalled; factory reset & safe mode disabled."
        } catch (e: SecurityException) {
            return "Failed to apply protection: ${e.message}"
        }
    }

    /** Lifts the protections (for testing / after parent-approved removal). */
    fun removeProtection(ctx: Context): String {
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        if (!dpm.isDeviceOwnerApp(ctx.packageName)) return "Not a Device Owner."
        try {
            dpm.setUninstallBlocked(admin, ctx.packageName, false)
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_FACTORY_RESET)
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_ADD_USER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                dpm.clearUserRestriction(admin, UserManager.DISALLOW_REMOVE_USER)
            }
            return "Protection OFF — app can be uninstalled again."
        } catch (e: SecurityException) {
            return "Failed to remove protection: ${e.message}"
        }
    }

    /** Immediately locks the screen. Works when the app is an active device admin
     * with the force-lock policy (or a Device Owner). This is what enforces
     * "pause" and bedtime. Guarded so it no-ops when the app has no admin rights,
     * to avoid accidental locking during setup.
     */
    fun lockNow(ctx: Context): String {
        val dpm = dpm(ctx)
        if (!dpm.isAdminActive(admin(ctx))) return "Locking needs device admin."
        return try {
            dpm.lockNow()
            "Locked."
        } catch (e: SecurityException) {
            "Couldn’t lock: ${e.message}"
        }
    }

    /**
     * Applies the strongest anti-removal protection available while paired. As a
     * Device Owner this blocks uninstall + factory reset outright; as a plain
     * device admin, Android already requires the admin be deactivated first (and
     * [GuardNestAdminReceiver.onDisableRequested] warns about that). Safe to call
     * repeatedly.
     */
    fun applyTamperProtection(ctx: Context) {
        if (isDeviceOwner(ctx)) applyProtection(ctx)
    }

    /**
     * Lifts protection so the app can be removed — called only when the parent
     * removes the device. Clears Device-Owner uninstall blocks, or deactivates
     * the device admin so the app can then be uninstalled normally.
     */
    fun releaseForRemoval(ctx: Context) {
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        try {
            if (dpm.isDeviceOwnerApp(ctx.packageName)) {
                removeProtection(ctx)
            } else if (dpm.isAdminActive(admin)) {
                dpm.removeActiveAdmin(admin)
            }
        } catch (_: Exception) {
        }
    }
}

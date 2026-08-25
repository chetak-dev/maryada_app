package com.guardnest.kid

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings

/**
 * Keeps the accessibility service alive on ROMs that kill it.
 *
 * Vivo, Oppo, Xiaomi and Huawei power managers stop background services and, on
 * some builds, drop the accessibility binding without clearing its switch. There
 * is no Android API to force a service to stay bound, so this closes the gap
 * from three directions:
 *
 *  1. [pinAgainstForceStop] — Device Owner marks the app as one the user (and
 *     the OEM's own task manager, which goes through the same path) may not
 *     force-stop or clear data on.
 *  2. [recover] — if the app holds `WRITE_SECURE_SETTINGS`, it re-enables its
 *     own service exactly as toggling it by hand would. This is the only real
 *     self-heal, and it needs one adb command at provisioning:
 *     `adb shell pm grant com.guardnest.kid android.permission.WRITE_SECURE_SETTINGS`
 *     (the permission is `development`-level, so adb can grant it). Run it in
 *     the same session as `dpm set-device-owner`.
 *  3. Failing both, [EnforcementService] escalates: after
 *     [Permissions.STALL_GRACE_MS] the device is treated as unprotected and the
 *     lockbox forces the child to fix it. A transient kill is ridden out; a
 *     genuinely dead service is never left running blind.
 */
object AccessibilityGuard {

    private fun component(ctx: Context): String =
        ComponentName(ctx, GuardNestAccessibilityService::class.java).flattenToString()

    /** Whether this install can re-enable its own service without the child. */
    fun canSelfHeal(ctx: Context): Boolean =
        ctx.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Puts the accessibility service back. Returns false when it could not be
     * done, which is the caller's cue to escalate.
     *
     * Temporary Access turns the service off deliberately, so it is never
     * fought here.
     */
    fun recover(ctx: Context): Boolean {
        if (ChildStore.tempAccess(ctx)) return false
        if (!canSelfHeal(ctx)) return false
        val cn = component(ctx)
        return try {
            val others = enabledServices(ctx).filterNot { it.equals(cn, ignoreCase = true) }
            // The system only (re)binds on a change, so a stalled service has to
            // be dropped before it can be added back — the same off/on the child
            // would do by hand in Settings.
            write(ctx, others)
            write(ctx, others + cn)
            Settings.Secure.putInt(
                ctx.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1
            )
            true
        } catch (e: Exception) {
            Diag.warn(ctx, "accessibilityRecover", e)
            false
        }
    }

    private fun enabledServices(ctx: Context): List<String> =
        (Settings.Secure.getString(
            ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: "").split(':').filter { it.isNotBlank() }

    private fun write(ctx: Context, services: List<String>) {
        Settings.Secure.putString(
            ctx.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            services.joinToString(":"),
        )
    }

    /**
     * Stops Settings and OEM "phone manager" apps from force-stopping or
     * clearing this app's data. Only this package is pinned: the blanket
     * `DISALLOW_APPS_CONTROL` restriction would also stop the child uninstalling
     * anything else, which is not what a parent asked for.
     */
    fun pinAgainstForceStop(ctx: Context, pinned: Boolean = true) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) return
        if (!DeviceLockdown.isDeviceOwner(ctx)) return
        try {
            DeviceLockdown.dpm(ctx).setUserControlDisabledPackages(
                DeviceLockdown.admin(ctx),
                if (pinned) listOf(ctx.packageName) else emptyList(),
            )
        } catch (e: Exception) {
            Diag.warn(ctx, "pinAgainstForceStop", e)
        }
    }

    /**
     * The OEM battery/auto-start screen that has to be allowed by hand, or null
     * on a ROM that doesn't have one. Every one of these is an OEM-private
     * activity, so the intent is always tried defensively.
     */
    fun autoStartSettings(): android.content.Intent? {
        val target = when (android.os.Build.MANUFACTURER.lowercase()) {
            "vivo", "iqoo" -> "com.iqoo.secure" to
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
            "oppo", "realme", "oneplus" -> "com.coloros.safecenter" to
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            "xiaomi", "redmi", "poco" -> "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            "huawei", "honor" -> "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            "letv" -> "com.letv.android.letvsafe" to
                "com.letv.android.letvsafe.AutobootManageActivity"
            else -> return null
        }
        return android.content.Intent().setComponent(
            ComponentName(target.first, target.second)
        )
    }

    /** True on a ROM known to need the auto-start allowance. */
    fun needsAutoStartAllowance(): Boolean = autoStartSettings() != null

    /** Opens that screen, returning false if this ROM names it something else. */
    fun openAutoStartSettings(ctx: Context): Boolean {
        val intent = autoStartSettings() ?: return false
        return try {
            ctx.startActivity(intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }
}

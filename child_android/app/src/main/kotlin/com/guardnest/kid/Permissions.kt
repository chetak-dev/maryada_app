package com.guardnest.kid

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.PowerManager
import android.provider.Settings

/**
 * Central check for the protections the child device must keep granted. Shared
 * by the setup UI ([MainActivity]) and the enforcement service, so if the child
 * later turns a permission off, the service can detect it and pull the child
 * back to the permission screen.
 */
object Permissions {

    fun hasUsageAccess(ctx: Context): Boolean = UsageReporter.hasAccess(ctx)

    fun hasCallLog(ctx: Context): Boolean =
        ctx.checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED

    fun hasSms(ctx: Context): Boolean =
        ctx.checkSelfPermission(android.Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    fun hasNotificationAccess(ctx: Context): Boolean {
        val enabled = Settings.Secure.getString(
            ctx.contentResolver, "enabled_notification_listeners"
        ) ?: return false
        val cn = ComponentName(ctx, GuardNestNotificationListener::class.java)
            .flattenToString()
        return enabled.split(':').any { it.equals(cn, ignoreCase = true) }
    }

    fun hasVpnConsent(ctx: Context): Boolean = VpnService.prepare(ctx) == null

    fun hasBatteryExemption(ctx: Context): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    fun hasDeviceAdmin(ctx: Context): Boolean = DeviceLockdown.isAdminActive(ctx)

    fun hasOverlay(ctx: Context): Boolean = Settings.canDrawOverlays(ctx)

    fun hasAccessibility(ctx: Context): Boolean {
        val cn = ComponentName(ctx, GuardNestAccessibilityService::class.java)
            .flattenToString()
        val enabled = Settings.Secure.getString(
            ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.equals(cn, ignoreCase = true) }
    }

    /** True only when every required protection is currently granted. */
    fun allGranted(ctx: Context): Boolean =
        hasUsageAccess(ctx) && hasCallLog(ctx) && hasSms(ctx) &&
            hasNotificationAccess(ctx) &&
            hasBatteryExemption(ctx) && hasDeviceAdmin(ctx) &&
            hasOverlay(ctx) && hasAccessibility(ctx)
}

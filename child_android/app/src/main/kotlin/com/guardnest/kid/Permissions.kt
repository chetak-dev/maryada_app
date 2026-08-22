package com.guardnest.kid

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.PowerManager
import android.os.SystemClock
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

    fun hasVpnConsent(ctx: Context): Boolean = VpnService.prepare(ctx) == null

    fun hasBatteryExemption(ctx: Context): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    fun hasDeviceAdmin(ctx: Context): Boolean = DeviceLockdown.isAdminActive(ctx)

    fun hasOverlay(ctx: Context): Boolean = Settings.canDrawOverlays(ctx)

    /**
     * True only when the service is both listed in the setting *and* actually
     * connected. An app update leaves it enabled but unbound on some OEM ROMs:
     * the switch still looks on while no events are delivered, so monitoring
     * silently stops and the parent is told everything is fine.
     */
    fun hasAccessibility(ctx: Context): Boolean {
        val cn = ComponentName(ctx, GuardNestAccessibilityService::class.java)
            .flattenToString()
        val enabled = Settings.Secure.getString(
            ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val listed = enabled.split(':').any { it.equals(cn, ignoreCase = true) }
        return listed && AccessibilityController.service != null
    }

    /**
     * Notification access, which lets [GuardNestNotificationListener] read the
     * YouTube media session for full-screen/background watch history. It's a
     * REQUIRED protection (part of [allGranted]); when it's off the enforcement
     * lockbox restricts the device until it's granted. Temporary Access disables
     * the listener component (via DeviceLockdown), which correctly flips this to
     * false. The grant persists even if the OS kills the running service, so a
     * battery-manager kill does NOT trip the lockbox — only a real revoke does.
     */
    fun hasNotificationAccess(ctx: Context): Boolean {
        val cn = ComponentName(ctx, GuardNestNotificationListener::class.java)
        val flat = Settings.Secure.getString(
            ctx.contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return flat.split(':').any { ComponentName.unflattenFromString(it) == cn }
    }

    /** True only when every required protection is currently granted. */
    fun allGranted(ctx: Context): Boolean {
        val value = hasUsageAccess(ctx) && hasCallLog(ctx) && hasSms(ctx) &&
            hasBatteryExemption(ctx) && hasDeviceAdmin(ctx) &&
            hasOverlay(ctx) && hasAccessibility(ctx) && hasNotificationAccess(ctx)
        cached = value
        cachedAt = SystemClock.elapsedRealtime()
        return value
    }

    @Volatile private var cached = false
    @Volatile private var cachedAt = 0L
    private const val CACHE_MS = 3_000L

    /**
     * [allGranted] costs ~8 binder round-trips (two of them `Settings.Secure`
     * content-provider reads). The enforcement loop and every window change ask
     * for it, which was enough to make the whole phone feel slow, so those hot
     * callers get an answer that may be up to [CACHE_MS] old — a revoked
     * permission is still caught within seconds.
     */
    fun allGrantedCached(ctx: Context): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (cachedAt != 0L && now - cachedAt < CACHE_MS) return cached
        return allGranted(ctx)
    }

    /** Forces the next [allGrantedCached] to re-check (after a grant/revoke). */
    fun invalidateCache() {
        cachedAt = 0L
    }
}

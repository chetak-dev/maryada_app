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
     * The accessibility GRANT — the service is listed in the system setting.
     *
     * This is deliberately not "is the service running". Vivo, Oppo and Xiaomi
     * ROMs kill the service whenever they feel like it while leaving the switch
     * on; treating that as a revoked permission dropped the phone into the
     * lockbox and locked the child out of a device nobody had tampered with.
     * A real revoke clears the setting, and that is still caught instantly.
     */
    fun hasAccessibility(ctx: Context): Boolean {
        val cn = ComponentName(ctx, GuardNestAccessibilityService::class.java)
            .flattenToString()
        val enabled = Settings.Secure.getString(
            ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.equals(cn, ignoreCase = true) }
    }

    /**
     * Whether the granted service is actually connected. Granted but unbound
     * means no events are delivered, so blocking and capture are silently dead
     * and the child has to toggle it off and on again.
     *
     * The in-process reference alone is NOT proof of life. An OEM ROM can drop
     * the binding without ever calling onUnbind/onDestroy, and our own
     * foreground service keeps the process alive, so that reference then
     * reports a dead service as healthy for as long as the phone stays on —
     * telling the parent "Protected" while nothing at all is monitored. The
     * system's own bound-service list is the authority; it is the same list
     * `dumpsys accessibility` prints under "Bound services".
     */
    fun accessibilityBound(ctx: Context): Boolean {
        if (AccessibilityController.service == null) return false
        // A platform that won't answer must not be read as "dead" — that would
        // lock a child out of an untampered phone.
        val system = systemSaysBound(ctx) ?: return true
        if (!system) {
            android.util.Log.w(
                "Maryada",
                "accessibility: in-process reference is stale, system reports unbound",
            )
        }
        return system
    }

    /** Null when the platform declines to answer. */
    private fun systemSaysBound(ctx: Context): Boolean? = try {
        val am = ctx.getSystemService(Context.ACCESSIBILITY_SERVICE)
            as android.view.accessibility.AccessibilityManager
        val mine = ComponentName(ctx, GuardNestAccessibilityService::class.java)
        am.getEnabledAccessibilityServiceList(
            android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK
        )?.any { info ->
            val s = info.resolveInfo?.serviceInfo
            s != null && ComponentName(s.packageName, s.name) == mine
        }
    } catch (_: Exception) {
        null
    }

    /** Granted, but not delivering events — needs re-enabling in Settings. */
    fun accessibilityStalled(ctx: Context): Boolean =
        hasAccessibility(ctx) && !accessibilityBound(ctx)

    /**
     * How long a granted-but-dead accessibility service is tolerated before the
     * device counts as unprotected.
     *
     * An OEM power manager kills the service several times a day and it rebinds
     * on its own, so reacting instantly locked the child out of an untampered
     * phone. Tolerating it forever was worse: nothing would be monitored and
     * the parent's screen would still read "Protected".
     */
    const val STALL_GRACE_MS = 10 * 60 * 1000L

    /**
     * Accessibility as the lockbox sees it: granted, and either alive or dead
     * for less than [STALL_GRACE_MS].
     *
     * The stall clock is stamped here rather than by the caller. The enforcement
     * tick only runs every 30s, and this is read from the 700ms lock guard, so
     * waiting for the tick to stamp it meant an unstamped stall read as "dead"
     * and slammed the lockbox shut the instant the service was killed — exactly
     * the lockout the grace period exists to prevent.
     */
    fun accessibilityOk(ctx: Context): Boolean {
        if (!hasAccessibility(ctx)) return false
        val stalledSince = ChildStore.accessibilityStallSince(ctx)
        if (accessibilityBound(ctx)) {
            if (stalledSince != 0L) ChildStore.setAccessibilityStallSince(ctx, 0L)
            return true
        }
        val now = System.currentTimeMillis()
        if (stalledSince == 0L) {
            ChildStore.setAccessibilityStallSince(ctx, now)
            return true
        }
        return now - stalledSince < STALL_GRACE_MS
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
            hasOverlay(ctx) && accessibilityOk(ctx) && hasNotificationAccess(ctx)
        cached = value
        cachedAt = SystemClock.elapsedRealtime()
        return value
    }

    /** How many required protections are still missing (for the setup notice). */
    fun missingCount(ctx: Context): Int = listOf(
        hasUsageAccess(ctx),
        hasCallLog(ctx) && hasSms(ctx),
        hasBatteryExemption(ctx),
        hasDeviceAdmin(ctx),
        hasOverlay(ctx),
        accessibilityOk(ctx),
        hasNotificationAccess(ctx),
    ).count { !it }

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

package com.guardnest.kid

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
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

    /** This app's own runtime permissions that Temporary Access toggles. */
    private val SENSITIVE_PERMISSIONS = listOf(
        android.Manifest.permission.READ_CALL_LOG,
        android.Manifest.permission.READ_SMS,
    )

    /**
     * Grants or denies this app's OWN call-log/SMS permissions. Device Owner
     * only (no-ops otherwise). Temporary Access uses this to switch monitoring
     * off for a banking session, then restores it when the child turns
     * protection back on. Device admin is untouched, so the app still can't be
     * uninstalled. (Overlay, usage access and battery exemption have no revoke
     * API — they simply go unused while accessibility is off.)
     */
    fun setSensitivePermissions(ctx: Context, granted: Boolean) {
        if (!isDeviceOwner(ctx)) return
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        val state = if (granted) {
            DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
        } else {
            DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED
        }
        for (perm in SENSITIVE_PERMISSIONS) {
            try {
                dpm.setPermissionGrantState(admin, ctx.packageName, perm, state)
            } catch (e: Exception) {
                Diag.warn(ctx, "setSensitivePermissions", e)
            }
        }
    }

    /**
     * Pins this app's notification permission on. The Temporary Access notice
     * has to stay visible, and from API 33 the app-level notification toggle
     * *is* this permission — fixing it granted takes that switch away.
     */
    fun forceNotificationsAllowed(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (!isDeviceOwner(ctx)) return
        try {
            dpm(ctx).setPermissionGrantState(
                admin(ctx),
                ctx.packageName,
                android.Manifest.permission.POST_NOTIFICATIONS,
                DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
            )
        } catch (e: Exception) {
            Diag.warn(ctx, "forceNotificationsAllowed", e)
        }
    }

    /**
     * Enables or disables the notification-listener component. Disabling removes
     * it from the system's active notification listeners, so its monitoring
     * stops completely — used by Temporary Access so a banking session runs with
     * no listener attached. Re-enabling (on restore) makes it grantable again;
     * the child then re-allows Notification access from the setup screen. Works
     * without Device Owner (it's this app's own component).
     */
    fun setNotificationListenerEnabled(ctx: Context, enabled: Boolean) {
        try {
            val cn = ComponentName(ctx, GuardNestNotificationListener::class.java)
            val state = if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            ctx.packageManager.setComponentEnabledSetting(
                cn, state, PackageManager.DONT_KILL_APP
            )
        } catch (e: Exception) {
            Diag.warn(ctx, "setNotificationListenerEnabled", e)
        }
    }

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
            // Block cloned / parallel / dual apps: they run in a separate user
            // profile our per-user enforcement can't see, so a child could hide a
            // blocked app there. Prevent new managed/clone profiles, and remove
            // any secondary users that already exist.
            dpm.addUserRestriction(admin, UserManager.DISALLOW_ADD_MANAGED_PROFILE)
            if (Build.VERSION.SDK_INT >= 34) {
                // UserManager.DISALLOW_ADD_CLONE_PROFILE (API 34+).
                dpm.addUserRestriction(admin, "no_add_clone_profile")
            }
            // Bedtime and pause are decided by the device clock, so a child who
            // can set the time back could skip bedtime. Forcing network time
            // removes that bypass (and stops manual date/time changes entirely).
            requireNetworkTime(ctx)
            // OEM "phone manager" apps force-stop background services through
            // the same path Settings uses, which is how the accessibility
            // service kept dying on Vivo and Oppo.
            AccessibilityGuard.pinAgainstForceStop(ctx)
            removeSecondaryUsers(ctx)
            disableIncognito(ctx)
            return "Protection ON — app can’t be uninstalled; factory reset, safe mode & app cloning disabled."
        } catch (e: SecurityException) {
            Diag.warn(ctx, "applyProtection", e)
            return "Failed to apply protection: ${e.message}"
        }
    }

    /**
     * Pins the device to network-provided time (Device Owner only; no-ops
     * otherwise). Without this the child can defeat bedtime by changing the
     * clock, because the schedule is evaluated against local time.
     */
    fun requireNetworkTime(ctx: Context) {
        if (!isDeviceOwner(ctx)) return
        try {
            @Suppress("DEPRECATION")
            dpm(ctx).setAutoTimeRequired(admin(ctx), true)
        } catch (e: Exception) {
            Diag.warn(ctx, "requireNetworkTime", e)
        }
        try {
            dpm(ctx).addUserRestriction(admin(ctx), UserManager.DISALLOW_CONFIG_DATE_TIME)
        } catch (e: Exception) {
            Diag.warn(ctx, "disallowConfigDateTime", e)
        }
    }

    /** Chromium browsers that honour the IncognitoModeAvailability managed key. */
    private val INCOGNITO_BROWSERS = listOf(
        "com.android.chrome",
        "com.chrome.beta",
        "com.chrome.dev",
        "com.microsoft.emmx",   // Edge
        "com.brave.browser",
        "com.brave.browser_beta",
    )

    /**
     * Disables incognito / private browsing in supported browsers via the
     * managed-configuration channel (Device Owner only; no-ops otherwise).
     * `IncognitoModeAvailability = 1` means "Disabled", so the browser hides the
     * "New incognito tab" option entirely — no private browsing to miss.
     */
    fun disableIncognito(ctx: Context) {
        if (!isDeviceOwner(ctx)) return
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        for (pkg in INCOGNITO_BROWSERS) {
            try {
                val restrictions = android.os.Bundle().apply {
                    putInt("IncognitoModeAvailability", 1)
                }
                dpm.setApplicationRestrictions(admin, pkg, restrictions)
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Allows or blocks incognito / private browsing in supported browsers
     * (Device Owner only; no-ops otherwise). IncognitoModeAvailability: 0 =
     * available (allowed), 1 = disabled. Driven by the site admin's web policy.
     */
    fun setIncognitoAllowed(ctx: Context, allowed: Boolean) {
        if (!isDeviceOwner(ctx)) return
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        val value = if (allowed) 0 else 1
        for (pkg in INCOGNITO_BROWSERS) {
            try {
                val restrictions = android.os.Bundle().apply {
                    putInt("IncognitoModeAvailability", value)
                }
                dpm.setApplicationRestrictions(admin, pkg, restrictions)
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Removes any existing secondary users (Device Owner only) — e.g. an OEM
     * "second space" a child could use to run un-monitored copies of apps. Best
     * effort; OEM parallel-app profiles that aren't standard secondary users may
     * not be removable via the public API.
     */
    private fun removeSecondaryUsers(ctx: Context) {
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            for (user in dpm.getSecondaryUsers(admin)) {
                try {
                    dpm.removeUser(admin, user)
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
    }

    /** Lifts the protections (for testing / after parent-approved removal). */
    fun removeProtection(ctx: Context): String {
        val dpm = dpm(ctx)
        val admin = admin(ctx)
        if (!dpm.isDeviceOwnerApp(ctx.packageName)) return "Not a Device Owner."
        try {
            dpm.setUninstallBlocked(admin, ctx.packageName, false)
            AccessibilityGuard.pinAgainstForceStop(ctx, pinned = false)
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_FACTORY_RESET)
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_ADD_USER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                dpm.clearUserRestriction(admin, UserManager.DISALLOW_REMOVE_USER)
            }
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_ADD_MANAGED_PROFILE)
            if (Build.VERSION.SDK_INT >= 34) {
                dpm.clearUserRestriction(admin, "no_add_clone_profile")
            }
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_CONFIG_DATE_TIME)
            @Suppress("DEPRECATION")
            dpm.setAutoTimeRequired(admin, false)
            return "Protection OFF — app can be uninstalled again."
        } catch (e: SecurityException) {
            Diag.warn(ctx, "removeProtection", e)
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
        } catch (e: Exception) {
            Diag.warn(ctx, "releaseForRemoval", e)
        }
    }
}

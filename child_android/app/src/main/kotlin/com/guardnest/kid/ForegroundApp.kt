package com.guardnest.kid

/**
 * Tracks which app is currently in the foreground. Updated by
 * [GuardNestAccessibilityService] on every window change and read by
 * [WebFilterVpnService] so web history only logs domains looked up while the
 * child is actually using a browser (instead of every background app's traffic).
 */
object ForegroundApp {
    @Volatile
    var packageName: String = ""
        private set

    @Volatile
    var changedAt: Long = 0L
        private set

    fun set(pkg: String) {
        packageName = pkg
        changedAt = System.currentTimeMillis()
    }

    /** True if the current foreground app is a web browser. */
    fun isBrowserForeground(): Boolean = Pkgs.isBrowser(packageName)

    /** True if [pkg] is a web browser. */
    fun isBrowser(pkg: String): Boolean = Pkgs.isBrowser(pkg)
}

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

    /** Known browser packages across the common Android OEMs. */
    private val BROWSERS: Set<String> = setOf(
        "com.android.chrome", "com.chrome.beta", "com.chrome.dev", "com.chrome.canary",
        "org.mozilla.firefox", "org.mozilla.focus", "org.mozilla.fenix",
        "com.opera.browser", "com.opera.mini.native", "com.opera.gx",
        "com.brave.browser", "com.microsoft.emmx",
        "com.sec.android.app.sbrowser", "com.sec.android.app.sbrowser.beta",
        "com.duckduckgo.mobile.android", "com.UCMobile.intl", "com.UCMobile.x86",
        "com.mi.globalbrowser", "com.mi.globalbrowser.mini", "com.android.browser",
        "com.heytap.browser", "com.coloros.browser", "com.oppo.browser",
        "com.vivaldi.browser", "com.yandex.browser", "com.ecosia.android",
        "com.kiwibrowser.browser", "mark.via.gp", "acr.browser.lightning",
        "com.qwant.liberty", "org.torproject.torbrowser", "com.aloha.browser",
    )

    /** True if the current foreground app is a web browser. */
    fun isBrowserForeground(): Boolean {
        val pkg = packageName
        if (pkg.isEmpty()) return false
        return pkg in BROWSERS || pkg.contains("browser")
    }

    /** True if [pkg] is a web browser. */
    fun isBrowser(pkg: String): Boolean =
        pkg in BROWSERS || pkg.contains("browser")
}

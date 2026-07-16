package com.guardnest.kid

/**
 * Holds the family's active web-filter rule in memory so the accessibility
 * service can block bad sites straight from the browser address bar — no VPN,
 * so it doesn't slow the internet down.
 *
 * Fed by [EnforcementService] from the `rules/webFilter` document; the enabled
 * categories are matched against [CategoryFeed]'s downloaded domain lists.
 */
object WebFilter {

    @Volatile var enabled: Boolean = false
    @Volatile var blockedSites: Set<String> = emptySet()   // exact domains from the parent
    @Volatile var enabledCategories: Set<String> = emptySet()

    // "Only allow one browser": when on, every browser except [approvedBrowser]
    // is blocked, which closes the private/incognito gap for all browsers.
    // Safe browsing implies this with Chrome as the approved browser, so the
    // filter (which works via Chrome's address bar) can't be bypassed by using
    // a different browser or its private mode.
    @Volatile var blockOtherBrowsers: Boolean = false
    @Volatile var approvedBrowser: String? = null

    /** The browser package the child is allowed to use (defaults to Chrome). */
    fun effectiveApprovedBrowser(): String =
        approvedBrowser?.takeIf { it.isNotBlank() } ?: DEFAULT_BROWSER

    /** True when non-approved browsers should be locked (safe browsing on, or
     *  the explicit "block other browsers" flag). */
    fun shouldLockOtherBrowsers(): Boolean = enabled || blockOtherBrowsers

    const val DEFAULT_BROWSER = "com.android.chrome"

    /** True if [host] should be blocked (exact/subdomain site or a category hit). */
    fun isBlocked(host: String): Boolean {
        if (!enabled) return false
        val d = host.lowercase().removePrefix("www.")
        if (d.isEmpty()) return false
        if (blockedSites.any { d == it || d.endsWith(".$it") }) return true
        return CategoryFeed.isBlocked(d, enabledCategories)
    }
}

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

    /** True if [host] should be blocked (exact/subdomain site or a category hit). */
    fun isBlocked(host: String): Boolean {
        if (!enabled) return false
        val d = host.lowercase().removePrefix("www.")
        if (d.isEmpty()) return false
        if (blockedSites.any { d == it || d.endsWith(".$it") }) return true
        return CategoryFeed.isBlocked(d, enabledCategories)
    }
}

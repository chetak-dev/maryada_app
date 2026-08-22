package com.guardnest.kid

/**
 * Holds the active web-filter policy in memory so the accessibility service can
 * block bad sites straight from the browser address bar — no VPN, so it doesn't
 * slow the internet down.
 *
 * The whole policy lives in one immutable [Policy] behind a single volatile
 * reference. It used to be several independent `@Volatile` fields updated one
 * after another by the Firestore listeners, which meant a check running on the
 * accessibility thread could read a half-applied policy (e.g. new categories
 * with the old enabled flag) and let a blocked page through. Swapping one
 * snapshot makes every read self-consistent.
 *
 * Fed by [EnforcementService]: the per-family custom sites from
 * `rules/webFilter`, and the global switches from `appConfig/webPolicy`.
 */
object WebFilter {

    /**
     * One consistent view of the filter. Replaced wholesale, never mutated.
     *
     * "Only allow one browser" ([blockOtherBrowsers]): when on, every browser
     * except [approvedBrowser] is blocked, which closes the private/incognito
     * gap for all browsers. Safe browsing implies this with Chrome as the
     * approved browser, so the filter (which works via Chrome's address bar)
     * can't be bypassed by using a different browser or its private mode.
     */
    data class Policy(
        val enabled: Boolean = false,
        val blockedSites: Set<String> = emptySet(), // exact domains from the parent
        val enabledCategories: Set<String> = emptySet(),
        val blockOtherBrowsers: Boolean = false,
        val approvedBrowser: String? = null,
    )

    @Volatile
    private var policy = Policy()

    /** The current snapshot. Read once per decision so it can't change midway. */
    fun policy(): Policy = policy

    val enabled: Boolean get() = policy.enabled
    val blockedSites: Set<String> get() = policy.blockedSites
    val enabledCategories: Set<String> get() = policy.enabledCategories
    val blockOtherBrowsers: Boolean get() = policy.blockOtherBrowsers

    /** Applies the per-family custom blocked sites (from `rules/webFilter`). */
    @Synchronized
    fun updateSites(sites: Set<String>) {
        policy = policy.copy(blockedSites = sites)
    }

    /**
     * Applies the site admin's global policy (from `appConfig/webPolicy`) as one
     * atomic change, so the safe-browsing master, the browser lock and the
     * blocked categories can never be observed out of step with each other.
     */
    @Synchronized
    fun updatePolicy(
        enabled: Boolean,
        blockOtherBrowsers: Boolean,
        categories: Set<String>,
        approvedBrowser: String? = policy.approvedBrowser,
    ) {
        policy = policy.copy(
            enabled = enabled,
            blockOtherBrowsers = blockOtherBrowsers,
            enabledCategories = categories,
            approvedBrowser = approvedBrowser,
        )
    }

    /** The browser package the child is allowed to use (defaults to Chrome). */
    fun effectiveApprovedBrowser(): String =
        policy.approvedBrowser?.takeIf { it.isNotBlank() } ?: DEFAULT_BROWSER

    /** True when non-approved browsers should be locked. Follows the site
     *  admin's switch alone — safe browsing used to imply it, so turning the
     *  switch off changed nothing and every other browser stayed blocked. */
    fun shouldLockOtherBrowsers(): Boolean = policy.blockOtherBrowsers

    const val DEFAULT_BROWSER = "com.android.chrome"

    /** Alias domains that are really the same service, so blocking the canonical
     *  domain also blocks the alias (e.g. blocking youtube.com blocks youtu.be). */
    private val DOMAIN_ALIASES = mapOf(
        "youtu.be" to "youtube.com",
    )

    /** YouTube website domains. YouTube is always blocked in the *browser* (the
     *  child should use the YouTube app instead) — this is built in and does NOT
     *  depend on the parent's blocklist or the safe-browsing switch. It only
     *  affects the browser: the YouTube app is unaffected because app traffic
     *  never goes through this address-bar check. */
    private val YOUTUBE_WEB_DOMAINS = setOf(
        "youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
        "youtubekids.com",
    )

    /** True if [host] is a YouTube website domain (always blocked in browser). */
    fun isYoutubeWeb(host: String): Boolean {
        val d = host.lowercase().removePrefix("www.").removePrefix("m.")
        return YOUTUBE_WEB_DOMAINS.any { d == it || d.endsWith(".$it") }
    }

    /** Search-engine result pages. These merely *list links* (with snippets that
     *  may contain a keyword), so the page-text content scan is skipped for them
     *  to avoid blocking the results page itself — only the site the child
     *  actually opens is content-scanned. URL/host blocking still applies. */
    private val SEARCH_ENGINES = setOf(
        "bing.com", "duckduckgo.com", "search.yahoo.com", "ecosia.org",
        "startpage.com", "qwant.com", "baidu.com", "ask.com",
        "search.brave.com", "searx.be", "swisscows.com", "mojeek.com",
    )

    /** True if [host] is a search-engine results page (Google incl. all TLDs,
     *  Yandex, or one of [SEARCH_ENGINES]). */
    fun isSearchEngine(host: String): Boolean {
        val h = host.lowercase().removePrefix("www.")
        if (h == "google.com" || h.startsWith("google.") || h.contains(".google.")) {
            return true
        }
        if (h == "bing.com" || h.startsWith("yandex.")) return true
        return SEARCH_ENGINES.any { h == it || h.endsWith(".$it") }
    }

    /** True if [host] should be blocked (exact/subdomain site or a category hit). */
    fun isBlocked(host: String): Boolean = reasonFor(host) != null

    /**
     * Why [host] is blocked — a category id, [REASON_BLOCKLIST] for the parent's
     * own list, or null when it's allowed. The parent app turns this into a tag.
     */
    fun reasonFor(host: String): String? {
        val p = policy // one snapshot for the whole decision
        if (!p.enabled) return null
        val d = host.lowercase().removePrefix("www.")
        if (d.isEmpty()) return null
        if (matchesBlockedSite(d, p.blockedSites)) return REASON_BLOCKLIST
        // Treat a known alias as its canonical domain (youtu.be -> youtube.com).
        val canonical = DOMAIN_ALIASES[d]
        if (canonical != null && matchesBlockedSite(canonical, p.blockedSites)) {
            return REASON_BLOCKLIST
        }
        return CategoryFeed.categoryOf(d, p.enabledCategories)
    }

    const val REASON_BLOCKLIST = "blocklist"
    const val REASON_YOUTUBE = "youtube"
    const val REASON_KEYWORD = "keyword"
    const val REASON_CONTENT = "content"

    /** Curated per-category seed domains — blocked instantly and offline, before
     *  the live category feeds download. Shared with [WebFilterVpnService]. */
    val CATEGORY_SEEDS: Map<String, List<String>> = mapOf(
        "adult" to listOf(
            "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com",
            "redtube.com", "youporn.com",
        ),
        "gambling" to listOf(
            "bet365.com", "pokerstars.com", "williamhill.com", "888casino.com",
        ),
        "social" to listOf(
            "facebook.com", "instagram.com", "twitter.com", "x.com",
            "tiktok.com", "snapchat.com",
        ),
        "drugs" to listOf("leafly.com", "weedmaps.com"),
        "weapons" to listOf("armslist.com"),
        "violence" to listOf("liveleak.com"),
    )

    /** The seed category [domain] falls in (any category), or null. */
    fun seedCategoryOf(domain: String): String? {
        val d = domain.lowercase().removePrefix("www.")
        for ((cat, seeds) in CATEGORY_SEEDS) {
            if (seeds.any { d == it || d.endsWith(".$it") }) return cat
        }
        return null
    }

    /**
     * Best-effort category for tagging a block in the parent's activity list.
     * Checks every source regardless of which categories are enabled — a
     * gambling site the parent listed manually should still read "Gambling".
     * Never used for the blocking decision itself.
     */
    fun categoryHint(host: String): String? {
        val d = host.lowercase().removePrefix("www.")
        if (d.isEmpty()) return null
        return seedCategoryOf(d)
            ?: ContentFilter.matchHost(d)?.let { ContentFilter.categoryOf(it) }
            ?: CategoryFeed.categoryOfAny(d)
    }

    /** True if [domain] is on the blocklist, as an exact or parent domain. */
    private fun matchesBlockedSite(domain: String, sites: Set<String>): Boolean =
        sites.any { domain == it || domain.endsWith(".$it") }
}

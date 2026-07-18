package com.guardnest.kid

/**
 * Content-based page blocking. Complements the URL/host filter ([WebFilter]) by
 * scanning the *visible page text* (read via the accessibility service) for
 * unsafe terms. Works on HTTPS because it reads the rendered text on screen, not
 * the encrypted network traffic — no certificate interception needed.
 *
 * Matching is deliberately conservative to limit false positives:
 * - A parent-defined keyword blocks on a single hit (the parent chose it).
 * - A "strong" built-in term (unambiguous adult brands) blocks on a single hit.
 * - "Weak" generic terms need [WEAK_THRESHOLD] distinct hits on the same page.
 */
object ContentFilter {

    /** Parent-defined blocked words (lowercased), from the web-filter rule. */
    @Volatile var parentKeywords: Set<String> = emptySet()

    // Unambiguous adult brands/terms — a single occurrence blocks the page.
    private val STRONG = setOf(
        "pornhub", "xvideos", "xnxx", "xhamster", "redtube", "youporn",
        "brazzers", "onlyfans", "hentai", "camgirl", "camsoda", "chaturbate",
    )

    // Generic terms that can appear in legitimate contexts — need several
    // distinct hits before blocking.
    private val WEAK = setOf(
        "porn", "nsfw", "xxx", "sex video", "sex videos", "adult video",
        "nude photos", "nude pics", "escort service",
    )

    private const val WEAK_THRESHOLD = 2

    /**
     * Returns the term to block on, or null to allow. [textLower] must already
     * be lower-cased.
     */
    fun match(textLower: String): String? {
        if (textLower.isBlank()) return null

        // Parent keywords: a single match blocks.
        for (w in parentKeywords) {
            if (w.length >= 3 && textLower.contains(w)) return w
        }

        // Strong built-in terms: a single match blocks.
        for (t in STRONG) {
            if (textLower.contains(t)) return t
        }

        // Weak terms: require several distinct hits.
        var count = 0
        var first: String? = null
        for (t in WEAK) {
            if (textLower.contains(t)) {
                if (first == null) first = t
                count++
                if (count >= WEAK_THRESHOLD) return first
            }
        }
        return null
    }
}

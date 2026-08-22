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

    /** Extra words pushed from the backend (`appConfig/contentFilter`). */
    @Volatile var backendKeywords: Set<String> = emptySet()

    /**
     * The backend's words still grouped by the category they were filed under.
     * [backendKeywords] flattens them for matching; this keeps the category so a
     * block can be tagged with it — otherwise a page caught by a *gambling*
     * word was labelled from the domain instead, and read as adult content.
     */
    @Volatile var backendByCategory: Map<String, Set<String>> = emptyMap()

    // Unambiguous terms/brands/phrases — a single occurrence blocks the page.
    // Keyed by category so the parent's activity list can say *why* a page was
    // blocked, not just that a word matched.
    private val STRONG_BY_CATEGORY: Map<String, Set<String>> = mapOf(
        "adult" to setOf(
            "pornhub", "xvideos", "xnxx", "xhamster", "redtube", "youporn",
            "brazzers", "onlyfans", "hentai", "camgirl", "camsoda", "chaturbate",
            "spankbang", "redgifs", "youjizz", "tube8", "motherless", "tnaflix",
            "eporner", "porntrex", "fapello", "nhentai", "e-hentai", "hqporner",
            "beeg", "txxx", "hclips", "adultfriendfinder", "stripchat",
            "bongacams", "livejasmin", "myfreecams", "fansly", "manyvids",
            "rule34", "child porn",
            "spankwire", "keezmovies", "drtuber", "sunporno", "porn300",
            "porndig", "thumbzilla", "vporn", "faphouse", "javhd", "javbus",
            "missav", "hanime", "hentaihaven", "fakku", "pornhd", "4tube",
            "empflix", "xmoviesforyou", "desixnxx", "desipapa", "cam4",
            "flirt4free", "streamate", "imlive", "xhamsterlive", "porhub",
            "pornky", "okxxx", "3movs", "sexvid", "anysex",
        ),
        "gambling" to setOf(
            "1xbet", "bet365", "dafabet", "parimatch", "stake.com", "betway",
            "melbet", "22bet", "betwinner", "mostbet", "4rabet", "10cric",
            "casumo", "leovegas", "ladbrokes", "williamhill", "pokerstars",
            "betfair", "unibet", "888casino", "rummycircle", "pokerbaazi",
            "sattaking", "price boost", "bet slip", "betslip", "bet builder",
            "in-play betting", "sportsbook", "live betting",
            "1win", "linebet", "megapari", "rajabets", "fun88", "9winz",
            "betandreas", "pin-up casino", "crickex", "baji live", "babu88",
            "jeetwin", "betvisa", "lotus365", "laser247", "world777",
            "reddy anna", "mahadev book", "fairplay", "betbhai", "sky exchange",
            "skyexchange", "diamond exchange", "lords exchange",
            "tiger exchange", "gullybet", "indibet", "betdaily", "dpboss",
            "kalyan matka", "winzo", "junglee rummy", "a23 rummy", "rummy glee",
        ),
        "drugs" to setOf(
            "how to make meth", "buy cocaine", "buy heroin online", "buy mdma",
            "buy lsd", "buy fentanyl", "buy ketamine", "buy weed online",
            "order cocaine", "buy cannabis online", "buy meth online",
            "dark web drugs", "buy shrooms online",
        ),
        "weapons" to setOf(
            "how to make a bomb", "buy guns online", "buy a gun online",
            "buy a ghost gun",
        ),
        "violence" to setOf(
            "how to commit suicide", "ways to kill yourself", "suicide methods",
            "how to hang yourself", "painless suicide", "how to kill myself",
        ),
    )

    private val STRONG: Set<String> =
        STRONG_BY_CATEGORY.values.flatMapTo(LinkedHashSet()) { it }

    // Generic terms that also appear in legitimate contexts — need several
    // distinct hits before blocking.
    private val WEAK_BY_CATEGORY: Map<String, Set<String>> = mapOf(
        "adult" to setOf(
            "porn", "nsfw", "xxx", "sex video", "sex videos", "adult video",
            "porn video", "nude photos", "nude pics", "nude girls",
            "naked girls", "escort service", "sex cam", "camsex", "live sex",
            "sex chat", "webcam girls", "adult webcam", "milf", "blowjob",
            "threesome", "cumshot", "hardcore porn", "sex tube",
            "free porn", "sex movies", "porn site", "adult movies", "xxx video",
            "camgirls", "escort", "call girl", "anal sex", "gangbang",
            "creampie", "deepthroat", "handjob", "fetish porn", "sex stories",
            "adult chat", "nude video", "sexting", "onlyfans leak", "nude leak",
        ),
        "gambling" to setOf(
            "casino", "online casino", "poker", "betting", "roulette",
            "blackjack", "jackpot", "wager", "slot machine", "online lottery",
            "free spins", "place a bet", "betting odds", "deposit bonus",
            "real money casino", "teen patti", "andar bahar", "rummy",
            "satta matka", "lottery ticket", "cash out", "accumulator",
            "match odds", "free bet", "betting tips", "in-play",
            "cricket betting", "ipl betting", "online betting",
            "sports betting", "betting site", "betting app", "casino games",
            "win real money", "color prediction", "colour prediction",
            "aviator game", "crash game", "real cash game", "matka result",
            "spin and win", "dragon tiger",
        ),
        "drugs" to setOf(
            "cocaine", "heroin", "marijuana", "cannabis", "lsd", "mdma",
            "ecstasy", "methamphetamine", "buy drugs", "buy weed",
            "magic mushrooms", "fentanyl", "ketamine", "hashish", "opioids",
            "thc", "weed for sale", "cannabis oil", "buy hashish",
            "crystal meth",
        ),
        "violence" to setOf(
            "gore", "beheading", "graphic violence", "extremely graphic",
            "murder video", "execution video", "torture video", "snuff film",
            "self harm", "self-harm", "cutting myself", "pro ana", "thinspo",
            "gore video", "death video", "watch people die", "beheading video",
        ),
        "weapons" to setOf(
            "buy firearm", "buy ammunition", "buy handgun", "buy gun",
            "ghost gun", "buy ammo", "silencer for sale",
        ),
    )

    private val WEAK: Set<String> =
        WEAK_BY_CATEGORY.values.flatMapTo(LinkedHashSet()) { it }

    /** The category a matched term belongs to, or null for parent words. */
    fun categoryOf(term: String): String? {
        val t = term.lowercase()
        STRONG_BY_CATEGORY.forEach { (cat, set) -> if (t in set) return cat }
        backendByCategory.forEach { (cat, set) -> if (t in set) return cat }
        WEAK_BY_CATEGORY.forEach { (cat, set) -> if (t in set) return cat }
        return null
    }

    private const val WEAK_THRESHOLD = 2

    /**
     * Returns the term to block on, or null to allow. [textLower] must already
     * be lower-cased.
     */
    fun match(textLower: String): String? {
        if (textLower.isBlank()) return null

        // Parent + backend keywords: a single match blocks (curated lists).
        for (w in parentKeywords) {
            if (w.length >= 3 && textLower.contains(w)) return w
        }
        for (w in backendKeywords) {
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

    /**
     * Matches a bare host/domain against the parent, backend and STRONG lists
     * (single-word terms only) — so a site like parimatch.com / pornhub.com is
     * blocked by its domain even when the brand appears only as a logo image and
     * never as page text. Generic "weak" words are intentionally excluded here
     * to avoid blocking innocent domains (e.g. gore-tex.com).
     */
    fun matchHost(host: String): String? {
        if (host.isBlank()) return null
        val h = host.lowercase()
        for (w in parentKeywords) {
            if (w.length >= 3 && !w.contains(' ') && h.contains(w)) return w
        }
        for (w in backendKeywords) {
            if (w.length >= 3 && !w.contains(' ') && h.contains(w)) return w
        }
        for (t in STRONG) {
            if (!t.contains(' ') && h.contains(t)) return t
        }
        return null
    }
}

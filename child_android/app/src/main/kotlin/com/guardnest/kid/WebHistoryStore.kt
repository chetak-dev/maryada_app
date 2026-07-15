package com.guardnest.kid

/**
 * Central store for the child's web history.
 *
 * - "Visited" sites come from the browser's address bar (read by
 *   [GuardNestAccessibilityService]) so they reflect REAL navigations only —
 *   not the dozens of ad/CDN/analytics domains a page loads in the background.
 * - "Blocked" sites are fed by [WebFilterVpnService] when the DNS filter blocks
 *   a lookup.
 *
 * [EnforcementService] periodically flushes a [snapshot] to Firestore.
 */
object WebHistoryStore {

    private class Stat(var lastAt: Long) {
        var totalMs: Long = 0L
        var count: Int = 0
    }

    private const val MAX = 60
    private const val ACTIVE_GAP_MS = 5 * 60 * 1000L

    private val lock = Any()
    private val visited = LinkedHashMap<String, Stat>()
    private val blocked = LinkedHashMap<String, Stat>()

    // Time-on-site tracking for the currently open page.
    private var activeDomain: String? = null
    private var activeSince = 0L
    @Volatile private var dirty = false

    /** Records an actual page visit (from the browser address bar). */
    fun recordVisit(host: String) {
        val root = normalize(host) ?: return
        val now = System.currentTimeMillis()
        synchronized(lock) {
            if (root == activeDomain) {
                // Same page still open: extend its time and refresh lastAt.
                val delta = now - activeSince
                if (delta in 1..ACTIVE_GAP_MS) visited[root]?.let { it.totalMs += delta }
                activeSince = now
                visited[root]?.lastAt = now
                dirty = true
                return
            }
            // Switched sites: close out the previous page's time.
            val prev = activeDomain
            if (prev != null) {
                val delta = now - activeSince
                if (delta in 1..ACTIVE_GAP_MS) visited[prev]?.let { it.totalMs += delta }
            }
            val stat = visited.getOrPut(root) { Stat(now) }
            stat.lastAt = now
            stat.count++
            activeDomain = root
            activeSince = now
            trim(visited)
            dirty = true
        }
    }

    /** Records a blocked lookup (from the DNS filter). */
    fun recordBlocked(domain: String) {
        val root = normalize(domain) ?: return
        val now = System.currentTimeMillis()
        synchronized(lock) {
            val stat = blocked.getOrPut(root) { Stat(now) }
            stat.lastAt = now
            stat.count++
            trim(blocked)
            dirty = true
        }
    }

    /** True if there's new data worth reporting since the last flush. */
    fun hasChanges(): Boolean = dirty

    /** Builds the report payload, rolling in the active page's ongoing time. */
    fun snapshot(): Pair<List<Map<String, Any>>, List<Map<String, Any>>> {
        synchronized(lock) {
            val active = activeDomain
            if (active != null) {
                val now = System.currentTimeMillis()
                val delta = now - activeSince
                if (delta in 1..ACTIVE_GAP_MS) {
                    visited[active]?.let { it.totalMs += delta }
                    activeSince = now
                }
            }
            val visitedList = visited.entries.sortedByDescending { it.value.lastAt }
                .map {
                    mapOf<String, Any>(
                        "domain" to it.key,
                        "at" to it.value.lastAt,
                        "seconds" to (it.value.totalMs / 1000L),
                        "visits" to it.value.count,
                    )
                }
            val blockedList = blocked.entries.sortedByDescending { it.value.lastAt }
                .map {
                    mapOf<String, Any>(
                        "domain" to it.key,
                        "at" to it.value.lastAt,
                        "attempts" to it.value.count,
                    )
                }
            dirty = false
            return visitedList to blockedList
        }
    }

    private fun trim(map: LinkedHashMap<String, Stat>) {
        while (map.size > MAX) map.remove(map.keys.iterator().next())
    }

    /** Extracts a clean registrable host from a raw address-bar / domain string. */
    private fun normalize(raw: String): String? {
        var s = raw.trim().lowercase()
        if (s.isEmpty()) return null
        // A search query (has spaces) or a placeholder is not a URL.
        if (s.contains(' ')) return null
        s = s.removePrefix("https://").removePrefix("http://")
        s = s.substringBefore('/')
        s = s.substringBefore('?').substringBefore('#')
        s = s.substringBefore(':') // strip any port
        s = s.removePrefix("www.")
        if (s.isEmpty() || !s.contains('.') || s.endsWith(".arpa")) return null
        // Reject obviously non-host strings (e.g. leftover query text).
        if (s.any { it != '.' && it != '-' && !it.isLetterOrDigit() }) return null
        return rootDomain(s)
    }

    /** Collapses `m.youtube.com` / `i.ytimg.com` to `youtube.com` / `ytimg.com`. */
    private fun rootDomain(host: String): String {
        val parts = host.split('.').filter { it.isNotEmpty() }
        if (parts.size <= 2) return host
        val lastTwo = "${parts[parts.size - 2]}.${parts[parts.size - 1]}"
        val take = if (lastTwo in TWO_LEVEL_TLDS) 3 else 2
        return parts.takeLast(take).joinToString(".")
    }

    private val TWO_LEVEL_TLDS: Set<String> = setOf(
        "co.uk", "org.uk", "ac.uk", "gov.uk", "co.in", "net.in", "org.in",
        "ac.in", "gov.in", "co.jp", "com.au", "net.au", "org.au", "com.br",
        "com.cn", "com.mx", "co.nz", "co.za", "com.sg", "com.hk", "co.kr",
        "com.tr", "com.tw", "com.ua", "co.id", "com.ph", "com.my", "com.pk",
    )
}

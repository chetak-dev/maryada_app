package com.guardnest.kid

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

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

    data class Snapshot(
        val visited: List<Map<String, Any>>,
        val blocked: List<Map<String, Any>>,
        val searches: List<Map<String, Any>>,
    )

    internal data class ParsedSearch(val query: String, val engine: String)

    private data class Search(val query: String, val engine: String, val at: Long)

    private class Stat(var lastAt: Long) {
        var totalMs: Long = 0L
        var count: Int = 0
        /** Why the domain was blocked; blank for visited sites. */
        var reason: String = ""
    }

    private const val MAX = 200
    private const val MAX_SEARCHES = 300
    private const val ACTIVE_GAP_MS = 5 * 60 * 1000L
    private const val SEARCH_DEDUPE_MS = 30_000L
    private const val RETAIN_MS = 31L * 24 * 60 * 60 * 1000 // ~1 month
    private const val FILE = "web_history.json"
    private const val SCHEMA_VERSION = 2

    private val lock = Any()
    private val visited = LinkedHashMap<String, Stat>()
    private val blocked = LinkedHashMap<String, Stat>()
    private val searches = ArrayDeque<Search>()

    // Time-on-site tracking for the currently open page.
    private var activeDomain: String? = null
    private var activeSince = 0L
    private var activeSearchKey = ""
    private var lastSearchKey = ""
    private var lastSearchAt = 0L
    private var appCtx: Context? = null

    /** Loads persisted history once, so retained data survives restarts. */
    fun init(ctx: Context) {
        synchronized(lock) {
            if (appCtx != null) return
            appCtx = ctx.applicationContext
            load()
        }
    }
    @Volatile private var dirty = false

    /** Records an actual page visit (from the browser address bar). */
    fun recordVisit(host: String) = recordVisitAt(host, System.currentTimeMillis())

    internal fun recordVisitAt(host: String, now: Long) {
        val root = normalize(host) ?: return
        synchronized(lock) {
            if (root == activeDomain) {
                addActiveTime(now)
                return
            }
            finishActive(now)
            val stat = visited.getOrPut(root) { Stat(now) }
            stat.lastAt = now
            stat.count++
            activeDomain = root
            activeSince = now
            trim(visited, now)
            dirty = true
        }
    }

    /** Records a submitted search-results URL, never omnibox typing/suggestions. */
    fun recordSearch(address: String) = recordSearchAt(address, System.currentTimeMillis())

    internal fun recordSearchAt(address: String, now: Long) {
        val parsed = parseSearch(address)
        if (parsed == null) {
            synchronized(lock) { activeSearchKey = "" }
            return
        }
        recordParsedSearch(parsed.query, parsed.engine, now)
    }

    /** Records an already-extracted query (e.g. from the YouTube app's search box). */
    fun recordSearchQuery(query: String, engine: String) =
        recordSearchQueryAt(query, engine, System.currentTimeMillis())

    internal fun recordSearchQueryAt(query: String, engine: String, now: Long) {
        val q = query.trim()
        if (q.length < 2 || q.length > 300) return
        recordParsedSearch(q, engine, now)
    }

    private fun recordParsedSearch(query: String, engine: String, now: Long) {
        val key = "${engine.lowercase()}\u0000${query.lowercase()}"
        synchronized(lock) {
            if (key == activeSearchKey) return
            activeSearchKey = key
            if (key == lastSearchKey && now - lastSearchAt < SEARCH_DEDUPE_MS) return
            searches.addLast(Search(query, engine, now))
            while (searches.size > MAX_SEARCHES) searches.removeFirst()
            lastSearchKey = key
            lastSearchAt = now
            dirty = true
        }
    }

    /** Stops timing when the browser leaves the foreground or the screen turns off. */
    fun endVisit() = endVisitAt(System.currentTimeMillis())

    internal fun endVisitAt(now: Long) = synchronized(lock) { finishActive(now) }

    private fun addActiveTime(now: Long) {
        val domain = activeDomain ?: return
        val delta = now - activeSince
        activeSince = now
        if (delta !in 1..ACTIVE_GAP_MS) return
        visited[domain]?.let {
            it.totalMs += delta
            it.lastAt = now
            dirty = true
        }
    }

    private fun finishActive(now: Long) {
        if (activeDomain != null) addActiveTime(now)
        activeDomain = null
        activeSince = 0L
        trim(visited, now)
    }

    /** Records a blocked lookup, tagged with why it was blocked. */
    @JvmOverloads
    fun recordBlocked(domain: String, reason: String = "") {
        val root = normalize(domain) ?: return
        val now = System.currentTimeMillis()
        synchronized(lock) {
            val stat = blocked.getOrPut(root) { Stat(now) }
            stat.lastAt = now
            stat.count++
            if (reason.isNotEmpty()) stat.reason = reason
            trim(blocked)
            dirty = true
        }
    }

    /** True if there's new data worth reporting since the last flush. */
    fun hasChanges(): Boolean = dirty

    /** Builds the report payload, rolling in the active page's ongoing time. */
    fun snapshot(): Snapshot =
        snapshotAt(System.currentTimeMillis())

    internal fun snapshotAt(now: Long): Snapshot {
        synchronized(lock) {
            val active = activeDomain
            if (active != null) {
                if (ForegroundApp.isBrowserForeground()) addActiveTime(now)
                else finishActive(now)
            }
            trim(visited, now)
            trim(blocked, now)
            val visitedList = visited.entries.sortedByDescending { it.value.lastAt }
                .map {
                    mapOf<String, Any>(
                        "domain" to it.key,
                        "at" to it.value.lastAt,
                        "milliseconds" to it.value.totalMs,
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
                        "reason" to it.value.reason,
                    )
                }
            val searchList = searches.asReversed().map {
                mapOf<String, Any>(
                    "query" to it.query,
                    "engine" to it.engine,
                    "at" to it.at,
                )
            }
            dirty = false
            save()
            return Snapshot(visitedList, blockedList, searchList)
        }
    }

    private fun trim(map: LinkedHashMap<String, Stat>, now: Long = System.currentTimeMillis()) {
        val cutoff = now - RETAIN_MS
        val it = map.entries.iterator()
        while (it.hasNext()) {
            if (it.next().value.lastAt < cutoff) it.remove()
        }
        if (map.size > MAX) {
            val oldestFirst = map.entries.sortedBy { it.value.lastAt }
            val toRemove = map.size - MAX
            for (i in 0 until toRemove) map.remove(oldestFirst[i].key)
        }
    }

    internal fun resetForTest() = synchronized(lock) {
        visited.clear()
        blocked.clear()
        searches.clear()
        activeDomain = null
        activeSince = 0L
        activeSearchKey = ""
        lastSearchKey = ""
        lastSearchAt = 0L
        dirty = false
    }

    /** Empties the store after a server-side wipe, so the next flush doesn't
     *  resurrect the deleted history from this device's local copy. */
    fun clearAll() = synchronized(lock) {
        visited.clear()
        blocked.clear()
        searches.clear()
        activeDomain = null
        activeSince = 0L
        activeSearchKey = ""
        lastSearchKey = ""
        lastSearchAt = 0L
        dirty = false
        save()
    }

    // ---- Persistence ------------------------------------------------------

    private fun save() {
        val ctx = appCtx ?: return
        try {
            fun arrayOf(map: LinkedHashMap<String, Stat>): JSONArray {
                val arr = JSONArray()
                for ((domain, s) in map) {
                    arr.put(
                        JSONObject()
                            .put("domain", domain)
                            .put("at", s.lastAt)
                            .put("totalMs", s.totalMs)
                            .put("count", s.count)
                            .put("reason", s.reason)
                    )
                }
                return arr
            }
            val root = JSONObject()
                .put("version", SCHEMA_VERSION)
                .put("visited", arrayOf(visited))
                .put("blocked", arrayOf(blocked))
                .put("searches", JSONArray().apply {
                    for (search in searches) {
                        put(JSONObject()
                            .put("query", search.query)
                            .put("engine", search.engine)
                            .put("at", search.at))
                    }
                })
            ctx.openFileOutput(FILE, Context.MODE_PRIVATE).use {
                it.write(root.toString().toByteArray())
            }
        } catch (_: Exception) {
        }
    }

    private fun load() {
        val ctx = appCtx ?: return
        try {
            if (!ctx.getFileStreamPath(FILE).exists()) return
            val text = ctx.openFileInput(FILE).bufferedReader().use { it.readText() }
            val root = JSONObject(text)
            val cutoff = System.currentTimeMillis() - RETAIN_MS
            fun fill(map: LinkedHashMap<String, Stat>, arr: JSONArray?) {
                if (arr == null) return
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val at = o.optLong("at")
                    if (at < cutoff) continue
                    val domain = o.optString("domain")
                    if (domain.isEmpty()) continue
                    val s = Stat(at)
                    s.totalMs = o.optLong("totalMs")
                    s.count = o.optInt("count")
                    s.reason = o.optString("reason")
                    map[domain] = s
                }
            }
            fill(visited, root.optJSONArray("visited"))
            fill(blocked, root.optJSONArray("blocked"))
            root.optJSONArray("searches")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val query = o.optString("query").trim()
                    val engine = o.optString("engine").trim()
                    val at = o.optLong("at")
                    if (query.isNotEmpty() && engine.isNotEmpty() && at >= cutoff) {
                        searches.addLast(Search(query, engine, at))
                    }
                }
            }
        } catch (_: Exception) {
        }
    }

    /** Parses only known search-result URLs with a submitted query parameter. */
    internal fun parseSearch(raw: String): ParsedSearch? {
        val text = raw.trim()
        if (text.isEmpty() || text.contains(' ') || !text.contains('.')) return null
        val uri = try {
            URI(if (text.contains("://")) text else "https://$text")
        } catch (_: Exception) {
            return null
        }
        val host = uri.host?.lowercase()?.removePrefix("www.") ?: return null
        val path = uri.path.orEmpty().lowercase()
        val params = uri.rawQuery.orEmpty().split('&')
            .mapNotNull { part ->
                if (part.isEmpty()) return@mapNotNull null
                val pieces = part.split('=', limit = 2)
                val key = decode(pieces[0]).lowercase()
                val value = decode(pieces.getOrElse(1) { "" }).trim()
                key to value
            }
            .toMap()

        val match: Pair<String, String?> = when {
            (host == "google.com" || host.startsWith("google.") || host.contains(".google.")) &&
                path.startsWith("/search") -> "Google" to params["q"]
            (host == "bing.com" || host.endsWith(".bing.com")) && path.startsWith("/search") ->
                "Bing" to params["q"]
            host == "duckduckgo.com" -> "DuckDuckGo" to params["q"]
            host == "search.yahoo.com" -> "Yahoo" to params["p"]
            host == "ecosia.org" && path.startsWith("/search") -> "Ecosia" to params["q"]
            host == "startpage.com" && path.contains("search") ->
                "Startpage" to (params["query"] ?: params["q"])
            host == "qwant.com" -> "Qwant" to params["q"]
            host == "search.brave.com" -> "Brave" to params["q"]
            host.endsWith("baidu.com") -> "Baidu" to params["wd"]
            host.endsWith("ask.com") -> "Ask" to params["q"]
            (host.startsWith("yandex.") || host.contains(".yandex.")) ->
                "Yandex" to params["text"]
            (host == "youtube.com" || host.endsWith(".youtube.com")) && path == "/results" ->
                "YouTube" to params["search_query"]
            else -> return null
        }
        val query = match.second?.replace(Regex("\\s+"), " ")?.trim().orEmpty()
        if (query.length < 2) return null
        return ParsedSearch(query.take(300), match.first)
    }

    private fun decode(value: String): String = try {
        URLDecoder.decode(value, StandardCharsets.UTF_8.name())
    } catch (_: Exception) {
        value
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
        // Strip only a couple of common "noise" subdomains, keeping the real
        // host so e.g. maryada.web.app stays intact (was collapsing to web.app).
        for (p in listOf("m.", "mobile.", "amp.")) {
            if (s.startsWith(p)) {
                s = s.substring(p.length)
                break
            }
        }
        if (s.isEmpty() || !s.contains('.') || s.endsWith(".arpa")) return null
        // Reject obviously non-host strings (e.g. leftover query text).
        if (s.any { it != '.' && it != '-' && !it.isLetterOrDigit() }) return null
        return s
    }
}

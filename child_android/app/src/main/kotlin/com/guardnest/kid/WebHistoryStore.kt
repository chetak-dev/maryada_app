package com.guardnest.kid

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

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

    private const val MAX = 200
    private const val ACTIVE_GAP_MS = 5 * 60 * 1000L
    private const val RETAIN_MS = 31L * 24 * 60 * 60 * 1000 // ~1 month
    private const val FILE = "web_history.json"

    private val lock = Any()
    private val visited = LinkedHashMap<String, Stat>()
    private val blocked = LinkedHashMap<String, Stat>()

    // Time-on-site tracking for the currently open page.
    private var activeDomain: String? = null
    private var activeSince = 0L
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
            trim(visited)
            trim(blocked)
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
            save()
            return visitedList to blockedList
        }
    }

    private fun trim(map: LinkedHashMap<String, Stat>) {
        val cutoff = System.currentTimeMillis() - RETAIN_MS
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
                    )
                }
                return arr
            }
            val root = JSONObject()
                .put("visited", arrayOf(visited))
                .put("blocked", arrayOf(blocked))
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
                    map[domain] = s
                }
            }
            fill(visited, root.optJSONArray("visited"))
            fill(blocked, root.optJSONArray("blocked"))
        } catch (_: Exception) {
        }
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

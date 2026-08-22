package com.guardnest.kid

import android.content.Context
import android.util.Log
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

/**
 * Runtime domain categorisation for the web filter.
 *
 * Real products decide a site's category from a maintained reputation feed —
 * you can't tell a domain's category by inspecting encrypted HTTPS traffic. So
 * this downloads community-maintained per-category domain blocklists, caches
 * them on disk, and holds them in memory. At DNS time [isBlocked] decides a
 * lookup's category live and blocks it if the parent enabled that category.
 *
 * Domain-based (not page-content) classification — the only approach that works
 * at the DNS layer without breaking HTTPS.
 */
object CategoryFeed {

    private const val TAG = "GuardNestCategoryFeed"
    private const val MAX_AGE_MS = 24L * 60 * 60 * 1000 // refresh daily

    // Hard cap on domains kept per category, to bound memory. Some community
    // lists (phishing/malware) have hundreds of thousands of entries which
    // would otherwise exhaust the app heap (OutOfMemoryError).
    private const val MAX_DOMAINS = 40000

    // Our category ids -> community blocklist (hosts-format) URLs. A category
    // may combine several lists.
    private const val BASE =
        "https://raw.githubusercontent.com/blocklistproject/Lists/master"
    private val FEED_URLS: Map<String, List<String>> = mapOf(
        "adult" to listOf("$BASE/porn.txt"),
        "gambling" to listOf("$BASE/gambling.txt"),
        "drugs" to listOf("$BASE/drugs.txt"),
        "social" to listOf(
            "$BASE/facebook.txt",
            "$BASE/tiktok.txt",
            "$BASE/twitter.txt",
        ),
        "malware" to listOf("$BASE/malware.txt"),
        "phishing" to listOf("$BASE/phishing.txt"),
    )

    // Categories sourced from the UT1 (Toulouse) blacklists, distributed as
    // .tar.gz archives that contain a plain "domains" file.
    private const val UT1 = "https://dsi.ut-capitole.fr/blacklists/download"
    private val ARCHIVE_URLS: Map<String, String> = mapOf(
        "weapons" to "$UT1/dangerous_material.tar.gz",
        "violence" to "$UT1/agressif.tar.gz",
    )

    private val allCategories: Set<String> get() = FEED_URLS.keys + ARCHIVE_URLS.keys

    @Volatile private var sets: Map<String, Set<String>> = emptyMap()
    @Volatile private var refreshing = false

    /** Loads any cached lists from disk into memory (call on filter start). */
    fun loadCache(ctx: Context) {
        val loaded = HashMap<String, Set<String>>()
        for (cat in allCategories) {
            val f = cacheFile(ctx, cat)
            if (f.exists()) {
                runCatching { parse(f.readText()) }
                    .getOrNull()
                    ?.let { if (it.isNotEmpty()) loaded[cat] = it }
            }
        }
        if (loaded.isNotEmpty()) sets = loaded
    }

    /**
     * Ensures the enabled categories' lists are present and fresh, downloading
     * in the background. Safe to call often; it no-ops when already refreshing.
     */
    fun ensure(ctx: Context, enabled: Set<String>) {
        val wanted = enabled.filter { allCategories.contains(it) }
        if (wanted.isEmpty() || refreshing) return
        refreshing = true
        Thread {
            try {
                val current = HashMap(sets)
                for (cat in wanted) {
                    val f = cacheFile(ctx, cat)
                    val fresh = f.exists() &&
                        System.currentTimeMillis() - f.lastModified() < MAX_AGE_MS
                    if (fresh && current.containsKey(cat)) continue
                    // Parse straight into a bounded set (never hold the whole
                    // multi-MB text of several lists at once).
                    val set = HashSet<String>()
                    if (FEED_URLS.containsKey(cat)) {
                        for (url in FEED_URLS[cat]!!) {
                            if (set.size >= MAX_DOMAINS) break
                            download(url)?.let { parseInto(it, set) }
                        }
                    } else {
                        val bytes = downloadBytes(ARCHIVE_URLS[cat] ?: continue)
                        if (bytes != null) parseInto(extractTarGzDomains(bytes), set)
                    }
                    if (set.isNotEmpty()) {
                        // Cache the deduped, bounded list (not the raw file), so
                        // reloads on start stay small and fast.
                        runCatching { f.writeText(set.joinToString("\n")) }
                        current[cat] = set
                        sets = HashMap(current) // publish incrementally
                        Log.i(TAG, "category '$cat' loaded: ${set.size} domains")
                    } else if (!current.containsKey(cat)) {
                        // Nothing downloaded and nothing cached: this category is
                        // effectively NOT being enforced. Surface it rather than
                        // leaving the parent to believe it's blocked.
                        Diag.warn(
                            ctx, "categoryFeed:$cat",
                            detail = "no domains available — category not enforced",
                        )
                    }
                }
            } catch (e: Exception) {
                Diag.warn(ctx, "categoryFeed", e)
            } finally {
                refreshing = false
            }
        }.apply { isDaemon = true }.start()
    }

    /**
     * True if [host] (already lowercased, no www.) falls in any [enabled]
     * category's domain list — matching the host or any of its parent domains.
     */
    fun isBlocked(host: String, enabled: Set<String>): Boolean =
        categoryOf(host, enabled) != null

    /** The first [enabled] category [host] falls in, or null if none match. */
    fun categoryOf(host: String, enabled: Set<String>): String? {
        if (enabled.isEmpty()) return null
        val s = sets
        for (cat in enabled) {
            val set = s[cat] ?: continue
            if (suffixMatch(host, set)) return cat
        }
        return null
    }

    /** Like [categoryOf] but across every downloaded list — used only to tag a
     *  block that already happened, never to decide blocking. */
    fun categoryOfAny(host: String): String? {
        for ((cat, set) in sets) {
            if (suffixMatch(host, set)) return cat
        }
        return null
    }

    private fun suffixMatch(host: String, set: Set<String>): Boolean {
        var h = host
        while (true) {
            if (set.contains(h)) return true
            val dot = h.indexOf('.')
            if (dot < 0) return false
            h = h.substring(dot + 1)
        }
    }

    private fun cacheFile(ctx: Context, cat: String) =
        File(ctx.filesDir, "catfeed2_$cat.txt")

    private fun download(url: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 20000
                requestMethod = "GET"
            }
            if (conn.responseCode != 200) return null
            conn.inputStream.bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            Log.w(TAG, "download failed: $url", e)
            null
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    private fun downloadBytes(url: String): ByteArray? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 30000
                requestMethod = "GET"
                instanceFollowRedirects = true
            }
            if (conn.responseCode != 200) return null
            conn.inputStream.use { it.readBytes() }
        } catch (e: Exception) {
            Log.w(TAG, "download failed: $url", e)
            null
        } finally {
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Gunzips a .tar.gz and concatenates every "domains" file it contains (UT1
     * blacklists store one domain per line in a file named `.../domains`).
     */
    private fun extractTarGzDomains(gz: ByteArray): String {
        val out = StringBuilder()
        try {
            GZIPInputStream(ByteArrayInputStream(gz)).use { input ->
                val header = ByteArray(512)
                while (true) {
                    if (!readFully(input, header, 512)) break
                    if (header.all { it.toInt() == 0 }) break // end of archive
                    val name = tarString(header, 0, 100)
                    val size = tarSize(header)
                    val padded = ((size + 511) / 512) * 512
                    if (name.endsWith("/domains") || name == "domains") {
                        val data = ByteArray(size)
                        if (!readFully(input, data, size)) break
                        out.append(String(data, Charsets.UTF_8)).append('\n')
                        val pad = padded - size
                        if (pad > 0) skipFully(input, pad)
                    } else if (padded > 0) {
                        skipFully(input, padded)
                    }
                }
            }
        } catch (_: Exception) {
        }
        return out.toString()
    }

    private fun readFully(input: InputStream, buf: ByteArray, len: Int): Boolean {
        var off = 0
        while (off < len) {
            val r = input.read(buf, off, len - off)
            if (r < 0) return false
            off += r
        }
        return true
    }

    private fun skipFully(input: InputStream, count: Int) {
        var remaining = count.toLong()
        val tmp = ByteArray(4096)
        while (remaining > 0) {
            val r = input.read(tmp, 0, minOf(tmp.size.toLong(), remaining).toInt())
            if (r < 0) break
            remaining -= r
        }
    }

    private fun tarString(header: ByteArray, offset: Int, max: Int): String {
        var end = offset
        while (end < offset + max && header[end].toInt() != 0) end++
        return String(header, offset, end - offset, Charsets.UTF_8)
    }

    /** TAR header stores the size as an octal string at bytes 124..135. */
    private fun tarSize(header: ByteArray): Int {
        val s = tarString(header, 124, 12).trim()
        return if (s.isEmpty()) 0 else s.toIntOrNull(8) ?: 0
    }

    /** Parses a hosts-format or plain domain list into a set of base domains. */
    private fun parse(text: String): Set<String> {
        val out = HashSet<String>()
        parseInto(text, out)
        return out
    }

    /**
     * Appends domains from [text] into [out], line by line, capped at
     * [MAX_DOMAINS]. Allocation-light (no per-line regex) so huge lists don't
     * exhaust the heap.
     */
    private fun parseInto(text: String, out: MutableSet<String>) {
        for (raw in text.lineSequence()) {
            if (out.size >= MAX_DOMAINS) return
            var line = raw.trim()
            if (line.isEmpty() || line[0] == '#') continue
            // Hosts format "0.0.0.0 domain.com": take the last token (no regex).
            val ws = line.lastIndexOfAny(charArrayOf(' ', '\t'))
            if (ws >= 0) line = line.substring(ws + 1)
            val hash = line.indexOf('#')
            if (hash >= 0) line = line.substring(0, hash)
            line = line.trim().lowercase()
            if (line.startsWith("www.")) line = line.substring(4)
            if (line.isEmpty() || !line.contains('.') ||
                line == "localhost" || line == "0.0.0.0"
            ) continue
            out.add(line)
        }
    }
}

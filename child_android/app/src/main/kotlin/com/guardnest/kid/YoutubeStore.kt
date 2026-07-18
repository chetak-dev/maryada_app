package com.guardnest.kid

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Buffers YouTube videos the child watches, captured from the on-screen video
 * title by [GuardNestAccessibilityService]. YouTube's own watch history lives in
 * the account/app sandbox and isn't readable, so this records what's actually
 * shown while a video plays — including the accumulated watch time per video.
 */
object YoutubeStore {

    data class Video(
        val title: String,
        var channel: String,
        var at: Long,
        var watchedMs: Long,
    )

    private const val MAX = 400
    private const val RETAIN_MS = 31L * 24 * 60 * 60 * 1000 // ~1 month
    private const val FILE = "youtube_history.json"

    private val lock = Any()
    // Keyed by lowercased title so repeat views of the same video accumulate
    // watch time instead of creating duplicates.
    private val videos = LinkedHashMap<String, Video>()

    @Volatile private var dirty = false
    private var appCtx: Context? = null

    /** Loads persisted history once, so retained data survives restarts. */
    fun init(ctx: Context) {
        synchronized(lock) {
            if (appCtx != null) return
            appCtx = ctx.applicationContext
            load()
        }
    }

    /**
     * Records that [title] is on screen. [addMs] is the watch time to add since
     * the previous capture of the same video (0 when a new video just started).
     */
    fun record(title: String, channel: String, addMs: Long = 0L) {
        val t = title.trim()
        if (t.length < 2) return
        val key = normalizeKey(t)
        val now = System.currentTimeMillis()
        synchronized(lock) {
            val existing = videos[key]
            if (existing == null) {
                videos[key] = Video(t, channel.trim(), now, addMs.coerceAtLeast(0L))
            } else {
                if (channel.isNotBlank()) existing.channel = channel.trim()
                existing.at = now
                if (addMs > 0L) existing.watchedMs += addMs
            }
            pruneLocked(now)
            dirty = true
        }
    }

    /** Collapses whitespace and trailing "…more"/ellipsis so the same video —
     *  captured collapsed or expanded — maps to a single key. */
    private fun normalizeKey(title: String): String {
        return title
            .lowercase()
            .replace(Regex("\\s+"), " ")
            .removeSuffix("…more")
            .removeSuffix("...more")
            .trimEnd('.', '…', ' ')
            .trim()
    }

    /** Drops entries older than the retention window, then caps the total. */
    private fun pruneLocked(now: Long) {
        val cutoff = now - RETAIN_MS
        val it = videos.entries.iterator()
        while (it.hasNext()) {
            if (it.next().value.at < cutoff) it.remove()
        }
        if (videos.size > MAX) {
            val oldestFirst = videos.entries.sortedBy { it.value.at }
            val toRemove = videos.size - MAX
            for (i in 0 until toRemove) videos.remove(oldestFirst[i].key)
        }
    }

    fun hasChanges(): Boolean = dirty

    fun snapshot(): List<Map<String, Any>> {
        synchronized(lock) {
            pruneLocked(System.currentTimeMillis())
            dirty = false
            save()
            return videos.values.sortedByDescending { it.at }.map {
                mapOf(
                    "title" to it.title,
                    "channel" to it.channel,
                    "at" to it.at,
                    "watchedMs" to it.watchedMs,
                )
            }
        }
    }

    // ---- Persistence ------------------------------------------------------

    private fun save() {
        val ctx = appCtx ?: return
        try {
            val arr = JSONArray()
            for (v in videos.values) {
                arr.put(
                    JSONObject()
                        .put("title", v.title)
                        .put("channel", v.channel)
                        .put("at", v.at)
                        .put("watchedMs", v.watchedMs)
                )
            }
            ctx.openFileOutput(FILE, Context.MODE_PRIVATE).use {
                it.write(arr.toString().toByteArray())
            }
        } catch (_: Exception) {
        }
    }

    private fun load() {
        val ctx = appCtx ?: return
        try {
            if (!ctx.getFileStreamPath(FILE).exists()) return
            val text = ctx.openFileInput(FILE).bufferedReader().use { it.readText() }
            val arr = JSONArray(text)
            val now = System.currentTimeMillis()
            val cutoff = now - RETAIN_MS
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val at = o.optLong("at")
                if (at < cutoff) continue
                val title = o.optString("title")
                if (title.length < 2) continue
                videos[normalizeKey(title)] = Video(
                    title,
                    o.optString("channel"),
                    at,
                    o.optLong("watchedMs"),
                )
            }
        } catch (_: Exception) {
        }
    }
}

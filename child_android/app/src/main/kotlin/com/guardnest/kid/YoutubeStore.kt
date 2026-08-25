package com.guardnest.kid

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Buffers YouTube videos the child watches, captured from the on-screen video
 * title by [GuardNestAccessibilityService]. YouTube's own watch history lives in
 * the account/app sandbox and isn't readable, so this records what's actually
 * shown while a video plays — including the accumulated watch time per video.
 */
object YoutubeStore {

    data class Video(
        var title: String,
        var channel: String,
        var durationMs: Long,
        var at: Long,
        var watchedMs: Long,
    )

    private const val MAX = 700
    private const val RETAIN_MS = 31L * 24 * 60 * 60 * 1000 // ~1 month
    private const val FILE = "youtube_history.json"

    /** A video only counts as "watched" after this much accumulated play time —
     *  opening one and backing straight out shouldn't put it in the history. */
    private const val MIN_WATCHED_MS = 20_000L

    private val lock = Any()
    // Keyed by day + title + channel + duration. Title alone merged different
    // videos that happened to share a name, and split one video whose title was
    // shown truncated in the feed but in full on the watch page. The day keeps
    // watch time attributed to the day it happened instead of one running total.
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
    fun record(
        title: String,
        channel: String,
        durationMs: Long = 0L,
        addMs: Long = 0L,
    ) {
        val t = title.trim()
        if (t.length < 2) return
        val ch = channel.trim()
        val now = System.currentTimeMillis()
        val key = keyOf(t, ch, durationMs, now)
        synchronized(lock) {
            val existing = videos[key]
            if (existing == null) {
                videos[key] = Video(t, ch, durationMs, now, addMs.coerceAtLeast(0L))
            } else {
                if (ch.isNotBlank()) existing.channel = ch
                if (durationMs > 0L) existing.durationMs = durationMs
                // Screens truncate titles; keep the fullest one we've seen.
                if (t.length > existing.title.length) existing.title = t
                existing.at = now
                if (addMs > 0L) existing.watchedMs += addMs
            }
            pruneLocked(now)
            dirty = true
        }
    }

    /**
     * Identity of a video on a given day. Duration separates same-titled videos,
     * and is bucketed to a second because sources report it slightly differently.
     */
    private fun keyOf(title: String, channel: String, durationMs: Long, at: Long): String {
        val bucket = if (durationMs > 0L) (durationMs / 1000).toString() else ""
        return "${dayOf(at)}|${normalizeKey(title)}|${channel.lowercase()}|$bucket"
    }

    private fun dayOf(ms: Long): Long {
        val cal = Calendar.getInstance()
        cal.timeInMillis = ms
        return cal.get(Calendar.YEAR) * 10_000L +
            (cal.get(Calendar.MONTH) + 1) * 100L +
            cal.get(Calendar.DAY_OF_MONTH)
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

    /** Empties the store after a server-side wipe, so the next flush doesn't
     *  resurrect the deleted history from this device's local copy. */
    fun clearAll() {
        synchronized(lock) {
            videos.clear()
            dirty = false
            save()
        }
    }

    fun snapshot(): List<Map<String, Any>> {
        synchronized(lock) {
            pruneLocked(System.currentTimeMillis())
            dirty = false
            save()
            // Sub-threshold entries stay buffered (their time keeps accruing);
            // they just don't ship until the child has genuinely watched.
            return videos.values
                .filter { it.watchedMs >= MIN_WATCHED_MS }
                .sortedByDescending { it.at }
                .map {
                    mapOf(
                        "title" to it.title,
                        "channel" to it.channel,
                        "durationMs" to it.durationMs,
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
                        .put("durationMs", v.durationMs)
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
                val channel = o.optString("channel")
                val durationMs = o.optLong("durationMs")
                videos[keyOf(title, channel, durationMs, at)] = Video(
                    title,
                    channel,
                    durationMs,
                    at,
                    o.optLong("watchedMs"),
                )
            }
        } catch (_: Exception) {
        }
    }
}

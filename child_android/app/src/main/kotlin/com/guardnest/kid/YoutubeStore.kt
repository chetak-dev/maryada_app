package com.guardnest.kid

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

    private const val MAX = 150
    private val lock = Any()
    // Keyed by lowercased title so repeat views of the same video accumulate
    // watch time instead of creating duplicates.
    private val videos = LinkedHashMap<String, Video>()

    @Volatile private var dirty = false

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
                while (videos.size > MAX) {
                    videos.remove(videos.keys.iterator().next())
                }
            } else {
                if (channel.isNotBlank()) existing.channel = channel.trim()
                existing.at = now
                if (addMs > 0L) existing.watchedMs += addMs
            }
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

    fun hasChanges(): Boolean = dirty

    fun snapshot(): List<Map<String, Any>> {
        synchronized(lock) {
            dirty = false
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
}

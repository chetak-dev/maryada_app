package com.guardnest.kid

/**
 * Coordinates YouTube watch-time capture between the two sources so they never
 * double-count the same playback:
 *
 *  - [GuardNestNotificationListener] (MediaSession) — the reliable source. It
 *    reads the video title/channel and playback state straight from YouTube's
 *    media session, so it keeps working full-screen, in picture-in-picture and
 *    while the video plays in the background or with the screen off.
 *  - [GuardNestAccessibilityService] — the fallback that reads the on-screen
 *    title (feed dwell, some Shorts) for the cases where no media session exists.
 *
 * While the MediaSession source is actively bound to a YouTube session, the
 * accessibility source defers to it (see [mediaActive]).
 */
object YoutubeWatch {

    /**
     * Timestamp of the most recent tick while a YouTube media session was bound.
     * Refreshed by [GuardNestNotificationListener] on every pump (playing or
     * paused) so the accessibility source knows the session is still covering it.
     */
    @Volatile
    var mediaTickAt: Long = 0L

    /**
     * True while a YouTube media session is bound at all. Only tells us the
     * source exists — not that anything is playing.
     */
    @Volatile
    var sessionBound: Boolean = false

    /**
     * When the media session was last seen actually playing. Deferral keys off
     * this rather than merely being bound: YouTube keeps a session around after
     * playback stops, and treating that as "covered" left Shorts and the feed
     * uncaptured, because the accessibility source stood down for a session that
     * was reporting nothing.
     */
    @Volatile
    var mediaPlayingAt: Long = 0L

    /** How long after the last playing tick we still treat the MediaSession
     *  source as the owner of YouTube capture — a little over its pump interval. */
    private const val FRESH_MS = 12_000L

    /**
     * True while the MediaSession source is actively covering playback, so the
     * accessibility source should skip its own capture to avoid double-counting
     * watch time or creating duplicate title entries.
     */
    fun mediaActive(now: Long = System.currentTimeMillis()): Boolean =
        mediaPlayingAt > 0L && (now - mediaPlayingAt) < FRESH_MS
}

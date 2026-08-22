package com.guardnest.kid

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.notification.NotificationListenerService

/**
 * Captures YouTube watch history (title, channel and watch-time) from the app's
 * MediaSession. Unlike the accessibility screen read, the media session stays
 * accurate in full-screen, in picture-in-picture and while the video plays in
 * the background or with the screen off — closing those capture gaps.
 *
 * We do not read notification content. A NotificationListenerService is simply
 * the only component Android allows to call
 * [MediaSessionManager.getActiveSessions], which is how we reach the media
 * controller. The child grants "Notification access" once in Settings; it is an
 * optional enhancement (not a required protection), so the app works without it
 * — it just falls back to on-screen capture via the accessibility service.
 */
class GuardNestNotificationListener : NotificationListenerService() {

    private val handler = Handler(Looper.getMainLooper())
    private var sessionManager: MediaSessionManager? = null

    // The currently-bound YouTube controller (if any) and its callback.
    private var ytController: MediaController? = null
    private var ytCallback: MediaController.Callback? = null

    // The current video, and the last time we accumulated watch time for it.
    private var title: String? = null
    private var channel: String = ""
    private var durationMs: Long = 0L
    private var lastTickAt = 0L
    // Last known playhead position. Watch time is the distance the playhead
    // moves, which excludes pauses, buffering and seeks without needing a
    // separate rule for each.
    private var lastPosition = -1L

    private val self by lazy {
        ComponentName(this, GuardNestNotificationListener::class.java)
    }

    private val sessionsChanged =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            bindYoutube(controllers)
        }

    /**
     * Accumulates watch time while a YouTube session is playing. Runs regardless
     * of screen or foreground state — that is the whole point of this source.
     */
    private val pump = object : Runnable {
        override fun run() {
            try {
                tick()
            } catch (_: Throwable) {
            } finally {
                handler.postDelayed(this, PUMP_MS)
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        YoutubeStore.init(this)
        val mgr = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        sessionManager = mgr
        try {
            mgr?.addOnActiveSessionsChangedListener(sessionsChanged, self)
            bindYoutube(mgr?.getActiveSessions(self))
        } catch (_: Exception) {
            // Not actually an enabled listener yet, or the OEM restricts it.
        }
        handler.removeCallbacks(pump)
        handler.postDelayed(pump, PUMP_MS)
    }

    override fun onListenerDisconnected() {
        handler.removeCallbacks(pump)
        try {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsChanged)
        } catch (_: Exception) {
        }
        detach()
        if (instance === this) instance = null
        super.onListenerDisconnected()
    }

    /** Binds to YouTube's media controller, dropping any stale one. */
    private fun bindYoutube(controllers: List<MediaController>?) {
        val yt = controllers?.firstOrNull { Pkgs.isYoutube(it.packageName) }
        if (yt == null) {
            detach()
            return
        }
        if (ytController?.sessionToken == yt.sessionToken) return // already bound
        detach()
        ytController = yt
        YoutubeWatch.sessionBound = true
        val cb = object : MediaController.Callback() {
            override fun onMetadataChanged(metadata: MediaMetadata?) {
                readMetadata(metadata)
            }

            // Play/pause/seek arrive here immediately, so watch time follows the
            // real playback instead of waiting for the next pump.
            override fun onPlaybackStateChanged(state: PlaybackState?) {
                accumulate(state, System.currentTimeMillis())
            }

            override fun onSessionDestroyed() {
                detach()
            }
        }
        ytCallback = cb
        try {
            yt.registerCallback(cb, handler)
        } catch (_: Exception) {
        }
        readMetadata(yt.metadata)
    }

    /** Reads title + channel from the session, logging a new video on change. */
    private fun readMetadata(metadata: MediaMetadata?) {
        val md = metadata ?: return
        val t = (md.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: md.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE))
            ?.trim().orEmpty()
        if (t.length < 2) return
        val ch = (md.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: md.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: md.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE))
            ?.trim().orEmpty()
        val dur = md.getLong(MediaMetadata.METADATA_KEY_DURATION).coerceAtLeast(0L)
        if (t != title) {
            // A new video started — log it now with no added time, then start
            // accumulating watch time from this moment.
            title = t
            channel = ch
            durationMs = dur
            lastTickAt = System.currentTimeMillis()
            lastPosition = -1L
            YoutubeStore.record(t, ch, dur, 0L)
        } else {
            if (ch.isNotEmpty() && ch != channel) channel = ch
            if (dur > 0L && dur != durationMs) durationMs = dur
        }
        YoutubeWatch.mediaTickAt = System.currentTimeMillis()
    }

    /** Adds elapsed time to the current video while it is actually playing. */
    private fun tick() {
        val c = ytController ?: return // not bound — let accessibility cover it
        // Signal that the MediaSession source is covering YouTube (even while
        // paused), so the accessibility source keeps deferring to us.
        YoutubeWatch.mediaTickAt = System.currentTimeMillis()
        accumulate(c.playbackState, System.currentTimeMillis())
    }

    /**
     * Credits watch time up to [now]. Prefers the distance the playhead moved;
     * falls back to elapsed wall-clock only when the session doesn't report a
     * usable position.
     */
    private fun accumulate(state: PlaybackState?, now: Long) {
        val t = title ?: return
        if (state?.state != PlaybackState.STATE_PLAYING) {
            // Not playing: reset the baselines so the paused span is never
            // credited once playback resumes.
            lastTickAt = now
            lastPosition = -1L
            return
        }
        // Claim ownership only while really playing, so an idle session doesn't
        // stop the accessibility source covering Shorts and the feed.
        YoutubeWatch.mediaPlayingAt = now
        val elapsed = if (lastTickAt > 0L) now - lastTickAt else 0L
        lastTickAt = now
        val position = positionOf(state)
        val add: Long
        if (lastPosition >= 0L && position >= 0L) {
            val moved = position - lastPosition
            // A backward or implausibly large jump is a seek, not watching.
            val plausible = elapsed * 3 + 5_000L
            add = if (moved in 1..plausible) moved else 0L
        } else {
            // No usable playhead. A gap longer than the pump means the pump was
            // stalled and we simply don't know what happened — clamping it to a
            // cap (as this used to) invented watch time that never occurred.
            add = if (elapsed in 1..MAX_GAP_MS) elapsed else 0L
        }
        if (position >= 0L) lastPosition = position
        if (add > 0L) YoutubeStore.record(t, channel, durationMs, add)
    }

    /** The playhead now, extrapolated from the last reported update. */
    private fun positionOf(state: PlaybackState): Long {
        val base = state.position
        if (base < 0L) return -1L
        val updatedAt = state.lastPositionUpdateTime
        if (updatedAt <= 0L) return base
        val since = SystemClock.elapsedRealtime() - updatedAt
        if (since < 0L) return base
        val speed = if (state.playbackSpeed > 0f) state.playbackSpeed else 1f
        return base + (since * speed).toLong()
    }

    private fun detach() {
        val c = ytController
        val cb = ytCallback
        if (c != null && cb != null) {
            try {
                c.unregisterCallback(cb)
            } catch (_: Exception) {
            }
        }
        ytController = null
        ytCallback = null
        title = null
        channel = ""
        durationMs = 0L
        lastTickAt = 0L
        lastPosition = -1L
        YoutubeWatch.sessionBound = false
    }

    companion object {
        /** The running instance, so Temporary Access can unbind it immediately. */
        @Volatile
        private var instance: GuardNestNotificationListener? = null

        /** Stops the listener now (Temporary Access). The component is also
         *  disabled by DeviceLockdown, so it won't rebind until re-enabled. */
        fun stop() {
            try {
                instance?.requestUnbind()
            } catch (_: Throwable) {
            }
        }

        /** How often watch time is accumulated while a video plays. */
        const val PUMP_MS = 5_000L

        /** Cap a single tick's added time so a stalled pump can't over-count. */
        const val MAX_GAP_MS = 15_000L
    }
}

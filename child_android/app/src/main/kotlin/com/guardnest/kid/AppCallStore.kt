package com.guardnest.kid

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Buffers WhatsApp voice and video calls.
 *
 * WhatsApp calls never reach the system call log — they live inside the app's
 * own encrypted database — so the only evidence available to us is the ongoing
 * call notification WhatsApp posts while a call is ringing or connected.
 * [GuardNestNotificationListener] feeds this store; [EnforcementService] flushes
 * it to the parent.
 */
object AppCallStore {

    /** One captured call. [seconds] is 0 for a call that never connected. */
    data class Call(
        val app: String,
        val contact: String,
        var video: Boolean,
        var incoming: Boolean,
        var missed: Boolean,
        val at: Long,
        var seconds: Long,
        /** Last notification update for this call, for grouping the updates. */
        var lastAt: Long,
        /** When it was answered; 0 while it is still ringing or was never taken. */
        var connectedAt: Long,
        /** Set once a notification actually said which way the call went. */
        var directionKnown: Boolean,
    )

    private const val MAX = 300
    private const val RETAIN_MS = 31L * 24 * 60 * 60 * 1000 // ~1 month
    private const val FILE = "app_calls.json"

    /**
     * How long after the last notification update a new sighting still belongs
     * to the same call. WhatsApp posts a ringing notification and then replaces
     * it with an ongoing-call one whose timestamp is the moment it was answered,
     * so keying on the timestamp filed one call as two.
     */
    private const val SESSION_GAP_MS = 2 * 60 * 1000L

    private val lock = Any()
    private val calls = LinkedHashMap<String, Call>()

    @Volatile private var dirty = false
    private var appCtx: Context? = null

    fun init(ctx: Context) {
        synchronized(lock) {
            if (appCtx != null) return
            appCtx = ctx.applicationContext
            load()
        }
    }

    private fun keyOf(app: String, contact: String, at: Long) =
        "$app\u0000${contact.lowercase()}\u0000$at"

    /** The call with this contact that is still in progress, if any. */
    private fun liveCall(app: String, contact: String, now: Long): Call? =
        calls.values.lastOrNull {
            it.app == app &&
                it.contact.equals(contact, ignoreCase = true) &&
                now - it.lastAt <= SESSION_GAP_MS
        }

    /**
     * Records a sighting of a call. Every update WhatsApp posts for the same
     * call folds into one record rather than adding a row.
     */
    fun record(
        app: String,
        contact: String,
        video: Boolean,
        incoming: Boolean,
        missed: Boolean,
        startedAt: Long,
        seconds: Long = 0L,
        connected: Boolean = false,
        directionKnown: Boolean = true,
    ) {
        val name = contact.trim()
        if (name.isEmpty()) return
        val now = System.currentTimeMillis()
        synchronized(lock) {
            val existing = liveCall(app, name, now)
            if (existing == null) {
                calls[keyOf(app, name, startedAt)] = Call(
                    app = app,
                    contact = name,
                    video = video,
                    incoming = incoming,
                    missed = missed,
                    at = startedAt,
                    seconds = seconds,
                    lastAt = now,
                    connectedAt = if (connected) startedAt else 0L,
                    directionKnown = directionKnown,
                )
            } else {
                existing.lastAt = now
                // Video is only ever revealed by one of the updates.
                if (video) existing.video = true
                // The ringing notification is the one that names the direction;
                // the ongoing one usually does not, so it must not overwrite it.
                if (directionKnown && !existing.directionKnown) {
                    existing.incoming = incoming
                    existing.directionKnown = true
                }
                if (missed) existing.missed = true
                if (connected && existing.connectedAt == 0L) {
                    existing.connectedAt = startedAt
                    existing.missed = false
                }
                if (seconds > existing.seconds) existing.seconds = seconds
            }
            prune(now)
            dirty = true
        }
    }

    /** The call ended: turn the elapsed time into its real duration. */
    fun finish(app: String, contact: String, endedAt: Long) {
        val name = contact.trim()
        if (name.isEmpty()) return
        synchronized(lock) {
            val call = liveCall(app, name, endedAt) ?: return
            if (call.connectedAt > 0L) {
                val seconds = ((endedAt - call.connectedAt) / 1000L)
                    .coerceIn(0L, MAX_SECONDS)
                if (seconds > call.seconds) call.seconds = seconds
                call.missed = false
            }
            // Close the session so a later call to the same contact is its own
            // record rather than being folded into this one.
            call.lastAt = 0L
            dirty = true
            save()
        }
    }

    fun hasChanges(): Boolean = dirty

    fun snapshot(): List<Map<String, Any>> = synchronized(lock) {
        prune(System.currentTimeMillis())
        dirty = false
        save()
        calls.values.sortedByDescending { it.at }.map {
            mapOf(
                "app" to it.app,
                "contact" to it.contact,
                "video" to it.video,
                "incoming" to it.incoming,
                // A connected call is never a missed one, whatever the ringing
                // notification said at the time.
                "missed" to (it.missed && it.connectedAt == 0L),
                "at" to it.at,
                "seconds" to it.seconds,
            )
        }
    }

    /** Empties the store after a server-side wipe. */
    fun clearAll() = synchronized(lock) {
        calls.clear()
        dirty = false
        save()
    }

    internal fun resetForTest() = synchronized(lock) {
        calls.clear()
        dirty = false
    }

    private fun prune(now: Long) {
        val cutoff = now - RETAIN_MS
        val it = calls.entries.iterator()
        while (it.hasNext()) {
            if (it.next().value.at < cutoff) it.remove()
        }
        if (calls.size > MAX) {
            val oldestFirst = calls.entries.sortedBy { it.value.at }
            for (i in 0 until calls.size - MAX) calls.remove(oldestFirst[i].key)
        }
    }

    /** A stuck notification must not turn into a day-long "call". */
    private const val MAX_SECONDS = 6L * 60 * 60

    // ---- Persistence ------------------------------------------------------

    private fun save() {
        val ctx = appCtx ?: return
        try {
            val arr = JSONArray()
            for (c in calls.values) {
                arr.put(
                    JSONObject()
                        .put("app", c.app)
                        .put("contact", c.contact)
                        .put("video", c.video)
                        .put("incoming", c.incoming)
                        .put("missed", c.missed)
                        .put("at", c.at)
                        .put("seconds", c.seconds)
                        .put("connectedAt", c.connectedAt)
                        .put("directionKnown", c.directionKnown)
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
            val cutoff = System.currentTimeMillis() - RETAIN_MS
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val at = o.optLong("at")
                if (at < cutoff) continue
                val app = o.optString("app")
                val contact = o.optString("contact")
                if (app.isEmpty() || contact.isEmpty()) continue
                calls[keyOf(app, contact, at)] = Call(
                    app = app,
                    contact = contact,
                    video = o.optBoolean("video"),
                    incoming = o.optBoolean("incoming"),
                    missed = o.optBoolean("missed"),
                    at = at,
                    seconds = o.optLong("seconds"),
                    // Reloaded calls are finished, so none of them is live.
                    lastAt = 0L,
                    connectedAt = o.optLong("connectedAt"),
                    directionKnown = o.optBoolean("directionKnown", true),
                )
            }
        } catch (_: Exception) {
        }
    }
}

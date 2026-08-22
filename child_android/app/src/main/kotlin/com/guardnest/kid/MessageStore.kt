package com.guardnest.kid

import android.content.Context
import java.util.Locale

/**
 * Buffers chat messages captured from app notifications and on-screen scraping
 * (WhatsApp and other messengers), ready to be flushed to Firestore.
 *
 * Messages are queued and drained in batches by [EnforcementService]; each is
 * written as its own document in a per-contact thread subcollection, so there's
 * no fixed message cap and no whole-document re-sends.
 *
 * The hard part is identity: the same message is seen over and over (every
 * scroll, every re-opened chat, every process restart) and each sighting may
 * carry *less* information than the last — WhatsApp only shows the date on a
 * separator or the fading scroll pill, and a recycling row sometimes hides the
 * bubble's own time. Since the upload id is derived from the message's day and
 * time, a sighting that learned more than the previous one used to mint a
 * *second* id and the parent saw the message twice. [identities] remembers what
 * was already uploaded for each message and, when a later sighting fills in a
 * missing day or time, supersedes the old document instead of adding one.
 *
 * Note: this only sees INCOMING messages that post a notification plus whatever
 * is visible on screen — the full encrypted chat database of apps like WhatsApp
 * is sandboxed and unreadable.
 */
object MessageStore {

    data class Msg(
        val app: String,
        val sender: String,
        val text: String,
        val at: Long,
        val outgoing: Boolean,
        val timeLabel: String,
        val number: String,
        /** Start of the day the message's date separator resolved to, 0 if unknown. */
        val dayStart: Long = 0L,
        /** Tie-break position among the messages sharing this minute. */
        val slot: Int = 0,
        /** Deterministic id material for this message's Firestore document. */
        val docKey: String = "",
        /** Id material of the document this one supersedes, blank if none. */
        val replaces: String = "",
    )

    // Cap the pending queue so a long parent outage can't grow memory without
    // bound; oldest queued messages are dropped first.
    private const val PENDING_MAX = 400
    // Distinct messages remembered for dedup. Generous: every forgotten message
    // that is still on screen gets re-uploaded (harmless) and, worse, loses the
    // day/time it had already resolved.
    private const val IDENTITY_MAX = 3000
    private const val PREFS = "guardnest_msgs"
    private const val KEY_IDS = "msgIdentities"

    /**
     * How long a captured message stays suppressed.
     *
     * Upload ids are a deterministic hash of the message itself and are written
     * with merge, so re-sending one can't duplicate it — this only saves
     * bandwidth. Keeping it forever meant that once history was deleted on the
     * server, every message still on screen stayed suppressed and the chat list
     * never came back. Expiring it lets that repair itself.
     */
    private const val RESEND_TTL_MS = 6L * 60 * 60 * 1000

    /**
     * What we know, and already uploaded, about one captured message.
     *
     * [side] is null until a sighting could actually tell which side of the
     * conversation the row sits on. It is never guessed: "ok" from the child and
     * "ok" from the contact are the same text in the same chat, so a guess would
     * let one of them adopt the other's identity and flip sides on screen.
     */
    private class Entry(
        var day: Long,
        var label: String,
        var side: Boolean?,
        var slot: Int,
        var at: Long,
    )

    private val lock = Any()
    private val pending = ArrayDeque<Msg>()
    // Message text -> every distinct message with that text in that chat. The
    // same text sent twice keeps two entries (they resolve to different times,
    // or to different sides), so a genuine repeat is still its own message.
    // Persisted, because the OS restarts this process often on low-memory
    // devices and an in-memory map meant every re-opened chat was uploaded from
    // scratch.
    private val identities = LinkedHashMap<String, MutableList<Entry>>()
    // Next free tie-break position per chat-and-minute. A chat time label has no
    // seconds, so messages sharing a minute would otherwise land on the same
    // millisecond and Firestore would order them by their (random) id.
    private val groupSlots = HashMap<String, Int>()
    private var appCtx: Context? = null

    fun init(ctx: Context) {
        if (appCtx != null) return
        appCtx = ctx.applicationContext
        val saved = try {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getStringSet(KEY_IDS, null)
        } catch (_: Exception) {
            null
        } ?: return
        synchronized(lock) {
            for (line in saved) {
                // day, at, slot, side, then the two variable-length fields last
                // so a label or a message containing the separator can't shift
                // the parse.
                val parts = line.split('\u0001', limit = 6)
                if (parts.size < 6) continue
                val day = parts[0].toLongOrNull() ?: continue
                val at = parts[1].toLongOrNull() ?: continue
                val slot = parts[2].toIntOrNull() ?: continue
                val side = when (parts[3]) {
                    "1" -> true
                    "0" -> false
                    else -> null
                }
                val loose = parts[5]
                identities.getOrPut(loose) { ArrayList(1) }
                    .add(Entry(day, parts[4], side, slot, at))
                val group = groupKey(loose, day, parts[4])
                groupSlots[group] = maxOf(groupSlots[group] ?: 0, slot + 1)
            }
        }
    }

    fun record(
        app: String,
        sender: String,
        text: String,
        outgoing: Boolean? = null,
        timeLabel: String = "",
        number: String = "",
        dayStart: Long = 0L,
    ): Boolean {
        if (text.isBlank()) return false
        val now = System.currentTimeMillis()
        val label = timeLabel.trim()
        synchronized(lock) {
            val loose = looseKey(app, sender, text)
            // Re-inserting keeps the map in least-recently-seen order, so
            // eviction drops the messages that scrolled out of reach first.
            val list = identities.remove(loose) ?: ArrayList(1)
            identities[loose] = list
            while (identities.size > IDENTITY_MAX) {
                identities.remove(identities.keys.first())
            }

            // A sighting matches a known message when nothing it *does* know
            // contradicts it: a day-less or time-less scrape of a message we
            // already resolved is that same message, not a new one.
            val entry = list.firstOrNull { matches(it, dayStart, label, outgoing) }
            if (entry == null) {
                val slot = nextSlot(loose, dayStart, label)
                list.add(Entry(dayStart, label, outgoing, slot, now))
                queue(Msg(app, sender, text, now, outgoing == true, label, number,
                    dayStart, slot, docKey(loose, dayStart, label)))
                return true
            }

            val learnsDay = entry.day <= 0L && dayStart > 0L
            val learnsTime = entry.label.isBlank() && label.isNotBlank()
            val learnsSide = entry.side == null && outgoing != null
            if (!learnsDay && !learnsTime && !learnsSide &&
                now - entry.at < RESEND_TTL_MS
            ) {
                return false
            }
            val was = docKey(loose, entry.day, entry.label)
            if (learnsDay) entry.day = dayStart
            if (learnsTime) entry.label = label
            if (learnsSide) entry.side = outgoing
            entry.at = now
            val key = docKey(loose, entry.day, entry.label)
            // Only a message that moved to a different minute needs a new
            // position; re-sending one otherwise must not shuffle the thread.
            if (key != was) entry.slot = nextSlot(loose, entry.day, entry.label)
            queue(Msg(app, sender, text, now, entry.side == true, entry.label,
                number, entry.day, entry.slot, key, if (key == was) "" else was))
            return true
        }
    }

    private fun queue(msg: Msg) {
        pending.addLast(msg)
        while (pending.size > PENDING_MAX) pending.removeFirst()
    }

    private fun matches(e: Entry, day: Long, label: String, side: Boolean?): Boolean {
        if (day > 0L && e.day > 0L && e.day != day) return false
        if (side != null && e.side != null && e.side != side) return false
        if (label.isNotEmpty() && e.label.isNotEmpty() &&
            timeKey(e.label) != timeKey(label)
        ) {
            return false
        }
        return true
    }

    private fun nextSlot(loose: String, day: Long, label: String): Int {
        val group = groupKey(loose, day, label)
        val slot = groupSlots[group] ?: 0
        groupSlots[group] = slot + 1
        return slot.coerceAtMost(999)
    }

    /** The chat and minute a message belongs to, which its slot is counted in. */
    private fun groupKey(loose: String, day: Long, label: String): String {
        val app = loose.indexOf('\u0000')
        val sender = if (app < 0) -1 else loose.indexOf('\u0000', app + 1)
        val chat = if (sender < 0) loose else loose.substring(0, sender)
        return "$chat\u0000${dayKey(day)}${timeKey(label)}"
    }

    private fun looseKey(app: String, sender: String, text: String) =
        "$app\u0000$sender\u0000$text"

    /**
     * Id material for one message's document. Kept byte-for-byte compatible
     * with the ids already in Firestore, so a re-upload merges into the
     * existing document instead of adding a second copy.
     */
    private fun docKey(loose: String, day: Long, label: String) =
        "$loose\u0000${dayKey(day)}${timeKey(label)}"

    private fun dayKey(day: Long) =
        if (day > 0L) (day / 86_400_000L).toString() else ""

    private fun timeKey(label: String) =
        if (label.isBlank()) "NOTIME"
        else label.uppercase(Locale.ROOT).replace(" ", "")

    fun hasChanges(): Boolean = synchronized(lock) { pending.isNotEmpty() }

    /** Removes and returns the queued messages (oldest first) for upload. */
    fun drain(): List<Msg> = synchronized(lock) {
        val out = pending.toList()
        pending.clear()
        out
    }.also { if (it.isNotEmpty()) persistIdentities() }

    /** Keeps what was already uploaded across process restarts. */
    private fun persistIdentities() {
        val ctx = appCtx ?: return
        val snapshot = synchronized(lock) {
            val out = HashSet<String>()
            for ((loose, list) in identities) {
                for (e in list) {
                    val side = when (e.side) {
                        true -> "1"
                        false -> "0"
                        null -> "-"
                    }
                    out.add(
                        "${e.day}\u0001${e.at}\u0001${e.slot}\u0001$side" +
                            "\u0001${e.label}\u0001$loose"
                    )
                }
            }
            out
        }
        try {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putStringSet(KEY_IDS, snapshot).apply()
        } catch (e: Exception) {
            Diag.warn(ctx, "messageStore:persist", e)
        }
    }

    /** Re-queues messages at the front if their upload failed. */
    fun requeue(msgs: List<Msg>) = synchronized(lock) {
        for (m in msgs.asReversed()) pending.addFirst(m)
        while (pending.size > PENDING_MAX) pending.removeFirst()
    }

    /**
     * Forgets everything captured and queued. After the parent wipes history
     * server-side, the messages still visible on screen must be capturable
     * again — otherwise the dedup memory silently keeps the chat list empty.
     */
    fun resetForClear() {
        synchronized(lock) {
            pending.clear()
            identities.clear()
            groupSlots.clear()
        }
        try {
            appCtx?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                ?.edit()?.remove(KEY_IDS)?.apply()
        } catch (_: Exception) {
        }
    }
}


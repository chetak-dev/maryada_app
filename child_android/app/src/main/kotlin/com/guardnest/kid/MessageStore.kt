package com.guardnest.kid

/**
 * Buffers chat messages captured from app notifications and on-screen scraping
 * (WhatsApp and other messengers), ready to be flushed to Firestore.
 *
 * Messages are queued and drained in batches by [EnforcementService]; each is
 * written as its own document in a per-contact thread subcollection, so there's
 * no fixed message cap and no whole-document re-sends. A bounded "seen" set
 * keeps repeated screen scrapes / reposted notifications of the same message
 * from being queued twice.
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
    )

    // Cap the pending queue so a long parent outage can't grow memory without
    // bound; oldest queued messages are dropped first.
    private const val PENDING_MAX = 400
    private const val SEEN_MAX = 1000
    private val lock = Any()
    private val pending = ArrayDeque<Msg>()
    // Remembers recently captured messages so repeated screen scrapes / reposted
    // notifications of the same message aren't queued again.
    private val seen = LinkedHashSet<String>()

    fun record(
        app: String,
        sender: String,
        text: String,
        outgoing: Boolean = false,
        timeLabel: String = "",
        number: String = "",
    ) {
        if (text.isBlank()) return
        // Dedup key ignores direction but keeps the displayed time, so the same
        // message captured via notification / scrape / OCR collapses to one,
        // while a genuinely repeated text at a different time is kept.
        val key = "$app|$sender|$text|$timeLabel"
        val now = System.currentTimeMillis()
        synchronized(lock) {
            if (!seen.add(key)) return // already captured recently
            while (seen.size > SEEN_MAX) seen.remove(seen.iterator().next())
            pending.addLast(Msg(app, sender, text, now, outgoing, timeLabel, number))
            while (pending.size > PENDING_MAX) pending.removeFirst()
        }
    }

    fun hasChanges(): Boolean = synchronized(lock) { pending.isNotEmpty() }

    /** Removes and returns the queued messages (oldest first) for upload. */
    fun drain(): List<Msg> = synchronized(lock) {
        val out = pending.toList()
        pending.clear()
        out
    }

    /** Re-queues messages at the front if their upload failed. */
    fun requeue(msgs: List<Msg>) = synchronized(lock) {
        for (m in msgs.asReversed()) pending.addFirst(m)
        while (pending.size > PENDING_MAX) pending.removeFirst()
    }
}


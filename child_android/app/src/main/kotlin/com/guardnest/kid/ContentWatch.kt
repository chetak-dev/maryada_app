package com.guardnest.kid

import android.content.Context

/**
 * Runs captured text through [ContentFilter] and raises an alert when something
 * unsafe appears.
 *
 * The web filter can bounce a child off a page, but nothing can un-send a
 * message or un-watch a video — so this only tells the parent. It exists
 * because the same words that block a website went unnoticed in a chat or a
 * video title, which is where a child is far more likely to meet them.
 */
object ContentWatch {

    /** A captured chat message, whoever sent it. */
    fun message(
        ctx: Context,
        app: String,
        chat: String,
        text: String,
        outgoing: Boolean,
    ) {
        val hit = ContentFilter.matchWords(text.lowercase()) ?: return
        val who = if (outgoing) "sent by ${childName(ctx)}" else "received"
        AlertLog.log(
            ctx,
            type = "unsafeMessage",
            detail = "Unsafe language $who in $app \u00b7 $chat (\u201C$hit\u201D)",
            // One conversation is one story; without this a bad exchange would
            // file an alert per message.
            throttleKey = "msg:$app:$chat",
            category = ContentFilter.categoryOf(hit),
        )
    }

    /** A video title, from either the accessibility read or the media session. */
    fun video(ctx: Context, title: String, channel: String) {
        val hit = ContentFilter.matchWords(title.lowercase()) ?: return
        val from = if (channel.isBlank()) "" else " \u00b7 $channel"
        AlertLog.log(
            ctx,
            type = "unsafeVideo",
            detail = "Unsafe video title (\u201C$hit\u201D): $title$from",
            throttleKey = "yt:$title",
            category = ContentFilter.categoryOf(hit),
        )
    }

    private fun childName(ctx: Context): String =
        ChildStore.deviceName(ctx).ifBlank { "this device" }
}

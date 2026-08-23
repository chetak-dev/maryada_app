package com.guardnest.kid

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * The standing reminder that Maryada isn't fully set up yet: it appears
 * whenever a required permission is missing and clears itself only once every
 * one has been granted. Tapping it opens the permission screen.
 *
 * Like [TempAccessNotice] it is deliberately unshakeable — ongoing, never
 * auto-cancelling, and re-posted the instant it's swiped away.
 */
object SetupNotice {

    private const val CHANNEL_ID = "guardnest_setup"
    const val NOTIF_ID = 1003
    private const val ACTION_DISMISSED = "com.guardnest.kid.SETUP_NOTICE_DISMISSED"

    /**
     * Brings the notice in line with the device's current permission state.
     * [SetupService] owns the notification so the system itself refuses to let
     * it be swiped away; this just starts or stops that service.
     */
    fun sync(ctx: Context) = SetupService.sync(ctx)

    /** Posts the notice directly — the service's periodic re-assert. */
    fun repost(ctx: Context) {
        DeviceLockdown.forceNotificationsAllowed(ctx)
        nm(ctx).notify(NOTIF_ID, build(ctx))
    }

    /** The notification itself, used as [SetupService]'s foreground notice. */
    fun build(ctx: Context): Notification {
        val manager = nm(ctx)
        // Without this the child could simply switch the app's notifications off.
        DeviceLockdown.forceNotificationsAllowed(ctx)
        val channel = liveChannelId(manager)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channel,
                    "Setup required",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Shown until every Maryada permission is granted."
                    setShowBadge(true)
                }
            )
        }
        val open = PendingIntent.getActivity(
            ctx,
            2,
            Intent(ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val onDismissed = PendingIntent.getBroadcast(
            ctx,
            3,
            Intent(ctx, DismissReceiver::class.java).setAction(ACTION_DISMISSED),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val missing = Permissions.missingCount(ctx)
        val text = if (missing == 1) {
            "1 permission still needs your approval. Tap to finish setup."
        } else {
            "$missing permissions still need your approval. Tap to finish setup."
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(ctx)
        }
        return builder
            .setContentTitle("Maryada setup isn’t finished")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentIntent(open)
            .setDeleteIntent(onDismissed)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .build()
            // Keeps "Clear all" from taking it down.
            .apply { flags = flags or Notification.FLAG_NO_CLEAR }
    }

    private fun nm(ctx: Context) =
        ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /**
     * The first channel id that hasn't been switched off. An app can never
     * re-enable a channel the user turned off, but a fresh id starts allowed —
     * so silencing the notice in Settings only buys the child one round.
     */
    private fun liveChannelId(manager: NotificationManager): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return CHANNEL_ID
        var id = CHANNEL_ID
        for (i in 1..20) {
            val existing = manager.getNotificationChannel(id) ?: break
            if (existing.importance != NotificationManager.IMPORTANCE_NONE) break
            id = "$CHANNEL_ID$i"
        }
        return id
    }

    /** Puts the notice straight back when the child swipes it away. */
    class DismissReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent?) {
            SetupService.sync(context.applicationContext)
        }
    }
}

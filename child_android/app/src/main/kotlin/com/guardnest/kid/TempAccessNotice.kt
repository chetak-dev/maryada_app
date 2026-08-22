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
 * The standing notice that Temporary Access (banking mode) turned Maryada's
 * protections off.
 *
 * It is deliberately unshakeable: ongoing, not auto-cancelling, and re-posted
 * both on every enforcement tick and the instant the child swipes it away
 * (newer Android lets even ongoing notifications be dismissed). It only clears
 * once every protection the session switched off has been granted again —
 * turning accessibility back on alone isn't enough, because notification access
 * has to be re-allowed by hand.
 */
object TempAccessNotice {

    private const val CHANNEL_ID = "guardnest_temp_access"
    private const val NOTIF_ID = 1002
    private const val ACTION_DISMISSED = "com.guardnest.kid.TEMP_ACCESS_NOTICE_DISMISSED"

    /** Starts the notice; it stays until every permission is back. */
    fun begin(ctx: Context) {
        ChildStore.setTempAccessNotice(ctx, true)
        sync(ctx)
    }

    /** Brings the notification in line with the device's current state. */
    fun sync(ctx: Context) {
        if (!ChildStore.tempAccessNotice(ctx)) return
        if (Permissions.allGranted(ctx)) {
            ChildStore.setTempAccessNotice(ctx, false)
            nm(ctx).cancel(NOTIF_ID)
            return
        }
        post(ctx)
    }

    private fun post(ctx: Context) {
        val manager = nm(ctx)
        // Without this the child could simply switch the app's notifications off.
        DeviceLockdown.forceNotificationsAllowed(ctx)
        val channel = liveChannelId(manager)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channel,
                    "Protection paused",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Shown while Temporary Access has protections off."
                    setShowBadge(true)
                }
            )
        }
        val open = PendingIntent.getActivity(
            ctx,
            0,
            Intent(ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val onDismissed = PendingIntent.getBroadcast(
            ctx,
            1,
            Intent(ctx, DismissReceiver::class.java).setAction(ACTION_DISMISSED),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val text = "Tap to turn every Maryada permission back on. This stays " +
            "until protection is fully restored."
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(ctx)
        }
        manager.notify(
            NOTIF_ID,
            builder
                .setContentTitle("Temporary Access is on — protection is off")
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentIntent(open)
                .setDeleteIntent(onDismissed)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .build()
        )
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
            sync(context.applicationContext)
        }
    }
}

package com.guardnest.kid

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Keeps the "setup isn't finished" notice on screen while any Maryada
 * permission is missing.
 *
 * It exists because a plain notification — even an ongoing one — can be swiped
 * away on Android 14+, and re-posting from the delete-intent broadcast is
 * unreliable on OEMs that freeze background processes. A foreground service's
 * notification cannot be dismissed at all below API 34, and above it the
 * service is alive to put it straight back.
 *
 * Stops itself the moment every permission has been granted.
 */
class SetupService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            if (!stillNeeded(this@SetupService)) {
                stopSelf()
                return
            }
            // Re-assert it, in case it was dismissed on Android 14+.
            SetupNotice.repost(this@SetupService)
            handler.postDelayed(this, REFRESH_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        startInForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        if (!stillNeeded(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, REFRESH_MS)
        return START_STICKY
    }

    private fun startInForeground() {
        val notification = SetupNotice.build(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                SetupNotice.NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(SetupNotice.NOTIF_ID, notification)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val REFRESH_MS = 4_000L

        /** Banking mode turns protections off deliberately and has its own notice. */
        private fun stillNeeded(ctx: Context): Boolean =
            !ChildStore.tempAccessNotice(ctx) && !Permissions.allGranted(ctx)

        /** Starts or stops the notice to match the current permission state. */
        fun sync(ctx: Context) {
            val intent = Intent(ctx, SetupService::class.java)
            if (!stillNeeded(ctx)) {
                ctx.stopService(intent)
                return
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
            } catch (e: Exception) {
                // Background-start restrictions can refuse this; the plain
                // notification below still covers the child.
                Diag.warn(ctx, "setupService", e)
                SetupNotice.repost(ctx)
            }
        }
    }
}

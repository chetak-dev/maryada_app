package com.guardnest.kid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

/**
 * Receives the result of an OTA install session ([AppUpdater]). On a Device
 * Owner device the install completes silently (STATUS_SUCCESS). If the system
 * asks for user confirmation (non-owner devices), we launch the confirm dialog
 * as a best effort — but silent install (Device Owner) is the intended path.
 */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AppUpdater.ACTION_INSTALL_RESULT) return
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (android.os.Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirm?.let {
                    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(it)
                    } catch (_: Exception) {
                    }
                }
            }
            else -> {
                // STATUS_SUCCESS / failure — nothing to do; the app restarts on
                // a successful update.
            }
        }
    }
}

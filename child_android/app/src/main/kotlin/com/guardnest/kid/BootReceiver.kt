package com.guardnest.kid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts enforcement after the device reboots or the app is updated. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            // Boot, or an app update that replaced our package — in both cases
            // any running foreground service was killed, so start it again.
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> EnforcementService.start(context)
        }
    }
}

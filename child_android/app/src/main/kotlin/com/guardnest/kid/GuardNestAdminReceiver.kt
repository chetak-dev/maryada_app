package com.guardnest.kid

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Registering as a Device Administrator (and, for real protection, as Device
 * Owner) prevents the app from being uninstalled directly. The user must first
 * deactivate the admin in Settings — which the tamper-guard/Device Owner blocks.
 */
class GuardNestAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        return "Turning this off will let Maryada be removed. Ask a parent first."
    }
}

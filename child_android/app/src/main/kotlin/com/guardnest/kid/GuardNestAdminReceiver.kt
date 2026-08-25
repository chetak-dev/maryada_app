package com.guardnest.kid

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions

/**
 * Registering as a Device Administrator (and, for real protection, as Device
 * Owner) prevents the app from being uninstalled directly. The user must first
 * deactivate the admin in Settings — which the tamper-guard/Device Owner blocks.
 */
class GuardNestAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        return "Turning this off will let Maryada be removed. Ask a parent first."
    }

    /**
     * Deactivating the admin is the one step nobody can skip on the way to
     * uninstalling, so this is the last moment the app can tell the parent
     * anything. After it the device simply goes quiet, which on its own is
     * indistinguishable from a flat battery.
     */
    override fun onDisabled(context: Context, intent: Intent) {
        mark(context, active = false)
    }

    /** Re-activated (or reinstalled and set up again): clear the marker. */
    override fun onEnabled(context: Context, intent: Intent) {
        mark(context, active = true)
    }

    private fun mark(ctx: Context, active: Boolean) {
        val familyId = ChildStore.familyId(ctx) ?: return
        val childId = ChildStore.childId(ctx) ?: return
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val payload = mapOf(
            "adminActive" to active,
            "adminChangedAt" to FieldValue.serverTimestamp(),
        )
        val child = FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("children").document(childId)
        try {
            child.collection("devices").document(uid)
                .set(payload, SetOptions.merge())
            child.set(payload, SetOptions.merge())
        } catch (e: Exception) {
            Diag.warn(ctx, "adminMark", e)
        }
    }
}

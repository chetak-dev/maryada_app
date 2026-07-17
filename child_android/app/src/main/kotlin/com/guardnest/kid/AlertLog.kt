package com.guardnest.kid

import android.content.Context
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

/**
 * Writes a single event to the family's alert feed
 * (`families/{familyId}/alerts`). The parent app reads this in the Alerts tab.
 *
 * Fire-and-forget: any failure is swallowed so enforcement is never blocked.
 * An in-memory throttle keeps repeated events (e.g. the same blocked app tapped
 * over and over) from spamming the feed.
 */
object AlertLog {
    private val lastByKey = HashMap<String, Long>()
    private const val THROTTLE_MS = 60_000L

    fun log(ctx: Context, type: String, detail: String, throttleKey: String? = null) {
        val fid = ChildStore.familyId(ctx) ?: return
        val cid = ChildStore.childId(ctx) ?: return
        if (throttleKey != null) {
            val now = System.currentTimeMillis()
            val last = lastByKey[throttleKey] ?: 0L
            if (now - last < THROTTLE_MS) return
            lastByKey[throttleKey] = now
        }
        try {
            FirebaseFirestore.getInstance()
                .collection("families").document(fid)
                .collection("alerts")
                .add(
                    mapOf(
                        "type" to type,
                        "detail" to detail,
                        "childId" to cid,
                        "at" to FieldValue.serverTimestamp(),
                    )
                )
        } catch (_: Exception) {
        }
    }

    /** Best-effort human app name for a package; falls back to the package id. */
    fun appLabel(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg
    }
}

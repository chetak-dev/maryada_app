package com.guardnest.kid

import android.app.Application
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreSettings
import com.google.firebase.firestore.PersistentCacheSettings

/**
 * Sets up Firestore before anything touches it.
 *
 * Firestore's offline cache defaults to 100 MB, which on a child device is
 * almost all waste: this app writes far more than it reads, and the only reads
 * are a handful of small rule documents it subscribes to. Left alone the cache
 * grew until the app looked like it was hoarding storage.
 *
 * Persistence itself stays ON — a phone with no signal has to queue its reports
 * rather than drop them — the cache is just given a sane ceiling and evicts
 * least-recently-used data past it.
 */
class GuardNestApp : Application() {

    override fun onCreate() {
        super.onCreate()
        try {
            FirebaseFirestore.getInstance().firestoreSettings =
                FirebaseFirestoreSettings.Builder()
                    .setLocalCacheSettings(
                        PersistentCacheSettings.newBuilder()
                            .setSizeBytes(CACHE_BYTES)
                            .build()
                    )
                    .build()
        } catch (e: Exception) {
            // Settings can only be applied before the first use; never let that
            // stop the app starting.
            Diag.warn(this, "firestoreSettings", e)
        }
    }

    private companion object {
        const val CACHE_BYTES = 16L * 1024 * 1024
    }
}

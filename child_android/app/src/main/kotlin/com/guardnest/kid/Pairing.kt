package com.guardnest.kid

import android.content.Context
import android.os.Build
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.tasks.await
import java.util.Date

/** The family's screen-time rule, read from Firestore and fed to [ScreenGuard]. */
data class ScreenTimeRule(
    val dailyLimitMinutes: Int = 120,
    val bedtimeEnabled: Boolean = false,
    val bedtimeStart: Int = 21 * 60,
    val bedtimeEnd: Int = 7 * 60,
    val paused: Boolean = false,
)

/**
 * The child-side handshake and rule sync with Firestore. Pairs the device to a
 * family/child slot (binding this device's anonymous UID as `deviceUid`, which
 * the security rules use to scope access), and reads the family's rules to
 * enforce locally.
 */
object Pairing {

    private val auth get() = FirebaseAuth.getInstance()
    private val db get() = FirebaseFirestore.getInstance()

    /** Redeems a pairing code; on success saves the pairing locally. */
    suspend fun redeem(ctx: Context, rawCode: String): String {
        val code = rawCode.trim().uppercase()
        if (code.length < 6) throw IllegalArgumentException("Enter the 6-character code.")

        val user = auth.currentUser ?: auth.signInAnonymously().await().user
        ?: throw IllegalStateException("Couldn’t sign in.")

        val codeRef = db.collection("pairingCodes").document(code)
        val snap = codeRef.get().await()
        if (!snap.exists()) throw IllegalStateException("That code isn’t valid.")
        if (snap.getBoolean("used") == true) {
            throw IllegalStateException("That code has already been used.")
        }
        val expiresAt = snap.getTimestamp("expiresAt")?.toDate()
        if (expiresAt != null && Date().after(expiresAt)) {
            throw IllegalStateException("That code has expired. Ask for a new one.")
        }

        val familyId = snap.getString("familyId")
            ?: throw IllegalStateException("Code is missing its family.")
        val childId = snap.getString("childId")
            ?: throw IllegalStateException("Code is missing its child.")

        // Bind this device to the child slot. `pairingCode` is included because
        // the security rules use it to verify this claim really came from the
        // one-time code the parent generated for THIS child — without it any
        // anonymous client that guessed the ids could take the slot over.
        db.collection("families").document(familyId)
            .collection("children").document(childId)
            .set(
                mapOf(
                    "paired" to true,
                    "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "deviceUid" to user.uid,
                    "pairingCode" to code,
                    "online" to true,
                    "setupComplete" to true,
                    "permissionsOk" to true,
                    "pairedAt" to FieldValue.serverTimestamp(),
                    "lastSeenAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            ).await()

        // A removed installation keeps its entry in the profile's devices map
        // as an audit/revocation marker. Pairing it again is the only operation
        // allowed to reactivate that exact installation.
        val deviceName = snap.getString("deviceName")?.trim() ?: ""
        ChildStore.setDeviceName(ctx, deviceName)
        try {
            db.collection("families").document(familyId)
                .collection("children").document(childId)
                .set(
                    mapOf(
                        "devices" to mapOf(
                            user.uid to mapOf(
                                "deviceUid" to user.uid,
                                "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
                                "displayName" to deviceName,
                                "platform" to "android",
                                "revoked" to false,
                                "pairedAt" to FieldValue.serverTimestamp(),
                            )
                        )
                    ),
                    SetOptions.merge()
                ).await()
        } catch (e: Exception) {
            Diag.warn(ctx, "pair:deviceRecord", e)
        }

        // Register the device. This is what the rules read to decide which
        // family's settings this anonymous device is allowed to see, so it must
        // happen before the code is spent. Not fatal: on a build that ships
        // before the matching rules are deployed this write is rejected, and
        // pairing must still succeed — ensureDeviceRegistered() retries later.
        try {
            db.collection("devices").document(user.uid)
                .set(
                    mapOf(
                        "familyId" to familyId,
                        "childId" to childId,
                        "pairedAt" to FieldValue.serverTimestamp(),
                    ),
                    SetOptions.merge()
                ).await()
            ChildStore.setDeviceRegistered(ctx, true)
        } catch (e: Exception) {
            ChildStore.setDeviceRegistered(ctx, false)
            if (e !is FirebaseFirestoreException ||
                e.code != FirebaseFirestoreException.Code.PERMISSION_DENIED
            ) {
                Diag.warn(ctx, "pair:registerDevice", e)
            }
        }

        try {
            codeRef.update(mapOf("used" to true, "usedAt" to FieldValue.serverTimestamp()))
                .await()
        } catch (e: Exception) {
            // The device is already bound; leaving the code unspent is better
            // than failing a pairing that actually worked.
            Diag.warn(ctx, "pair:markCodeUsed", e)
        }

        ChildStore.save(ctx, familyId, childId)
        snap.getString("familyName")?.trim()?.takeIf { it.isNotEmpty() }?.let {
            ChildStore.setFamilyName(ctx, it)
        }
        return "Connected to your family."
    }

    /**
     * Makes sure this device has its `devices/{uid}` registration, which the
     * security rules use to decide which family's settings it may read.
     *
     * Devices paired by an older build never wrote one, and the write is
     * rejected until the matching rules are live — so this keeps being retried
     * (cheaply: one flag check once it has succeeded) until it sticks, letting a
     * device recover on its own rather than needing a restart.
     */
    fun ensureDeviceRegistered(ctx: Context) {
        if (ChildStore.deviceRegistered(ctx)) return
        val familyId = ChildStore.familyId(ctx) ?: return
        val childId = ChildStore.childId(ctx) ?: return
        val uid = auth.currentUser?.uid ?: return
        db.collection("devices").document(uid)
            .set(
                mapOf(
                    "familyId" to familyId,
                    "childId" to childId,
                    "pairedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            )
            .addOnSuccessListener { ChildStore.setDeviceRegistered(ctx, true) }
            .addOnFailureListener { error ->
                if (error is FirebaseFirestoreException &&
                    error.code == FirebaseFirestoreException.Code.PERMISSION_DENIED
                ) {
                    // Expected while the compatible APK is deployed before the
                    // hardened rules. Legacy child-doc authorization still
                    // protects the device, so this is migration state, not a
                    // parent-facing device failure.
                    if (Diag.clearIf(ctx, "ensureDeviceRegistered")) {
                        db.collection("families").document(familyId)
                            .collection("children").document(childId)
                            .set(
                                mapOf("lastError" to null, "lastErrorAt" to null),
                                SetOptions.merge()
                            )
                    }
                } else {
                    Diag.warn(ctx, "ensureDeviceRegistered", error)
                }
            }
    }

    /** Removes this device's registration when the parent unlinks it. */
    fun unregisterDevice(ctx: Context) {
        ChildStore.setDeviceRegistered(ctx, false)
        val uid = auth.currentUser?.uid ?: return
        db.collection("devices").document(uid).delete()
            .addOnFailureListener { Diag.warn(ctx, "unregisterDevice", it) }
    }

    /** Reads the family's current screen-time rule (defaults if none set). */
    suspend fun fetchScreenTime(ctx: Context): ScreenTimeRule {
        val familyId = ChildStore.familyId(ctx) ?: return ScreenTimeRule()
        val doc = db.collection("families").document(familyId)
            .collection("rules").document("screenTime").get().await()
        if (!doc.exists()) return ScreenTimeRule()
        fun i(k: String, d: Int) = (doc.get(k) as? Number)?.toInt() ?: d
        return ScreenTimeRule(
            dailyLimitMinutes = i("dailyLimitMinutes", 120),
            bedtimeEnabled = doc.getBoolean("bedtimeEnabled") ?: false,
            bedtimeStart = i("bedtimeStart", 21 * 60),
            bedtimeEnd = i("bedtimeEnd", 7 * 60),
            paused = doc.getBoolean("paused") ?: false,
        )
    }
}

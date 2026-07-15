package com.guardnest.kid

import android.content.Context
import android.os.Build
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
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

        // Bind this device to the child slot.
        db.collection("families").document(familyId)
            .collection("children").document(childId)
            .set(
                mapOf(
                    "paired" to true,
                    "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "deviceUid" to user.uid,
                    "online" to true,
                    "setupComplete" to true,
                    "permissionsOk" to true,
                    "pairedAt" to FieldValue.serverTimestamp(),
                    "lastSeenAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge()
            ).await()

        codeRef.update(mapOf("used" to true, "usedAt" to FieldValue.serverTimestamp()))
            .await()

        ChildStore.save(ctx, familyId, childId)
        return "Linked to your family."
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

package com.guardnest.kid

import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony

/**
 * Reads the device SMS inbox/sent so the guardian can review text messages.
 * Requires the READ_SMS runtime permission; returns null when it isn't granted
 * so the caller can skip silently.
 */
object SmsReader {

    private const val MAX = 100

    data class SmsEntry(
        val address: String,
        val body: String,
        val type: Int,
        val date: Long,
    )

    fun hasAccess(ctx: Context): Boolean =
        ctx.checkSelfPermission(android.Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    /** Returns the most recent messages (newest first), or null without access. */
    fun recent(ctx: Context): List<SmsEntry>? {
        if (!hasAccess(ctx)) return null
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.TYPE,
            Telephony.Sms.DATE,
        )
        val out = ArrayList<SmsEntry>()
        try {
            ctx.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                projection,
                null,
                null,
                "${Telephony.Sms.DATE} DESC",
            )?.use { c ->
                val iAddr = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val iBody = c.getColumnIndex(Telephony.Sms.BODY)
                val iType = c.getColumnIndex(Telephony.Sms.TYPE)
                val iDate = c.getColumnIndex(Telephony.Sms.DATE)
                while (c.moveToNext() && out.size < MAX) {
                    val address = c.getString(iAddr)?.takeIf { it.isNotBlank() } ?: "Unknown"
                    val body = c.getString(iBody) ?: ""
                    out.add(
                        SmsEntry(
                            address = address,
                            body = body,
                            type = if (iType >= 0) c.getInt(iType) else 0,
                            date = if (iDate >= 0) c.getLong(iDate) else 0L,
                        )
                    )
                }
            }
        } catch (_: Exception) {
            return null
        }
        return out
    }
}

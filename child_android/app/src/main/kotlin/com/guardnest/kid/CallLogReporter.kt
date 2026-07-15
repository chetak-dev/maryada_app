package com.guardnest.kid

import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog

/**
 * Reads the device call log so the guardian can review the child's recent
 * calls. Requires the READ_CALL_LOG runtime permission; returns null when it
 * isn't granted so the caller can skip silently.
 */
object CallLogReporter {

    private const val MAX = 100

    data class CallEntry(
        val number: String,
        val name: String?,
        val type: Int,
        val date: Long,
        val durationSeconds: Long,
    )

    fun hasAccess(ctx: Context): Boolean =
        ctx.checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED

    /** Returns the most recent calls (newest first), or null without permission. */
    fun recent(ctx: Context): List<CallEntry>? {
        if (!hasAccess(ctx)) return null
        val projection = arrayOf(
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
        )
        val out = ArrayList<CallEntry>()
        try {
            ctx.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                null,
                null,
                "${CallLog.Calls.DATE} DESC",
            )?.use { c ->
                val iNumber = c.getColumnIndex(CallLog.Calls.NUMBER)
                val iName = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val iType = c.getColumnIndex(CallLog.Calls.TYPE)
                val iDate = c.getColumnIndex(CallLog.Calls.DATE)
                val iDur = c.getColumnIndex(CallLog.Calls.DURATION)
                while (c.moveToNext() && out.size < MAX) {
                    val number = c.getString(iNumber)?.takeIf { it.isNotBlank() } ?: "Unknown"
                    val name = c.getString(iName)?.takeIf { it.isNotBlank() }
                    out.add(
                        CallEntry(
                            number = number,
                            name = name,
                            type = if (iType >= 0) c.getInt(iType) else 0,
                            date = if (iDate >= 0) c.getLong(iDate) else 0L,
                            durationSeconds = if (iDur >= 0) c.getLong(iDur) else 0L,
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

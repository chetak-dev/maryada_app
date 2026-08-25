package com.guardnest.kid

import android.content.Context
import android.content.pm.PackageInstaller
import android.os.Build
import com.google.firebase.firestore.FirebaseFirestore
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Remote self-update ("OTA"). The child fleet is unreachable after setup, so
 * updates are pushed from Firestore: a manifest doc gives the newest version
 * code and an APK URL. When a newer build is available, the app downloads it and
 * installs it via [PackageInstaller].
 *
 * On a **Device Owner** device the install is **silent** (no user tap needed) —
 * exactly what a hands-off family device needs. The APK must be signed with the
 * same release key as the installed app, or Android rejects the update.
 *
 * Firestore: `appConfig/kid` -> { enabled: Bool, versionCode: Number, url: String }.
 */
object AppUpdater {

    const val ACTION_INSTALL_RESULT = "com.guardnest.kid.UPDATE_INSTALL_RESULT"

    /**
     * e.g. "v1.0.0(24)" — the name people read plus the real versionCode, which
     * is what actually decides whether an update applies. Showing the true
     * number is the only way to tell which build a device is running.
     */
    fun versionLabel(ctx: Context): String = try {
        val info = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION") info.versionCode.toLong()
        }
        "v${info.versionName}($code)"
    } catch (_: Exception) {
        ""
    }

    @Volatile
    private var checking = false

    /** Current installed version code. */
    private fun currentVersion(ctx: Context): Long {
        return try {
            val info = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION") info.versionCode.toLong()
            }
        } catch (_: Exception) {
            Long.MAX_VALUE // if we can't read our own version, never "update"
        }
    }

    /** What a manual "check for update" ended up doing. */
    enum class CheckResult { UP_TO_DATE, DOWNLOADING, BUSY, FAILED }

    /**
     * Reads the update manifest and, if a newer build is published, downloads
     * and installs it on a background thread. Safe to call repeatedly; ignores
     * overlapping calls.
     */
    fun checkAndUpdate(ctx: Context) = checkAndUpdate(ctx, null)

    /**
     * As [checkAndUpdate], but reports back on the main thread so a parent who
     * asked for the check is told whether anything is happening. Waiting up to
     * three hours for the background check to notice a published build was the
     * only way to take an update before.
     */
    fun checkAndUpdate(ctx: Context, onResult: ((CheckResult) -> Unit)?) {
        val report: (CheckResult) -> Unit = { result ->
            if (onResult != null) {
                android.os.Handler(android.os.Looper.getMainLooper())
                    .post { onResult(result) }
            }
        }
        if (checking) {
            report(CheckResult.BUSY)
            return
        }
        checking = true
        FirebaseFirestore.getInstance()
            .collection("appConfig").document("kid")
            .get()
            .addOnSuccessListener { doc ->
                try {
                    if (doc == null || !doc.exists() ||
                        doc.getBoolean("enabled") == false
                    ) {
                        checking = false
                        report(CheckResult.UP_TO_DATE)
                        return@addOnSuccessListener
                    }
                    val latest = (doc.get("versionCode") as? Number)?.toLong() ?: 0L
                    val url = (doc.getString("url"))?.takeIf { it.startsWith("https://") }
                    if (url == null || latest <= currentVersion(ctx)) {
                        checking = false
                        report(CheckResult.UP_TO_DATE)
                        return@addOnSuccessListener
                    }
                    report(CheckResult.DOWNLOADING)
                    Thread {
                        try {
                            downloadAndInstall(ctx, url)
                        } catch (_: Exception) {
                        } finally {
                            checking = false
                        }
                    }.apply { isDaemon = true }.start()
                } catch (_: Exception) {
                    checking = false
                    report(CheckResult.FAILED)
                }
            }
            .addOnFailureListener {
                checking = false
                report(CheckResult.FAILED)
            }
    }

    private fun downloadAndInstall(ctx: Context, url: String) {
        val apk = File(ctx.cacheDir, "guardnest-update.apk")
        // Download (HTTPS only) to the cache dir.
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000
            readTimeout = 60_000
            instanceFollowRedirects = true
        }
        try {
            if (conn.responseCode != HttpURLConnection.HTTP_OK) return
            conn.inputStream.use { input ->
                apk.outputStream().use { output -> input.copyTo(output) }
            }
        } finally {
            conn.disconnect()
        }
        if (apk.length() <= 0L) return
        installApk(ctx, apk)
    }

    /**
     * Installs the downloaded APK. On Device Owner this commits silently; on a
     * non-owner device the system would need the user to confirm (handled, best
     * effort, by [UpdateInstallReceiver]).
     */
    private fun installApk(ctx: Context, apk: File) {
        val installer = ctx.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply { setAppPackageName(ctx.packageName) }

        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("guardnest_update", 0, apk.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val intent = android.content.Intent(ACTION_INSTALL_RESULT).setPackage(ctx.packageName)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                android.app.PendingIntent.FLAG_MUTABLE or
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pending = android.app.PendingIntent.getBroadcast(ctx, sessionId, intent, flags)
            session.commit(pending.intentSender)
        }
    }
}

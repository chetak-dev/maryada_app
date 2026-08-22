package com.guardnest.kid

/**
 * Package identity shared by every enforcement path.
 *
 * These lists used to be copied into [ForegroundApp], the accessibility
 * service, the notification listener and the enforcement service, so adding a
 * browser (or a new YouTube fork) meant editing several files and missing one
 * left a hole in the filter. Everything that needs to recognise a package asks
 * here instead.
 */
object Pkgs {

    /** Known browser packages across the common Android OEMs. */
    val BROWSERS: Set<String> = setOf(
        "com.android.chrome", "com.chrome.beta", "com.chrome.dev", "com.chrome.canary",
        "org.mozilla.firefox", "org.mozilla.focus", "org.mozilla.fenix",
        "com.opera.browser", "com.opera.mini.native", "com.opera.gx",
        "com.brave.browser", "com.brave.browser_beta", "com.microsoft.emmx",
        "com.sec.android.app.sbrowser", "com.sec.android.app.sbrowser.beta",
        "com.duckduckgo.mobile.android", "com.UCMobile.intl", "com.UCMobile.x86",
        "com.mi.globalbrowser", "com.mi.globalbrowser.mini", "com.android.browser",
        "com.heytap.browser", "com.coloros.browser", "com.oppo.browser",
        "com.vivaldi.browser", "com.yandex.browser", "com.ecosia.android",
        "com.kiwibrowser.browser", "mark.via.gp", "acr.browser.lightning",
        "com.qwant.liberty", "org.torproject.torbrowser", "com.aloha.browser",
    )

    /** YouTube app packages: official plus the common Vanced/ReVanced forks. */
    val YOUTUBE: Set<String> = setOf(
        "com.google.android.youtube",
        "app.vanced.android.youtube",
        "app.revanced.android.youtube",
        "app.rvx.android.youtube",
    )

    /** True if [pkg] is a web browser. */
    fun isBrowser(pkg: String): Boolean =
        pkg.isNotEmpty() && (pkg in BROWSERS || pkg.contains("browser"))

    /** True if [pkg] is a YouTube app (official or a fork). Forks are
     *  repackaged constantly, so the name is matched as well as the list. */
    fun isYoutube(pkg: String): Boolean =
        pkg in YOUTUBE || (pkg.contains("youtube") && !pkg.contains("music"))

    /** True if [pkg] is a home screen / launcher. */
    fun isLauncher(pkg: String): Boolean =
        pkg.contains("launcher") || pkg.contains("trebuchet") || pkg.endsWith(".home")

    /**
     * System surfaces the child must always be able to reach so the "fix your
     * permissions" path can never deadlock — Settings, the permission UI, the
     * launcher, the status bar and the dialer (for emergency calls).
     */
    fun isEssentialSystem(pkg: String): Boolean =
        pkg == "android" ||
            pkg.contains("settings") ||
            pkg.contains("permissioncontroller") ||
            pkg.contains("systemui") ||
            isLauncher(pkg) ||
            pkg.contains("dialer") ||
            pkg.contains(".phone")
}

package com.guardnest.kid

/**
 * The apps the child is still allowed to use while a required protection is
 * OFF (the "banking mode" / lockbox allow-list). The parent curates this in the
 * family-wide App rules (an app marked "Allow in banking mode"); the child
 * reads it from the `appRules` listener in [EnforcementService], unioned with
 * the built-in [DEFAULTS]. Applies to every child in the family.
 *
 * Why it exists: strict banking / UPI apps refuse to run while an accessibility
 * service is enabled. So the child may turn protections off to use them — but
 * when protections are off, [EnforcementService] suspends every other app
 * (Device Owner), leaving only these reachable. Turning protections back on
 * restores everything. See [EnforcementService.applyLockbox].
 */
object SensitiveApps {

    /**
     * A sensible default so banking works out of the box before the parent
     * curates the list: major UPI wallets and authenticator apps.
     */
    val DEFAULTS: Set<String> = setOf(
        "com.google.android.apps.nbu.paisa.user", // Google Pay
        "com.phonepe.app",                        // PhonePe
        "net.one97.paytm",                        // Paytm
        "in.org.npci.upiapp",                     // BHIM
        "in.amazon.mShop.android.shopping",       // Amazon Pay (shopping app)
        "com.google.android.apps.authenticator2", // Google Authenticator
        "com.azure.authenticator",                // Microsoft Authenticator
    )

    @Volatile
    var packages: Set<String> = DEFAULTS

    fun isSensitive(pkg: String): Boolean = packages.contains(pkg)
}

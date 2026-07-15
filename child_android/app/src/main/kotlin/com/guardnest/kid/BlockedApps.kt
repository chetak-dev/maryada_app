package com.guardnest.kid

/**
 * The set of packages the parent has blocked. Written by [EnforcementService]
 * (from the Firestore app-rules listener) and read by the accessibility
 * blocker, which bounces the child out of any blocked app it opens.
 */
object BlockedApps {
    @Volatile
    var packages: Set<String> = emptySet()

    fun isBlocked(pkg: String): Boolean = packages.contains(pkg)
}

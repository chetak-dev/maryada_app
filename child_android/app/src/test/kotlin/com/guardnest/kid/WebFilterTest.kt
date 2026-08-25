package com.guardnest.kid

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The blocklist match is what actually keeps a site out of the browser, so the
 * subdomain/alias/`www.` cases are pinned here — an over-eager match would block
 * unrelated sites ("notexample.com" vs "example.com") and a lax one would let a
 * blocked site through via a subdomain.
 */
class WebFilterTest {

    @After
    fun reset() {
        WebFilter.updatePolicy(
            enabled = false,
            blockOtherBrowsers = false,
            categories = emptySet(),
            approvedBrowser = null,
        )
        WebFilter.updateSites(emptySet())
    }

    private fun enable(vararg sites: String) {
        WebFilter.updatePolicy(
            enabled = true,
            blockOtherBrowsers = false,
            categories = emptySet(),
            approvedBrowser = null,
        )
        WebFilter.updateSites(sites.toSet())
    }

    @Test
    fun `nothing is blocked while the filter is off`() {
        WebFilter.updateSites(setOf("example.com"))
        assertFalse(WebFilter.isBlocked("example.com"))
    }

    @Test
    fun `exact and subdomain matches are blocked`() {
        enable("example.com")
        assertTrue(WebFilter.isBlocked("example.com"))
        assertTrue(WebFilter.isBlocked("www.example.com"))
        assertTrue(WebFilter.isBlocked("news.example.com"))
        assertTrue(WebFilter.isBlocked("EXAMPLE.COM"))
    }

    @Test
    fun `similarly named sites are not blocked`() {
        enable("example.com")
        assertFalse(WebFilter.isBlocked("notexample.com"))
        assertFalse(WebFilter.isBlocked("example.com.evil.net"))
        assertFalse(WebFilter.isBlocked(""))
    }

    @Test
    fun `blocking youtube com also blocks the youtu be alias`() {
        enable("youtube.com")
        assertTrue(WebFilter.isBlocked("youtu.be"))
    }

    @Test
    fun `youtube website is recognised regardless of the blocklist`() {
        assertTrue(WebFilter.isYoutubeWeb("www.youtube.com"))
        assertTrue(WebFilter.isYoutubeWeb("m.youtube.com"))
        assertTrue(WebFilter.isYoutubeWeb("youtu.be"))
        assertTrue(WebFilter.isYoutubeWeb("youtubekids.com"))
        assertFalse(WebFilter.isYoutubeWeb("youtubeclone.com"))
    }

    @Test
    fun `search engines are recognised for the content-scan skip`() {
        assertTrue(WebFilter.isSearchEngine("www.google.com"))
        assertTrue(WebFilter.isSearchEngine("google.co.in"))
        assertTrue(WebFilter.isSearchEngine("duckduckgo.com"))
        assertTrue(WebFilter.isSearchEngine("yandex.ru"))
        assertFalse(WebFilter.isSearchEngine("example.com"))
    }

    @Test
    fun `browser lock follows only the explicit flag`() {
        assertFalse(WebFilter.shouldLockOtherBrowsers())

        WebFilter.updatePolicy(
            enabled = false,
            blockOtherBrowsers = true,
            categories = emptySet(),
        )
        assertTrue(WebFilter.shouldLockOtherBrowsers())

        // Safe browsing is permanently on, so tying the browser lock to it
        // blocked every other browser on every device.
        WebFilter.updatePolicy(
            enabled = true,
            blockOtherBrowsers = false,
            categories = emptySet(),
        )
        assertFalse(WebFilter.shouldLockOtherBrowsers())
    }

    @Test
    fun `approved browser falls back to chrome`() {
        assertEquals(WebFilter.DEFAULT_BROWSER, WebFilter.effectiveApprovedBrowser())

        WebFilter.updatePolicy(
            enabled = true,
            blockOtherBrowsers = true,
            categories = emptySet(),
            approvedBrowser = "   ",
        )
        assertEquals(WebFilter.DEFAULT_BROWSER, WebFilter.effectiveApprovedBrowser())

        WebFilter.updatePolicy(
            enabled = true,
            blockOtherBrowsers = true,
            categories = emptySet(),
            approvedBrowser = "org.mozilla.firefox",
        )
        assertEquals("org.mozilla.firefox", WebFilter.effectiveApprovedBrowser())
    }

    @Test
    fun `updating sites keeps the rest of the policy`() {
        enable("example.com")
        WebFilter.updateSites(setOf("other.com"))
        assertTrue(WebFilter.enabled)
        assertTrue(WebFilter.isBlocked("other.com"))
        assertFalse(WebFilter.isBlocked("example.com"))
    }

    @Test
    fun `package identity lists agree with themselves`() {
        assertTrue(Pkgs.isBrowser(WebFilter.DEFAULT_BROWSER))
        assertTrue(Pkgs.isYoutube("com.google.android.youtube"))
        assertFalse(Pkgs.isBrowser("com.guardnest.kid"))
        assertFalse(Pkgs.isYoutube("com.guardnest.kid"))
    }
}

package com.guardnest.kid

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The matcher now guards chat messages and video titles as well as web pages,
 * so its false-positive behaviour matters far more than it used to.
 */
class ContentFilterTest {

    @After
    fun clearKeywords() {
        ContentFilter.parentKeywords = emptySet()
        ContentFilter.backendKeywords = emptySet()
    }

    @Test
    fun `a strong brand blocks on one hit`() {
        assertEquals("pornhub", ContentFilter.match("visit pornhub now"))
    }

    @Test
    fun `one weak phrase alone is not enough`() {
        assertNull(ContentFilter.match("a documentary about self harm awareness"))
    }

    @Test
    fun `two distinct weak phrases block`() {
        val hit = ContentFilter.match("self harm and thinspo forums")
        assertEquals("self harm", hit)
    }

    @Test
    fun `a parent keyword blocks on one hit`() {
        ContentFilter.parentKeywords = setOf("casino")
        assertEquals("casino", ContentFilter.match("the casino floor"))
    }

    @Test
    fun `keywords under three characters are ignored`() {
        ContentFilter.parentKeywords = setOf("ab")
        assertNull(ContentFilter.match("ab cd ab"))
    }

    // ---- word-boundary matching, used for chat + video titles ----

    @Test
    fun `substring matching would misfire but word matching does not`() {
        ContentFilter.parentKeywords = setOf("ass")
        // The whole point: a child writing about their class must never be
        // reported to their parent for it.
        assertEquals("ass", ContentFilter.match("i am late for class"))
        assertNull(ContentFilter.matchWords("i am late for class"))
    }

    @Test
    fun `word matching still catches the real word`() {
        ContentFilter.parentKeywords = setOf("casino")
        assertEquals("casino", ContentFilter.matchWords("going to the casino tonight"))
    }

    @Test
    fun `punctuation still counts as a boundary`() {
        assertEquals("pornhub", ContentFilter.matchWords("look at pornhub.com/x"))
    }

    @Test
    fun `a term at the very start or end is matched`() {
        ContentFilter.parentKeywords = setOf("casino")
        assertEquals("casino", ContentFilter.matchWords("casino"))
        assertEquals("casino", ContentFilter.matchWords("the casino"))
    }

    @Test
    fun `an ordinary message raises nothing`() {
        assertNull(ContentFilter.matchWords("see you at 6, bring the class notes"))
    }

    @Test
    fun `blank text is always safe`() {
        assertNull(ContentFilter.match(""))
        assertNull(ContentFilter.matchWords("   "))
    }

    @Test
    fun `a matched term reports its category`() {
        assertEquals("adult", ContentFilter.categoryOf("pornhub"))
    }
}

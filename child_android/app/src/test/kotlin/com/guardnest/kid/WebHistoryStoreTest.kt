package com.guardnest.kid

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class WebHistoryStoreTest {

    @Before
    fun setUp() = WebHistoryStore.resetForTest()

    @After
    fun tearDown() = WebHistoryStore.resetForTest()

    @Test
    fun `opening a site briefly still records the navigation and time`() {
        WebHistoryStore.recordVisitAt("https://example.com/page", 1_000L)
        WebHistoryStore.recordVisitAt("https://example.com/page", 9_000L)
        WebHistoryStore.endVisitAt(9_000L)

        val (visited, _) = WebHistoryStore.snapshotAt(9_000L)
        assertEquals(1, visited.size)
        assertEquals("example.com", visited.single()["domain"])
        assertEquals(8_000L, visited.single()["milliseconds"])
        assertEquals(8L, visited.single()["seconds"])
    }

    @Test
    fun `foreground dwell accumulates exact time`() {
        WebHistoryStore.recordVisitAt("https://example.com", 1_000L)
        WebHistoryStore.recordVisitAt("https://example.com", 11_000L)

        val (visited, _) = WebHistoryStore.snapshotAt(11_000L)
        assertEquals(1, visited.size)
        assertEquals("example.com", visited.single()["domain"])
        assertEquals(10_000L, visited.single()["milliseconds"])
        assertEquals(10L, visited.single()["seconds"])
        assertEquals(1, visited.single()["visits"])
    }

    @Test
    fun `switching sites keeps both navigations with their own time`() {
        WebHistoryStore.recordVisitAt("brief.example.com", 1_000L)
        WebHistoryStore.recordVisitAt("kept.example.com", 6_000L)
        WebHistoryStore.recordVisitAt("kept.example.com", 17_000L)

        val (visited, _) = WebHistoryStore.snapshotAt(17_000L)
        assertEquals(2, visited.size)
        val byDomain = visited.associateBy { it["domain"] }
        assertEquals(5L, byDomain["brief.example.com"]?.get("seconds"))
        assertEquals(11L, byDomain["kept.example.com"]?.get("seconds"))
    }

    @Test
    fun `the same site on two days is two rows`() {
        val dayOne = 1_000L
        val dayTwo = dayOne + 2 * 24 * 60 * 60 * 1000L
        WebHistoryStore.recordVisitAt("example.com", dayOne)
        WebHistoryStore.recordVisitAt("example.com", dayOne + 5_000L)
        WebHistoryStore.endVisitAt(dayOne + 5_000L)
        WebHistoryStore.recordVisitAt("example.com", dayTwo)
        WebHistoryStore.recordVisitAt("example.com", dayTwo + 9_000L)
        WebHistoryStore.endVisitAt(dayTwo + 9_000L)

        val visited = WebHistoryStore.snapshotAt(dayTwo + 9_000L).visited
        // Newest first. One running lifetime total per domain made "today" on
        // the parent's screen a month of accumulated time.
        assertEquals(2, visited.size)
        assertEquals(listOf(9L, 5L), visited.map { it["seconds"] })
        assertEquals(listOf("example.com", "example.com"), visited.map { it["domain"] })
    }

    @Test
    fun `parses submitted Google search and decodes its query`() {
        val search = WebHistoryStore.parseSearch(
            "https://www.google.com/search?q=lord+jagannath+temple&sourceid=chrome"
        )

        assertEquals("Google", search?.engine)
        assertEquals("lord jagannath temple", search?.query)
    }

    @Test
    fun `does not capture omnibox typing or non-search pages`() {
        assertEquals(null, WebHistoryStore.parseSearch("how to learn guitar"))
        assertEquals(null, WebHistoryStore.parseSearch("https://example.com/?q=private"))
        assertEquals(null, WebHistoryStore.parseSearch("https://google.com/"))
    }

    @Test
    fun `parses YouTube search results`() {
        val search = WebHistoryStore.parseSearch(
            "youtube.com/results?search_query=bhagavad%20gita"
        )

        assertEquals("YouTube", search?.engine)
        assertEquals("bhagavad gita", search?.query)
    }

    @Test
    fun `browser polling records one entry for the active results page`() {
        val address = "https://duckduckgo.com/?q=child+safety"
        WebHistoryStore.recordSearchAt(address, 1_000L)
        WebHistoryStore.recordSearchAt(address, 2_000L)
        WebHistoryStore.recordSearchAt(address, 32_000L)

        val searches = WebHistoryStore.snapshotAt(32_000L).searches
        assertEquals(1, searches.size)
        assertEquals("child safety", searches.first()["query"])
        assertEquals("DuckDuckGo", searches.first()["engine"])
    }

    @Test
    fun `same query can be recorded again after leaving and searching later`() {
        val address = "https://duckduckgo.com/?q=child+safety"
        WebHistoryStore.recordSearchAt(address, 1_000L)
        WebHistoryStore.recordSearchAt("https://example.com", 2_000L)
        WebHistoryStore.recordSearchAt(address, 32_000L)

        assertEquals(2, WebHistoryStore.snapshotAt(32_000L).searches.size)
    }
}
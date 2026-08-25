package com.guardnest.kid

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class AppCallStoreTest {

    // Entries older than the retention window are pruned, so the fixtures have
    // to sit inside it rather than at the epoch.
    private val now = System.currentTimeMillis()

    @Before
    fun setUp() = AppCallStore.resetForTest()

    @After
    fun tearDown() = AppCallStore.resetForTest()

    @Test
    fun `the updates of one call collapse into a single record`() {
        // WhatsApp posts the ringing notice, then replaces it with an ongoing
        // one stamped at the moment it was answered. That used to file two.
        AppCallStore.record("WhatsApp", "Riya", video = false, incoming = true,
            missed = false, startedAt = now - 30_000L)
        AppCallStore.record("WhatsApp", "Riya", video = false, incoming = false,
            missed = false, startedAt = now - 25_000L, connected = true,
            directionKnown = false)

        val calls = AppCallStore.snapshot()
        assertEquals(1, calls.size)
        // The direction came from the ringing notice and must survive the
        // ongoing one, which does not name it.
        assertEquals(true, calls.single()["incoming"])
    }

    @Test
    fun `a call that connects is timed and is not missed`() {
        val ring = now - 70_000L
        val answered = now - 65_000L
        AppCallStore.record("WhatsApp", "Arjun", video = true, incoming = true,
            missed = true, startedAt = ring)
        AppCallStore.record("WhatsApp", "Arjun", video = true, incoming = false,
            missed = false, startedAt = answered, connected = true,
            directionKnown = false)
        AppCallStore.finish("WhatsApp", "Arjun", answered + 65_000L)

        val call = AppCallStore.snapshot().single()
        assertEquals(false, call["missed"])
        assertEquals(true, call["video"])
        assertEquals(true, call["incoming"])
        assertEquals(65L, call["seconds"])
    }

    @Test
    fun `a call nobody answered stays missed with no duration`() {
        AppCallStore.record("WhatsApp", "Unknown", video = false, incoming = true,
            missed = true, startedAt = now - 180_000L)

        val call = AppCallStore.snapshot().single()
        assertEquals(true, call["missed"])
        assertEquals(0L, call["seconds"])
    }

    @Test
    fun `calling the same contact again is a separate record`() {
        val first = now - 300_000L
        AppCallStore.record("WhatsApp", "Riya", video = false, incoming = false,
            missed = false, startedAt = first, connected = true)
        AppCallStore.finish("WhatsApp", "Riya", first + 20_000L)

        AppCallStore.record("WhatsApp", "Riya", video = false, incoming = false,
            missed = false, startedAt = now - 60_000L, connected = true)

        assertEquals(2, AppCallStore.snapshot().size)
    }

    @Test
    fun `a video flag from any update sticks`() {
        AppCallStore.record("WhatsApp", "Gopal", video = false, incoming = true,
            missed = false, startedAt = now - 40_000L)
        AppCallStore.record("WhatsApp", "Gopal", video = true, incoming = false,
            missed = false, startedAt = now - 35_000L, directionKnown = false)

        assertEquals(true, AppCallStore.snapshot().single()["video"])
    }
}

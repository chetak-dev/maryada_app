package com.guardnest.kid

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Bedtime/pause is the rule a child is most likely to probe, and the overnight
 * window (21:00 -> 07:00) is the case that's easy to get wrong, so it's pinned
 * down here rather than tested by hand on a device at 3 a.m.
 */
class ScreenGuardTest {

    private fun at(hour: Int, minute: Int = 0) = hour * 60 + minute

    @Test
    fun `pause locks regardless of bedtime`() {
        assertTrue(
            ScreenGuard.shouldLock(
                paused = true,
                bedtimeEnabled = false,
                bedtimeStart = 0,
                bedtimeEnd = 0,
                now = at(12),
            )
        )
    }

    @Test
    fun `disabled bedtime never locks`() {
        assertFalse(
            ScreenGuard.shouldLock(
                paused = false,
                bedtimeEnabled = false,
                bedtimeStart = at(21),
                bedtimeEnd = at(7),
                now = at(23),
            )
        )
    }

    @Test
    fun `overnight window covers both sides of midnight`() {
        val start = at(21)
        val end = at(7)
        assertTrue(ScreenGuard.isWithinWindow(at(21), start, end))   // start is inclusive
        assertTrue(ScreenGuard.isWithinWindow(at(23, 59), start, end))
        assertTrue(ScreenGuard.isWithinWindow(at(0), start, end))
        assertTrue(ScreenGuard.isWithinWindow(at(6, 59), start, end))
        assertFalse(ScreenGuard.isWithinWindow(at(7), start, end))   // end is exclusive
        assertFalse(ScreenGuard.isWithinWindow(at(20, 59), start, end))
    }

    @Test
    fun `same-day window locks only inside it`() {
        val start = at(13)
        val end = at(15)
        assertFalse(ScreenGuard.isWithinWindow(at(12, 59), start, end))
        assertTrue(ScreenGuard.isWithinWindow(at(13), start, end))
        assertTrue(ScreenGuard.isWithinWindow(at(14, 59), start, end))
        assertFalse(ScreenGuard.isWithinWindow(at(15), start, end))
    }

    @Test
    fun `empty window never locks`() {
        // start == end means "no bedtime set"; treating it as a 24h window would
        // lock the device permanently.
        assertFalse(ScreenGuard.isWithinWindow(at(9), at(9), at(9)))
    }
}

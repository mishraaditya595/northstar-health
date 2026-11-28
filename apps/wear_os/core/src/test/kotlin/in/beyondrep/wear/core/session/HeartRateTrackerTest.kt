package `in`.beyondrep.wear.core.session

import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull

class HeartRateTrackerTest {
    private val t = Instant.parse("2026-10-23T01:00:00Z")

    @Test
    fun ignoresZeroNegativeAndAbove250() {
        val tracker = HeartRateTracker()
        listOf(0.0, -1.0, 251.0).forEach { tracker.add(it, t) }
        assertNull(tracker.current)
        assertNull(tracker.average)
    }

    @Test
    fun keepsTheBoundsAndTheLatestAsCurrent() {
        val tracker = HeartRateTracker()
        tracker.add(1.0, t)
        tracker.add(250.0, t.plusSeconds(1))
        assertEquals(250, tracker.current)
    }

    @Test
    fun averageRoundsHalfUp() {
        val tracker = HeartRateTracker()
        tracker.add(70.0, t)
        tracker.add(71.0, t.plusSeconds(1))
        assertEquals(71, tracker.average)
    }

    @Test
    fun resetClears() {
        val tracker = HeartRateTracker()
        tracker.add(80.0, t)
        tracker.reset()
        assertNull(tracker.current)
        assertNull(tracker.average)
    }
}

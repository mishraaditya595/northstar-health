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

    @Test
    fun minuteSeriesAveragesPerMinuteAndSkipsEmptyMinutes() {
        val tracker = HeartRateTracker()
        tracker.add(70.0, t.plusSeconds(5))
        tracker.add(72.0, t.plusSeconds(50))
        tracker.add(80.0, t.plusSeconds(125))
        assertEquals(
            listOf(t to 71, t.plusSeconds(120) to 80),
            tracker.minuteSeries(t))
    }

    @Test
    fun minuteSeriesRoundsHalfUpAndIgnoresInvalidAndEarlierSamples() {
        val tracker = HeartRateTracker()
        tracker.add(90.0, t.minusSeconds(1))
        tracker.add(0.0, t.plusSeconds(1))
        tracker.add(70.0, t.plusSeconds(2))
        tracker.add(71.0, t.plusSeconds(3))
        assertEquals(listOf(t to 71), tracker.minuteSeries(t))
    }

    @Test
    fun minuteSeriesIsEmptyWithoutSamplesAndAfterReset() {
        val tracker = HeartRateTracker()
        assertEquals(emptyList(), tracker.minuteSeries(t))
        tracker.add(80.0, t)
        tracker.reset()
        assertEquals(emptyList(), tracker.minuteSeries(t))
    }

    @Test
    fun minuteSeriesLeavesOutMinutesTheContractWouldReject() {
        val tracker = HeartRateTracker()
        tracker.add(10.0, t.plusSeconds(1))
        tracker.add(80.0, t.plusSeconds(61))
        assertEquals(listOf(t.plusSeconds(60) to 80), tracker.minuteSeries(t))
    }
}

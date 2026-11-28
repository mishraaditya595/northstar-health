package `in`.beyondrep.wear.workout

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.Instant
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class RestHapticsTest {
    private val base = Instant.parse("2026-10-23T01:00:00Z")
    private var pulses = 0

    private fun TestScope.haptics() = RestHaptics(this, { base.plusMillis(currentTime) }) { pulses += 1 }

    @Test
    fun oneVibrationAtTheDeadline() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.plusSeconds(10))
        advanceTimeBy(9_000)
        assertEquals(0, pulses)
        advanceTimeBy(2_000)
        assertEquals(1, pulses)
    }

    @Test
    fun noVibrationForADeadlinePastAtRelaunch() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.minusSeconds(10))
        advanceTimeBy(60_000)
        assertEquals(0, pulses)
    }

    @Test
    fun theSameDeadlineTwiceVibratesOnce() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.plusSeconds(10))
        haptics.onDeadline(base.plusSeconds(10))
        advanceTimeBy(30_000)
        haptics.onDeadline(base.plusSeconds(10))
        advanceTimeBy(30_000)
        assertEquals(1, pulses)
    }

    @Test
    fun aNewDeadlineReplacesTheOldOne() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.plusSeconds(10))
        advanceTimeBy(5_000)
        haptics.onDeadline(base.plusSeconds(40))
        advanceTimeBy(7_000)
        assertEquals(0, pulses)
        advanceTimeBy(30_000)
        assertEquals(1, pulses)
    }

    @Test
    fun clearingTheRestCancelsTheVibration() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.plusSeconds(10))
        haptics.onDeadline(null)
        advanceTimeBy(30_000)
        assertEquals(0, pulses)
    }
}

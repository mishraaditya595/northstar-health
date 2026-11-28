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

    private val lock = FakeWakeLock()

    private fun TestScope.haptics() = RestHaptics(this, { base.plusMillis(currentTime) }, lock) { pulses += 1 }

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

    @Test
    fun theWakeLockIsHeldForTheRemainingTimePlusFiveSecondsAndReleasedAfterThePulse() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.plusSeconds(10))
        assertEquals(listOf(15_000L), lock.acquired)
        assertEquals(true, lock.held)
        advanceTimeBy(11_000)
        assertEquals(1, pulses)
        assertEquals(false, lock.held)
    }

    @Test
    fun clearingTheRestReleasesTheWakeLock() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.plusSeconds(10))
        haptics.onDeadline(null)
        assertEquals(false, lock.held)
        assertEquals(1, lock.acquired.size)
    }

    @Test
    fun aNewDeadlineHoldsTheLockAgainForItsOwnTime() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.plusSeconds(10))
        advanceTimeBy(5_000)
        haptics.onDeadline(base.plusSeconds(40))
        assertEquals(listOf(15_000L, 40_000L), lock.acquired)
        assertEquals(true, lock.held)
        advanceTimeBy(36_000)
        assertEquals(false, lock.held)
        assertEquals(1, pulses)
    }

    @Test
    fun aPastDeadlineTakesNoWakeLock() = runTest {
        val haptics = haptics()
        haptics.onDeadline(base.minusSeconds(10))
        assertEquals(emptyList(), lock.acquired)
    }
}

/** Records how the wake lock was used; [held] follows acquire and release (not reference counted). */
internal class FakeWakeLock : HapticWakeLock {
    val acquired = mutableListOf<Long>()
    var held = false

    override fun acquire(timeoutMs: Long) {
        acquired += timeoutMs
        held = true
    }

    override fun release() {
        held = false
    }
}

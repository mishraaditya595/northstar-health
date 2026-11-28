package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.EventHeader
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Port of RestClockTests.swift. Swift drives a SessionMachine, which is ported in a later task
 * (its journey tests there re-run the rest cases through the machine); here the events are built
 * directly, with the same sequence and deadline the machine would write.
 */
class RestClockTest {
    private val base = Instant.ofEpochSecond(1_792_000_000)

    private fun header(sequence: Int) = EventHeader(
        eventId = "00000000-0000-4000-8000-%012d".format(sequence), workoutId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        sessionId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", originDeviceId = "watch-installation-a", sequence = sequence,
        occurredAtUtc = "2026-10-23T11:00:00Z", recordedAtUtc = "2026-10-23T11:00:00Z", timeZone = "Asia/Kolkata")

    private fun rest(sequence: Int, seconds: Int, at: Instant) =
        WorkoutEventV2.RestStarted(header(sequence), seconds, at.plusSeconds(seconds.toLong()).toString())

    private fun logged(sequence: Int) = WorkoutEventV2.SetLogged(
        header(sequence), SetValues("dddddddd-dddd-4ddd-8ddd-000000000001", "x", 1, reps = 8))

    @Test
    fun deadlineFromLastRestStarted() {
        val events = listOf(rest(1, 60, base), rest(2, 90, base.plusSeconds(10)))
        assertEquals(base.plusSeconds(100), RestClock.deadline(events))
    }

    @Test
    fun deadlineIsNullWithoutRest() {
        assertNull(RestClock.deadline(emptyList()))
    }

    @Test
    fun orderIsBySequenceNotListOrder() {
        val events = listOf(rest(2, 90, base.plusSeconds(10)), rest(1, 60, base))
        assertEquals(base.plusSeconds(100), RestClock.deadline(events))
    }

    @Test
    fun clearedRestHasNoDeadline() {
        assertNull(RestClock.deadline(listOf(rest(1, 60, base), WorkoutEventV2.RestCleared(header(2)))))
    }

    @Test
    fun loggedSetEndsRest() {
        assertNull(RestClock.deadline(listOf(rest(1, 60, base), logged(2))))
    }

    @Test
    fun pausedEndsRest() {
        assertNull(RestClock.deadline(listOf(rest(1, 60, base), WorkoutEventV2.WorkoutPaused(header(2)))))
    }

    @Test
    fun completedAndAbandonedEndRest() {
        assertNull(RestClock.deadline(listOf(rest(1, 60, base), WorkoutEventV2.WorkoutCompleted(header(2)))))
        assertNull(RestClock.deadline(listOf(rest(1, 60, base), WorkoutEventV2.WorkoutAbandoned(header(2)))))
    }

    @Test
    fun restStartedAfterALoggedSetCounts() {
        assertEquals(base.plusSeconds(45), RestClock.deadline(listOf(logged(1), rest(2, 45, base))))
    }

    @Test
    fun extendAddsThirtyAndCaps() {
        assertEquals(72, RestClock.extendedSeconds(Duration.ofMillis(41_200)))
        assertEquals(3600, RestClock.extendedSeconds(Duration.ofSeconds(3590)))
        assertEquals(30, RestClock.extendedSeconds(Duration.ZERO))
    }
}

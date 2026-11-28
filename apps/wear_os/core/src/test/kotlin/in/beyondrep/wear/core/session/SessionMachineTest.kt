package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.ExerciseAddedPayload
import `in`.beyondrep.wear.core.contracts.SessionCommand
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull

/** Port of SessionMachineTests.swift. */
class SessionMachineTest {
    private val key = "0123456789abcdef".repeat(4)
    private val session = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private val exercise = "builtin.v1.synthetic-move-1"

    private fun makeMachine(): SessionMachine {
        var tick = 0L
        val base = Instant.ofEpochSecond(1_792_000_000)
        return SessionMachine(
            sessionId = session, owner = "watch", accountKey = key, deviceId = "watch-installation-a",
            clock = { tick += 1; base.plusSeconds(tick) }, timeZone = "Asia/Kolkata")
    }

    private fun started(): SessionMachine = makeMachine().also { it.start(name = "Synthetic push day") }

    private fun set(n: Int, reps: Int = 8, load: Int = 60000) = SetValues(
        setId = "dddddddd-dddd-4ddd-8ddd-00000000000$n", exerciseId = exercise, position = n, reps = reps, loadGrams = load)

    private fun noValues(n: Int) = SetValues("dddddddd-dddd-4ddd-8ddd-00000000000$n", exercise, n)

    private fun error(block: () -> Unit): SessionError = assertFailsWith<SessionException> { block() }.error

    @Test
    fun sequenceIncreasesByOnePerEvent() {
        val m = makeMachine()
        val all = m.start("Synthetic push day", exercises = listOf(ExerciseAddedPayload(exercise, "Synthetic move", "reps", 0))).toMutableList()
        all.add(m.log(set(1)))
        all.add(m.startRest(90))
        all.add(m.complete())
        assertEquals(listOf(0, 1, 2, 3, 4), all.map { it.header.sequence })
        assertEquals(all, m.events)
    }

    @Test
    fun logWhilePausedThrows() {
        val m = started()
        m.pause()
        assertEquals(SessionError.INVALID_TRANSITION, error { m.log(set(1)) })
        m.resume()
        m.log(set(1))
    }

    @Test
    fun nothingAfterComplete() {
        val m = started()
        m.complete()
        assertFailsWith<SessionException> { m.log(set(1)) }
        assertFailsWith<SessionException> { m.pause() }
        assertFailsWith<SessionException> { m.complete() }
        assertFailsWith<SessionException> { m.abandon() }
    }

    @Test
    fun correctSupersedesTheLastEventForThatSet() {
        val m = started()
        val first = m.log(set(1))
        val second = m.correct(set(1).setId, set(1, reps = 9))
        val third = m.correct(set(1).setId, set(1, reps = 10))
        assertEquals(first.header.eventId, assertIs<WorkoutEventV2.SetCorrected>(second).supersedesEventId)
        assertEquals(second.header.eventId, assertIs<WorkoutEventV2.SetCorrected>(third).supersedesEventId)
        assertEquals(10, m.state.sets.first().reps)
        assertEquals(3, m.state.sets.first().history.size)
        assertEquals(SessionError.UNKNOWN_SET, error { m.correct(set(2).setId, set(2)) })
    }

    @Test
    fun stateMatchesReplayOfEmittedEventsInAnyDeliveryOrder() {
        val m = started()
        for (n in 1..4) {
            m.log(set(n))
            m.startRest(60)
            m.clearRest()
            if (n == 2) m.correct(set(1).setId, set(1, reps = 7))
            if (n == 3) m.skip(set(5).setId)
        }
        m.pause()
        assertEquals("paused", m.status)
        assertEquals(m.status, m.state.status)
        m.resume()
        m.log(SetValues("dddddddd-dddd-4ddd-8ddd-0000000000aa", exercise, 9, durationSeconds = 45))
        assertEquals(m.status, m.state.status)
        m.complete()
        assertEquals(m.status, m.state.status)
        assertEquals(19, m.events.size)
        assertEquals(m.state, WorkoutReplay.replay(m.events.reversed() + m.events))
        assertEquals("completed", m.state.status)
        assertEquals(emptyList(), m.state.gaps)
        assertEquals(5, m.state.completedSets)
    }

    @Test
    fun commandFinishMapsToComplete() {
        val m = started()
        val event = m.apply(SessionCommand(session, "88888888-4444-4444-8444-000000000002", "finish"))
        assertIs<WorkoutEventV2.WorkoutCompleted>(event)
        assertEquals("completed", m.state.status)
    }

    @Test
    fun commandLogSetMapsToLog() {
        val m = started()
        val event = m.apply(SessionCommand(session, "88888888-4444-4444-8444-000000000001", "log_set", set(1)))
        assertIs<WorkoutEventV2.SetLogged>(event)
    }

    @Test
    fun logOrCorrectWithoutRepsOrDurationThrows() {
        val m = started()
        assertEquals(SessionError.INVALID_COMMAND, error { m.log(noValues(1)) })
        m.log(set(1))
        assertEquals(SessionError.INVALID_COMMAND, error { m.correct(set(1).setId, noValues(1)) })
        for (name in listOf("log_set", "correct_set")) {
            assertEquals(SessionError.INVALID_COMMAND, error {
                m.apply(SessionCommand(session, UUID.randomUUID().toString(), name, noValues(1)))
            })
        }
        assertEquals(2, m.events.size)
    }

    @Test
    fun loggingAnAlreadyLoggedSetEmitsACorrection() {
        val m = started()
        val first = m.log(set(1))
        val again = m.log(set(1, reps = 9))
        assertEquals(first.header.eventId, assertIs<WorkoutEventV2.SetCorrected>(again).supersedesEventId)
        assertEquals(9, m.state.sets.first().reps)
    }

    @Test
    fun duplicateCommandIsIgnored() {
        val m = started()
        fun command(id: String, name: String, reps: Int) = SessionCommand(session, id, name, set(1, reps = reps))
        val log = command("88888888-4444-4444-8444-00000000000a", "log_set", 8)
        m.apply(log)
        m.apply(command("88888888-4444-4444-8444-00000000000b", "correct_set", 9))
        val count = m.events.size
        assertNull(m.apply(log))
        assertEquals(count, m.events.size)
        assertEquals(9, m.state.sets.first().reps)
    }

    @Test
    fun restoringContinuesTheSequenceAndKnowsLoggedSets() {
        val m = started()
        val logged = m.log(set(1))
        val restored = SessionMachine.restoring(
            m.events, "watch", key, "watch-installation-a", { Instant.ofEpochSecond(1_792_100_000) }, "Asia/Kolkata",
            appliedCommandIds = setOf("88888888-4444-4444-8444-00000000000A"))
        assertEquals("active", restored.status)
        val next = restored.log(set(2))
        assertEquals(2, next.header.sequence)
        // A set that was logged before the restart is corrected, not logged twice.
        val again = restored.log(set(1, reps = 9))
        assertEquals(logged.header.eventId, assertIs<WorkoutEventV2.SetCorrected>(again).supersedesEventId)
        // Applied command ids are compared in lower case.
        assertNull(restored.apply(SessionCommand(session, "88888888-4444-4444-8444-00000000000a", "pause")))
        assertEquals("notStarted", makeMachine().status)
    }
}

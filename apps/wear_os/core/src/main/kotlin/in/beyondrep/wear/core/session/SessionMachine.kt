package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.ExerciseAddedPayload
import `in`.beyondrep.wear.core.contracts.EventHeader
import `in`.beyondrep.wear.core.contracts.SessionCommand
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import `in`.beyondrep.wear.core.contracts.WorkoutStartedPayload
import java.time.Instant
import java.util.UUID

/**
 * The watch's session rules: it turns user actions and phone commands into the next
 * `workout_sync/v2` event, or throws (port of SessionMachine.swift). It holds no storage; the
 * caller commits the returned event and the new state together (see `WatchJournal`). Not thread-safe:
 * one owner calls it at a time.
 */
class SessionMachine(
    val sessionId: String,
    val workoutId: String = UUID.randomUUID().toString().lowercase(),
    val owner: String,
    val accountKey: String,
    val deviceId: String,
    private val clock: () -> Instant,
    val timeZone: String,
    private val makeId: () -> String = { UUID.randomUUID().toString().lowercase() },
) {
    private enum class Phase(val label: String) {
        NOT_STARTED("notStarted"), ACTIVE("active"), PAUSED("paused"), COMPLETED("completed"), ABANDONED("abandoned")
    }

    private var phase = Phase.NOT_STARTED
    private var nextSequence = 0
    private val lastEventForSet = mutableMapOf<String, String>()
    private val loggedSets = mutableSetOf<String>()
    private val appliedCommandIds = mutableSetOf<String>()
    private val _events = mutableListOf<WorkoutEventV2>()

    val events: List<WorkoutEventV2> get() = _events.toList()

    /** `notStarted`, `active`, `paused`, `completed` or `abandoned`. */
    val status: String get() = phase.label

    /** Equals `WorkoutReplay.replay(events)`. */
    val state: ReplayedWorkout get() = WorkoutReplay.replay(_events)

    /**
     * An independent copy with the same state. The controller builds events on a copy and keeps it
     * only after the journal commit (Swift gets this from the machine being a struct).
     */
    fun copy(): SessionMachine {
        val c = SessionMachine(sessionId, workoutId, owner, accountKey, deviceId, clock, timeZone, makeId)
        c.phase = phase
        c.nextSequence = nextSequence
        c.lastEventForSet.putAll(lastEventForSet)
        c.loggedSets.addAll(loggedSets)
        c.appliedCommandIds.addAll(appliedCommandIds)
        c._events.addAll(_events)
        return c
    }

    private fun timestamp(): String = WatchTimestamp.format(clock())

    private fun header(): EventHeader {
        val now = timestamp()
        val h = EventHeader(makeId(), workoutId, sessionId, deviceId, nextSequence, now, now, timeZone)
        nextSequence += 1
        return h
    }

    private fun <T : WorkoutEventV2> emit(make: (EventHeader) -> T): T {
        val event = make(header())
        _events.add(event)
        return event
    }

    private fun require(vararg allowed: Phase) {
        if (phase !in allowed) throw SessionException(SessionError.INVALID_TRANSITION)
    }

    /** The `workout_started` event followed by one `exercise_added` per exercise. */
    fun start(
        name: String,
        planId: String? = null,
        programDay: Pair<String, String>? = null,
        exercises: List<ExerciseAddedPayload> = emptyList(),
    ): List<WorkoutEventV2> {
        require(Phase.NOT_STARTED)
        phase = Phase.ACTIVE
        val payload = WorkoutStartedPayload(
            name = name, owner = owner, accountKey = accountKey, planId = planId,
            programId = programDay?.first, programLocalDate = programDay?.second)
        val out = mutableListOf<WorkoutEventV2>(emit { WorkoutEventV2.WorkoutStarted(it, payload) })
        for (exercise in exercises) out.add(emit { WorkoutEventV2.ExerciseAdded(it, exercise) })
        return out
    }

    /** Adds an exercise during a session (the person picked one on the watch). */
    fun addExercise(exercise: ExerciseAddedPayload): WorkoutEventV2 {
        require(Phase.ACTIVE, Phase.PAUSED)
        return emit { WorkoutEventV2.ExerciseAdded(it, exercise) }
    }

    /**
     * Logs a set. A set that is already logged gets a `set_corrected` that supersedes its last
     * event instead of a second `set_logged`.
     */
    fun log(set: SetValues): WorkoutEventV2 {
        require(Phase.ACTIVE)
        if (set.reps == null && set.durationSeconds == null) throw SessionException(SessionError.INVALID_COMMAND)
        if (set.setId in loggedSets) return correct(set.setId, set)
        val event = emit { WorkoutEventV2.SetLogged(it, set) }
        lastEventForSet[set.setId] = event.header.eventId
        loggedSets.add(set.setId)
        return event
    }

    fun correct(setId: String, values: SetValues): WorkoutEventV2 {
        require(Phase.ACTIVE)
        if (values.reps == null && values.durationSeconds == null) throw SessionException(SessionError.INVALID_COMMAND)
        val previous = lastEventForSet[setId]
        if (previous == null || values.setId != setId) throw SessionException(SessionError.UNKNOWN_SET)
        loggedSets.add(setId)
        val event = emit { WorkoutEventV2.SetCorrected(it, values, previous) }
        lastEventForSet[setId] = event.header.eventId
        return event
    }

    fun skip(setId: String): WorkoutEventV2 {
        require(Phase.ACTIVE)
        val event = emit { WorkoutEventV2.SetSkipped(it, setId) }
        lastEventForSet[setId] = event.header.eventId
        loggedSets.remove(setId)
        return event
    }

    fun startRest(seconds: Int): WorkoutEventV2 {
        require(Phase.ACTIVE)
        if (seconds !in 1..3600) throw SessionException(SessionError.INVALID_COMMAND)
        val deadline = WatchTimestamp.format(clock().plusSeconds(seconds.toLong()))
        return emit { WorkoutEventV2.RestStarted(it, seconds, deadline) }
    }

    fun clearRest(): WorkoutEventV2 {
        require(Phase.ACTIVE)
        return emit { WorkoutEventV2.RestCleared(it) }
    }

    fun pause(): WorkoutEventV2 {
        require(Phase.ACTIVE)
        phase = Phase.PAUSED
        return emit { WorkoutEventV2.WorkoutPaused(it) }
    }

    fun resume(): WorkoutEventV2 {
        require(Phase.PAUSED)
        phase = Phase.ACTIVE
        return emit { WorkoutEventV2.WorkoutResumed(it) }
    }

    fun complete(): WorkoutEventV2 {
        require(Phase.ACTIVE, Phase.PAUSED)
        phase = Phase.COMPLETED
        return emit { WorkoutEventV2.WorkoutCompleted(it) }
    }

    fun abandon(): WorkoutEventV2 {
        require(Phase.ACTIVE, Phase.PAUSED)
        phase = Phase.ABANDONED
        return emit { WorkoutEventV2.WorkoutAbandoned(it) }
    }

    /**
     * Maps a phone command to the same methods a watch tap uses. Delivery is at least once, so a
     * command id that was already applied returns null and changes nothing. Persist the id with
     * the event (`WatchJournal.record`).
     */
    fun apply(command: SessionCommand): WorkoutEventV2? {
        if (command.sessionId != sessionId) throw SessionException(SessionError.INVALID_COMMAND)
        val commandId = command.commandId.lowercase()
        if (commandId in appliedCommandIds) return null
        val event = run(command)
        appliedCommandIds.add(commandId)
        return event
    }

    private fun run(command: SessionCommand): WorkoutEventV2 {
        val invalid = SessionException(SessionError.INVALID_COMMAND)
        return when (command.command) {
            "log_set" -> log(command.set ?: throw invalid)
            "correct_set" -> {
                val set = command.set ?: throw invalid
                correct(set.setId, set)
            }
            "skip_set" -> skip((command.set ?: throw invalid).setId)
            "start_rest" -> startRest(command.restSeconds ?: throw invalid)
            "clear_rest" -> clearRest()
            "pause" -> pause()
            "resume" -> resume()
            "finish" -> complete()
            "discard" -> abandon()
            else -> throw invalid
        }
    }

    companion object {
        /**
         * Rebuilds a machine from the events a journal stored, so a session survives a restart:
         * phase, next sequence number and the last event per set come from `events`.
         * `appliedCommandIds` are the phone commands already applied.
         */
        fun restoring(
            events: List<WorkoutEventV2>,
            owner: String,
            accountKey: String,
            deviceId: String,
            clock: () -> Instant,
            timeZone: String,
            appliedCommandIds: Set<String> = emptySet(),
            makeId: () -> String = { UUID.randomUUID().toString().lowercase() },
        ): SessionMachine {
            val seen = mutableSetOf<String>()
            val ordered = events.filter { seen.add(it.header.eventId) }.sortedBy { it.header.sequence }
            val first = ordered.firstOrNull() ?: throw SessionException(SessionError.INVALID_TRANSITION)
            val m = SessionMachine(
                first.header.sessionId, first.header.workoutId, owner, accountKey, deviceId, clock, timeZone, makeId)
            m._events.addAll(ordered)
            m.appliedCommandIds.addAll(appliedCommandIds.map { it.lowercase() })
            m.nextSequence = (ordered.maxOf { it.header.sequence }) + 1
            for (event in ordered) {
                val id = event.header.eventId
                when (event) {
                    is WorkoutEventV2.SetLogged -> {
                        m.lastEventForSet[event.values.setId] = id
                        m.loggedSets.add(event.values.setId)
                    }
                    is WorkoutEventV2.SetCorrected -> {
                        m.lastEventForSet[event.values.setId] = id
                        m.loggedSets.add(event.values.setId)
                    }
                    is WorkoutEventV2.SetSkipped -> {
                        m.lastEventForSet[event.setId] = id
                        m.loggedSets.remove(event.setId)
                    }
                    else -> Unit
                }
            }
            m.phase = when (WorkoutReplay.replay(ordered).status) {
                "paused" -> Phase.PAUSED
                "completed" -> Phase.COMPLETED
                "abandoned" -> Phase.ABANDONED
                else -> Phase.ACTIVE
            }
            return m
        }
    }
}

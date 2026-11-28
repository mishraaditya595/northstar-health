package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import `in`.beyondrep.wear.core.link.CommandApplier
import `in`.beyondrep.wear.core.link.CommandOutcome
import `in`.beyondrep.wear.core.link.SessionStateBuilder
import `in`.beyondrep.wear.core.store.JournalException
import `in`.beyondrep.wear.core.store.SessionAccount
import `in`.beyondrep.wear.core.store.WatchJournal
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * One object per watch session (port of WorkoutController.swift). It runs `SessionMachine`, commits
 * every user action to the journal in one transaction before the UI may show it as done, and
 * restores itself after a relaunch. Each mutating method builds its events on a copy of the machine
 * and replaces the machine only after the commit, so memory never runs ahead of disk. Not
 * thread-safe: one owner calls it at a time.
 */
class WorkoutController private constructor(
    internal val journal: WatchJournal,
    val accountKey: String,
    internal val unit: String,
    internal val clock: () -> Instant,
    internal val makeId: () -> String,
    internal var machine: SessionMachine,
    template: WorkoutTemplate,
) {
    private var focusExerciseId: String? = null
    private var confirmedDuplicateIds: List<String> = emptyList()

    var template: WorkoutTemplate = template
        private set

    val sessionId: String get() = machine.sessionId
    val workoutId: String get() = machine.workoutId
    val state: ReplayedWorkout get() = machine.state
    val status: String get() = machine.status
    val cursor: WorkoutCursor get() = WorkoutCursor(template, machine.state, focusExerciseId)

    /**
     * Where "Add set" goes: the exercise of the most recently logged set, else the focused
     * exercise, else the last exercise of the template.
     */
    val addSetExerciseId: String?
        get() {
            var logged: String? = null
            for (event in machine.events.sortedBy { it.header.sequence }) {
                if (event is WorkoutEventV2.SetLogged) logged = event.values.exerciseId
            }
            return logged ?: focusExerciseId ?: template.exercises.lastOrNull()?.exerciseId
        }

    /** True with at least one completed working set, the rule the builder enforces: warm-ups alone cannot be saved. */
    val canSave: Boolean get() = machine.state.completedSets >= 1

    val restDeadline: Instant? get() = RestClock.deadline(machine.events)

    val startedAt: Instant
        get() {
            for (event in machine.events) {
                if (event is WorkoutEventV2.WorkoutStarted) return WatchTimestamp.instant(event.header.occurredAtUtc) ?: clock()
            }
            return clock()
        }

    /** `commandId` is the phone command these events answer; it is stored in the same transaction (see `CommandApplier`). */
    internal fun commit(commandId: String? = null, build: (SessionMachine) -> List<WorkoutEventV2>) {
        val copy = machine.copy()
        val events = build(copy)
        journal.record(events, copy.state, commandId = commandId)
        machine = copy
    }

    /** The rest after a set: its plan seconds, else 90. */
    internal fun restSeconds(setId: String): Int {
        val seconds = template.exercises.flatMap { it.sets }.firstOrNull { it.setId == setId }?.restSeconds ?: 90
        return minOf(3600, maxOf(1, seconds))
    }

    /** Logs a set and starts its rest in one commit (two events). */
    fun log(values: SetValues) {
        val seconds = restSeconds(values.setId)
        commit { m ->
            val logged = m.log(values)
            listOf(logged, m.startRest(seconds))
        }
    }

    private fun lastValues(setId: String): SetValues? {
        var found: SetValues? = null
        for (event in machine.events.sortedBy { it.header.sequence }) {
            when (event) {
                is WorkoutEventV2.SetLogged -> if (event.values.setId == setId) found = event.values
                is WorkoutEventV2.SetCorrected -> if (event.values.setId == setId) found = event.values
                else -> Unit
            }
        }
        return found
    }

    /** Corrects the set with the same values and a new RPE (null clears it). */
    fun setRpe(setId: String, rpe: Double?) {
        val values = lastValues(setId) ?: throw SessionException(SessionError.UNKNOWN_SET)
        val changed = values.copy(rpe = rpe)
        commit { listOf(it.correct(setId, changed)) }
    }

    fun skip(setId: String) = commit { listOf(it.skip(setId)) }

    /** Adds 30 s to what remains of the rest. */
    fun extendRest() {
        val deadline = restDeadline ?: throw SessionException(SessionError.INVALID_TRANSITION)
        val remaining = Duration.between(clock(), deadline).let { if (it.isNegative) Duration.ZERO else it }
        val seconds = RestClock.extendedSeconds(remaining)
        commit { listOf(it.startRest(seconds)) }
    }

    fun skipRest() {
        if (restDeadline == null) return
        commit { listOf(it.clearRest()) }
    }

    fun pause() = commit { listOf(it.pause()) }
    fun resume() = commit { listOf(it.resume()) }

    /**
     * Adds a set that copies the last set's targets. It is stored with the template; the set
     * becomes part of the workout when it is logged.
     */
    fun addSet(exerciseId: String): String = addSet(exerciseId, null)

    internal fun addSet(exerciseId: String, commandId: String?): String {
        val (next, setId) = template.addingSet(exerciseId, makeId)
        journal.saveTemplate(sessionId, next.encode(), commandId)
        template = next
        return setId
    }

    /** Adds an exercise: the `exercise_added` event and the new template are committed together. */
    fun addExercise(name: String, kind: String, muscle: String?): String {
        val (next, exerciseId) = template.addingExercise(name, kind, muscle, makeId)
        val added = next.exerciseAddedPayloads.firstOrNull { it.exerciseId == exerciseId }
            ?: throw SessionException(SessionError.INVALID_COMMAND)
        val copy = machine.copy()
        val event = copy.addExercise(added)
        journal.record(listOf(event), copy.state, template = next.encode())
        machine = copy
        template = next
        return exerciseId
    }

    fun focus(exerciseId: String) {
        focusExerciseId = exerciseId
    }

    /**
     * Records `workout_completed`. The workout is not queued yet: the app saves the platform
     * exercise in between, then calls `queueCompleted`.
     */
    fun markCompleted() = commit { listOf(it.complete()) }

    /** Builds the `completed_workout` and queues it. Safe to repeat: a session that is already queued, delivered or rejected is left as it is. */
    fun queueCompleted(healthkitWorkoutUuid: String?) =
        queuePendingFinish(sessionId, journal, unit, accountKey, healthkitWorkoutUuid, makeId, clock)

    /** Applies a phone `session_command` at most once per command id (see `CommandApplier`). */
    fun apply(message: WatchMessage): CommandOutcome {
        val outcome = CommandApplier.apply(message, this)
        // A duplicate of an applied command means the phone did not see it confirmed yet (the
        // 20-id window moved on): list it in the next states. Memory only; the journal row already exists.
        val body = message.body
        if (outcome == CommandOutcome.Duplicate && body is WatchMessageBody.SessionCommandBody) {
            val id = body.command.commandId.lowercase()
            if (journal.commandResult(sessionId, id)?.result == "applied") {
                confirmedDuplicateIds = (confirmedDuplicateIds.filter { it != id } + id).takeLast(20)
            }
        }
        return outcome
    }

    /**
     * The `session_state` to broadcast now. `extraRejections` are refusals that have no row in the
     * journal (a command for another session).
     */
    fun sessionState(
        messageId: String,
        sentAtUtc: String,
        extraRejections: List<SessionStateBuilder.Rejection> = emptyList(),
    ): WatchMessage {
        val log = journal.commandLog(sessionId)
        return SessionStateBuilder.message(
            events = machine.events, template = template, unit = unit, accountKey = accountKey, messageId = messageId,
            sentAtUtc = sentAtUtc, focusExerciseId = focusExerciseId,
            appliedCommandIds = log.filter { it.result == "applied" }.map { it.commandId },
            confirmedCommandIds = confirmedDuplicateIds,
            rejectedCommands = log.filter { it.result == "rejected" }
                .map { SessionStateBuilder.Rejection(it.commandId, it.reason ?: "not_allowed") } + extraRejections)
    }

    /** Discards the workout (`workout_abandoned`); nothing from it is sent. */
    fun discard() = commit { listOf(it.abandon()) }

    companion object {
        /** Starts a session: the start event, one `exercise_added` per exercise and the template are committed together. */
        fun start(
            template: WorkoutTemplate,
            journal: WatchJournal,
            accountKey: String,
            unit: String,
            deviceId: String,
            clock: () -> Instant,
            timeZone: String,
            makeId: () -> String,
        ): WorkoutController {
            val machine = SessionMachine(
                sessionId = makeId(), workoutId = makeId(), owner = "watch", accountKey = accountKey, deviceId = deviceId,
                clock = clock, timeZone = timeZone, makeId = makeId)
            val day = template.programDay?.let { it.programId to it.localDate }
            val events = machine.start(template.name, template.planId, day, template.exerciseAddedPayloads)
            journal.record(events, machine.state, template = template.encode())
            return WorkoutController(journal, accountKey, unit, clock, makeId, machine, template)
        }

        /** The active or paused session of `accountKey` after a relaunch, or null. */
        fun restore(
            journal: WatchJournal,
            accountKey: String,
            unit: String,
            deviceId: String,
            clock: () -> Instant,
            timeZone: String,
        ): WorkoutController? {
            val active = journal.activeSession(accountKey) ?: return null
            val json = journal.template(active.sessionId) ?: return null
            val template = runCatching { WorkoutTemplate.decode(json) }.getOrNull() ?: return null
            val makeId: () -> String = { UUID.randomUUID().toString().lowercase() }
            val machine = SessionMachine.restoring(
                active.events, "watch", accountKey, deviceId, clock, timeZone, active.commandIds, makeId)
            return WorkoutController(journal, accountKey, unit, clock, makeId, machine, template)
        }

        /** Finished sessions whose workout was never queued (the app stopped while finishing). */
        fun pendingFinish(journal: WatchJournal, accountKey: String): List<String> = journal.sessionsAwaitingQueue(accountKey)

        /** Finished sessions of every account whose workout was never queued, with the account each belongs to. */
        fun pendingFinishAllAccounts(journal: WatchJournal): List<SessionAccount> = journal.allSessionsAwaitingQueue()

        /** When the session's `workout_completed` happened, so a recovery after a relaunch ends the platform exercise at that time and not at launch time. */
        fun completedAt(sessionId: String, journal: WatchJournal): Instant? {
            for (event in journal.events(sessionId)) {
                if (event is WorkoutEventV2.WorkoutCompleted) return WatchTimestamp.instant(event.header.occurredAtUtc)
            }
            return null
        }

        fun queuePendingFinish(
            sessionId: String,
            journal: WatchJournal,
            unit: String? = null,
            accountKey: String,
            healthkitWorkoutUuid: String?,
            makeId: () -> String,
            clock: () -> Instant,
        ) {
            if (journal.delivery(sessionId) != null) return
            val json = journal.template(sessionId) ?: throw JournalException("unknown_session")
            val template = runCatching { WorkoutTemplate.decode(json) }.getOrNull() ?: throw JournalException("unknown_session")
            val events = journal.events(sessionId)
            // Without a unit, use the one the session logged its sets in: a recovery for another
            // account must not borrow the bound account's.
            var logged: String? = null
            for (event in events) if (event is WorkoutEventV2.SetLogged) logged = logged ?: event.values.inputUnit
            val message = CompletedWorkoutBuilder.message(
                events, template, unit ?: logged ?: "kg", accountKey, healthkitWorkoutUuid, makeId(),
                WatchTimestamp.format(clock()))
            journal.queueCompleted(message, sessionId)
        }
    }
}

package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.SessionCommand
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.session.SessionError
import `in`.beyondrep.wear.core.session.SessionException
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.core.session.WorkoutTemplate
import kotlin.math.floor

/** Why the watch refused a phone command (`session_state.rejected_commands`). */
enum class RejectReason(val wire: String) {
    UNKNOWN_SESSION("unknown_session"),
    UNKNOWN_SET("unknown_set"),
    INVALID_VALUES("invalid_values"),
    NOT_ALLOWED("not_allowed"),
}

sealed interface CommandOutcome {
    /** Applied now. */
    data object Applied : CommandOutcome

    /** `finish` was accepted and `workout_completed` is recorded. The app now ends the platform exercise and calls `queueCompleted`. */
    data object NeedsFinish : CommandOutcome

    /** The command id was handled before (applied or rejected); nothing changed. */
    data object Duplicate : CommandOutcome

    /** Refused; no event was written. Listed in the next state, except `unknownSession`, which has no session to list it under. */
    data class Rejected(val reason: RejectReason) : CommandOutcome

    /** Not a command, or signed with another account's key. Nothing is written and nothing is answered. */
    data object Ignored : CommandOutcome
}

/**
 * Applies a phone `session_command` to the watch's own session (port of CommandApplier.swift). The
 * watch stays the owner: each command becomes the same journal events a tap on the watch would
 * write, and the event and the command id commit in one transaction, so a resend, a relaunch or a
 * duplicate over both transports changes nothing the second time.
 */
object CommandApplier {
    private class Rejected(val reason: RejectReason) : Exception(reason.wire)

    /** The most sets one exercise may hold; `session_state` allows 300. */
    private const val MAX_SETS_PER_EXERCISE = 100

    fun apply(message: WatchMessage, controller: WorkoutController): CommandOutcome {
        val body = message.body as? WatchMessageBody.SessionCommandBody
        if (body == null || message.accountKey != controller.accountKey) return CommandOutcome.Ignored
        val command = body.command
        if (command.sessionId.lowercase() != controller.sessionId.lowercase()) {
            return CommandOutcome.Rejected(RejectReason.UNKNOWN_SESSION)
        }
        val id = command.commandId.lowercase()
        if (controller.journal.commandResult(controller.sessionId, id) != null) return CommandOutcome.Duplicate
        val reason = try {
            return run(command, id, controller)
        } catch (e: Rejected) {
            e.reason
        } catch (e: SessionException) {
            when (e.error) {
                SessionError.INVALID_TRANSITION -> RejectReason.NOT_ALLOWED
                SessionError.UNKNOWN_SET -> RejectReason.UNKNOWN_SET
                SessionError.INVALID_COMMAND -> RejectReason.INVALID_VALUES
            }
        }
        controller.journal.recordCommand(controller.sessionId, id, "rejected", reason.wire)
        return CommandOutcome.Rejected(reason)
    }

    private fun run(command: SessionCommand, id: String, c: WorkoutController): CommandOutcome {
        when (command.command) {
            "log_set", "correct_set" -> {
                // Both become `set_logged` for a new set and `set_corrected` for one that is
                // already logged (ADR-0012 decision 6).
                val values = checkedValues(command.set, c.template)
                val seconds = c.restSeconds(values.setId)
                c.commit(id) { m ->
                    val event = m.log(values)
                    if (event is `in`.beyondrep.wear.core.contracts.WorkoutEventV2.SetLogged) {
                        listOf(event, m.startRest(seconds))
                    } else {
                        listOf(event)
                    }
                }
                return CommandOutcome.Applied
            }
            "skip_set" -> {
                val set = command.set
                if (set == null || c.template.exercises.none { e -> e.sets.any { it.setId == set.setId } }) {
                    throw Rejected(RejectReason.UNKNOWN_SET)
                }
                c.commit(id) { listOf(it.skip(set.setId)) }
                return CommandOutcome.Applied
            }
            "add_set" -> {
                val exerciseId = command.exerciseId
                val exercise = c.template.exercises.firstOrNull { it.exerciseId == exerciseId }
                if (exerciseId == null || exercise == null) throw Rejected(RejectReason.UNKNOWN_SET)
                if (!(c.status == "active" || c.status == "paused") || exercise.sets.size >= MAX_SETS_PER_EXERCISE) {
                    throw Rejected(RejectReason.NOT_ALLOWED)
                }
                c.addSet(exerciseId, id)
                return CommandOutcome.Applied
            }
            "start_rest" -> {
                val seconds = command.restSeconds
                if (seconds == null || seconds !in 1..3600) throw Rejected(RejectReason.INVALID_VALUES)
                c.commit(id) { listOf(it.startRest(seconds)) }
                return CommandOutcome.Applied
            }
            "clear_rest" -> {
                if (c.restDeadline == null) {
                    c.journal.recordCommand(c.sessionId, id, "applied", null)
                } else {
                    c.commit(id) { listOf(it.clearRest()) }
                }
                return CommandOutcome.Applied
            }
            "pause" -> {
                c.commit(id) { listOf(it.pause()) }
                return CommandOutcome.Applied
            }
            "resume" -> {
                c.commit(id) { listOf(it.resume()) }
                return CommandOutcome.Applied
            }
            "finish" -> {
                // Warm-ups alone cannot be saved (the completed-workout builder's rule).
                if (!c.canSave) throw Rejected(RejectReason.NOT_ALLOWED)
                c.commit(id) { listOf(it.complete()) }
                return CommandOutcome.NeedsFinish
            }
            "discard" -> {
                c.commit(id) { listOf(it.abandon()) }
                return CommandOutcome.Applied
            }
            else -> throw Rejected(RejectReason.INVALID_VALUES)
        }
    }

    /**
     * The set values of a `log_set` or `correct_set`, checked against the template: the set and its
     * exercise must exist, a timed exercise takes seconds and no reps or load, a reps exercise takes
     * reps and no seconds. Position and kind come from the template, not from the phone.
     */
    private fun checkedValues(set: SetValues?, template: WorkoutTemplate): SetValues {
        val values = set ?: throw Rejected(RejectReason.INVALID_VALUES)
        val exercise = template.exercises.firstOrNull { it.exerciseId == values.exerciseId }
        val planned = exercise?.sets?.firstOrNull { it.setId == values.setId }
        if (exercise == null || planned == null) throw Rejected(RejectReason.UNKNOWN_SET)
        if ((values.reps ?: 0) < 0 || (values.loadGrams ?: 0) < 0 || (values.durationSeconds ?: 1) < 1) {
            throw Rejected(RejectReason.INVALID_VALUES)
        }
        val rpe = values.rpe
        if (rpe != null && (rpe < 1 || rpe > 10 || rpe * 2 != floor(rpe * 2))) throw Rejected(RejectReason.INVALID_VALUES)
        if (exercise.kind == "duration") {
            if (values.reps != null || (values.loadGrams ?: 0) != 0 || values.durationSeconds == null) {
                throw Rejected(RejectReason.INVALID_VALUES)
            }
        } else {
            if (values.durationSeconds != null || values.reps == null) throw Rejected(RejectReason.INVALID_VALUES)
        }
        return values.copy(position = planned.position, kind = planned.kind)
    }
}

import Foundation

/// Why the watch refused a phone command (`session_state.rejected_commands`).
public enum RejectReason: String, Equatable {
    case unknownSession = "unknown_session"
    case unknownSet = "unknown_set"
    case invalidValues = "invalid_values"
    case notAllowed = "not_allowed"
}

public enum CommandOutcome: Equatable {
    /// Applied now.
    case applied
    /// `finish` was accepted and `workout_completed` is recorded. The app now
    /// ends the HealthKit workout and calls `queueCompleted`.
    case needsFinish
    /// The command id was handled before (applied or rejected); nothing changed.
    case duplicate
    /// Refused; no event was written. Listed in the next state, except
    /// `unknownSession`, which has no session to list it under.
    case rejected(RejectReason)
    /// Not a command, or signed with another account's key. Nothing is written
    /// and nothing is answered.
    case ignored
}

/// Applies a phone `session_command` to the watch's own session. The watch
/// stays the owner: each command becomes the same journal events a tap on the
/// watch would write, and the event and the command id commit in one
/// transaction, so a resend, a relaunch or a duplicate over both transports
/// changes nothing the second time.
public enum CommandApplier {
    private struct Rejected: Error {
        let reason: RejectReason
        init(_ reason: RejectReason) { self.reason = reason }
    }

    /// The most sets one exercise may hold; `session_state` allows 300.
    private static let maxSetsPerExercise = 100

    public static func apply(_ message: WatchMessage, to controller: WorkoutController) throws -> CommandOutcome {
        guard case .sessionCommand(let command) = message.body, message.accountKey == controller.accountKey else {
            return .ignored
        }
        guard command.sessionId.lowercased() == controller.sessionId.lowercased() else {
            return .rejected(.unknownSession)
        }
        let id = command.commandId.lowercased()
        if try controller.journal.commandResult(sessionId: controller.sessionId, commandId: id) != nil {
            return .duplicate
        }
        let reason: RejectReason
        do {
            return try run(command, id: id, controller: controller)
        } catch let rejected as Rejected {
            reason = rejected.reason
        } catch SessionError.invalidTransition {
            reason = .notAllowed
        } catch SessionError.unknownSet {
            reason = .unknownSet
        } catch SessionError.invalidCommand {
            reason = .invalidValues
        }
        try controller.journal.recordCommand(
            sessionId: controller.sessionId, commandId: id, result: "rejected", reason: reason.rawValue)
        return .rejected(reason)
    }

    private static func run(
        _ command: SessionCommand, id: String, controller c: WorkoutController
    ) throws -> CommandOutcome {
        switch command.command {
        case "log_set", "correct_set":
            // Both become `set_logged` for a new set and `set_corrected` for
            // one that is already logged (ADR-0012 decision 6).
            let values = try checkedValues(command.set, in: c.template)
            let seconds = c.restSeconds(forSet: values.setId)
            try c.commit(commandId: id) { m in
                let event = try m.log(set: values)
                if case .setLogged = event { return [event, try m.startRest(seconds: seconds)] }
                return [event]
            }
            return .applied
        case "skip_set":
            guard let set = command.set, c.template.exercises.contains(where: { $0.sets.contains { $0.setId == set.setId } })
            else { throw Rejected(.unknownSet) }
            try c.commit(commandId: id) { [try $0.skip(setId: set.setId)] }
            return .applied
        case "add_set":
            guard let exerciseId = command.exerciseId,
                let exercise = c.template.exercises.first(where: { $0.exerciseId == exerciseId })
            else { throw Rejected(.unknownSet) }
            guard c.status == "active" || c.status == "paused", exercise.sets.count < maxSetsPerExercise else {
                throw Rejected(.notAllowed)
            }
            _ = try c.addSet(exerciseId: exerciseId, commandId: id)
            return .applied
        case "start_rest":
            guard let seconds = command.restSeconds, (1...3600).contains(seconds) else { throw Rejected(.invalidValues) }
            try c.commit(commandId: id) { [try $0.startRest(seconds: seconds)] }
            return .applied
        case "clear_rest":
            if c.restDeadline == nil {
                try c.journal.recordCommand(sessionId: c.sessionId, commandId: id, result: "applied", reason: nil)
            } else {
                try c.commit(commandId: id) { [try $0.clearRest()] }
            }
            return .applied
        case "pause":
            try c.commit(commandId: id) { [try $0.pause()] }
            return .applied
        case "resume":
            try c.commit(commandId: id) { [try $0.resume()] }
            return .applied
        case "finish":
            // Warm-ups alone cannot be saved (the completed-workout builder's rule).
            guard c.canSave else { throw Rejected(.notAllowed) }
            try c.commit(commandId: id) { [try $0.complete()] }
            return .needsFinish
        case "discard":
            try c.commit(commandId: id) { [try $0.abandon()] }
            return .applied
        default:
            throw Rejected(.invalidValues)
        }
    }

    /// The set values of a `log_set` or `correct_set`, checked against the
    /// template: the set and its exercise must exist, a timed exercise takes
    /// seconds and no reps or load, a reps exercise takes reps and no seconds.
    /// Position and kind come from the template, not from the phone.
    private static func checkedValues(_ set: SetValues?, in template: WorkoutTemplate) throws -> SetValues {
        guard var values = set else { throw Rejected(.invalidValues) }
        guard let exercise = template.exercises.first(where: { $0.exerciseId == values.exerciseId }),
            let planned = exercise.sets.first(where: { $0.setId == values.setId })
        else { throw Rejected(.unknownSet) }
        if (values.reps ?? 0) < 0 || (values.loadGrams ?? 0) < 0 || (values.durationSeconds ?? 1) < 1 {
            throw Rejected(.invalidValues)
        }
        if let rpe = values.rpe, rpe < 1 || rpe > 10 || (rpe * 2) != (rpe * 2).rounded() {
            throw Rejected(.invalidValues)
        }
        if exercise.kind == "duration" {
            guard values.reps == nil, (values.loadGrams ?? 0) == 0, values.durationSeconds != nil else {
                throw Rejected(.invalidValues)
            }
        } else {
            guard values.durationSeconds == nil, values.reps != nil else { throw Rejected(.invalidValues) }
        }
        values.position = planned.position
        values.kind = planned.kind
        return values
    }
}

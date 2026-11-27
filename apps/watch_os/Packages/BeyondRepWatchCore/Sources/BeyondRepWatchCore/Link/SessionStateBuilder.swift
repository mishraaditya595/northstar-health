import Foundation

/// Builds the `session_state` message the watch broadcasts while a workout it
/// owns is live. It is a pure function of the session's events and template,
/// so the golden cases in `contracts/watch_link/v1/cases/session_state` pin it.
/// The message holds no health values.
public enum SessionStateBuilder {
    /// A command the watch refused, newest last.
    public struct Rejection: Equatable {
        public var commandId: String
        public var reason: String

        public init(commandId: String, reason: String) {
            self.commandId = commandId
            self.reason = reason
        }
    }

    public static func message(
        events: [WorkoutEventV2], template: WorkoutTemplate, unit: String, accountKey: String,
        messageId: String, sentAtUtc: String, focusExerciseId: String? = nil,
        appliedCommandIds: [String] = [], rejectedCommands: [Rejection] = []
    ) throws -> WatchMessage {
        var seen = Set<String>()
        let ordered = events.filter { seen.insert($0.header.eventId).inserted }
            .sorted { $0.header.sequence < $1.header.sequence }
        let state = replay(ordered)
        var started: (header: EventHeader, payload: WorkoutStartedPayload)?
        var lastUnit: [String: String] = [:]
        var pausedTotalMs: Int64 = 0
        var pausedSince: String?
        for event in ordered {
            switch event {
            case .workoutStarted(let header, let payload):
                if started == nil { started = (header, payload) }
            case .setLogged(_, let values), .setCorrected(_, let values, _):
                lastUnit[values.setId] = values.inputUnit
            case .workoutPaused(let header):
                if pausedSince == nil { pausedSince = header.occurredAtUtc }
            case .workoutResumed(let header), .workoutCompleted(let header), .workoutAbandoned(let header):
                // A pause ends at the next resume, completion or discard.
                if let since = pausedSince, let from = WatchTimestamp.milliseconds(since),
                    let to = WatchTimestamp.milliseconds(header.occurredAtUtc)
                {
                    pausedTotalMs += max(0, to - from)
                    pausedSince = nil
                }
            default:
                break
            }
        }
        guard let started else { throw SessionError.invalidTransition }

        let ended = state.status == "completed" || state.status == "abandoned"
        let status = ended ? "ended" : state.status
        var body: [String: Any] = [
            "session_id": started.header.sessionId, "owner": started.payload.owner, "status": status,
            "name": started.payload.name, "started_at_utc": started.header.occurredAtUtc,
            "last_sequence": ordered.map { $0.header.sequence }.max() ?? 0,
        ]
        if ended { body["end_reason"] = state.status == "completed" ? "completed" : "discarded" }
        if status == "paused", let pausedSince { body["paused_at_utc"] = pausedSince }
        let pausedSeconds = Int(pausedTotalMs / 1000)
        if pausedSeconds > 0 { body["paused_seconds"] = pausedSeconds }
        if let deadline = RestClock.deadline(events: ordered) {
            body["rest_deadline_utc"] = ISO8601DateFormatter().string(from: deadline)
        }
        if !ended,
            let current = WorkoutCursor(template: template, state: state, focusExerciseId: focusExerciseId).current
        {
            body["current_set_id"] = current.set.setId
        }

        var done: [String: ReplayedSet] = [:]
        for set in state.sets { done[set.setId] = set }
        var exercises: [[String: Any]] = []
        for exercise in template.exercises.sorted(by: { $0.position < $1.position }) {
            var sets: [[String: Any]] = []
            for set in exercise.sets.sorted(by: { $0.position < $1.position }) {
                var item: [String: Any] = ["set_id": set.setId, "position": set.position]
                if let replayed = done[set.setId] {
                    if replayed.status == "skipped" {
                        item["kind"] = set.kind
                        item["status"] = "skipped"
                    } else {
                        item["kind"] = replayed.kind
                        item["status"] = "completed"
                        item["input_unit"] = lastUnit[set.setId] ?? unit
                        if let reps = replayed.reps { item["reps"] = reps }
                        if let seconds = replayed.durationSeconds { item["duration_seconds"] = seconds }
                        if let load = replayed.loadGrams, load > 0 { item["load_grams"] = load }
                        if let rpe = replayed.rpe { item["rpe"] = rpe }
                    }
                } else {
                    // A planned set carries its targets so a phone can prefill it.
                    item["kind"] = set.kind
                    item["status"] = "planned"
                    item["input_unit"] = unit
                    if let reps = set.targetReps, reps > 0 { item["reps"] = reps }
                    if let seconds = set.targetSeconds, seconds > 0 { item["duration_seconds"] = seconds }
                    if let load = set.targetLoadGrams, load > 0 { item["load_grams"] = load }
                }
                sets.append(item)
            }
            exercises.append(["exercise_id": exercise.exerciseId, "name": exercise.name, "kind": exercise.kind, "sets": sets])
        }
        body["exercises"] = exercises
        if !appliedCommandIds.isEmpty { body["applied_command_ids"] = Array(appliedCommandIds.suffix(20)) }
        if !rejectedCommands.isEmpty {
            body["rejected_commands"] = rejectedCommands.suffix(20).map {
                ["command_id": $0.commandId, "reason": $0.reason]
            }
        }
        let message = WatchMessage(
            messageId: messageId, sentAtUtc: sentAtUtc, accountKey: accountKey,
            body: .sessionState(sessionId: started.header.sessionId, raw: body))
        // A strict-codec failure throws here rather than at the phone.
        _ = try WatchMessage(json: message.jsonData())
        return message
    }
}

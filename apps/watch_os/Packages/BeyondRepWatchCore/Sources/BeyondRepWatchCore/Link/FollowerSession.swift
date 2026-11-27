import Foundation

/// One set of a workout the phone owns, as its last `session_state` said.
public struct PhoneSet: Equatable {
    public var setId: String
    public var position: Int
    /// `working` or `warmup`.
    public var kind: String
    /// `planned`, `completed` or `skipped`. A planned set's values are targets.
    public var status: String
    public var inputUnit: String?
    public var reps: Int?
    public var durationSeconds: Int?
    public var loadGrams: Int?
    public var rpe: Double?
    public var restSeconds: Int?

    public var isPlanned: Bool { status == "planned" }
    public var isCompleted: Bool { status == "completed" }
    public var isSkipped: Bool { status == "skipped" }
}

public struct PhoneExercise: Equatable {
    public var exerciseId: String
    public var name: String
    /// `reps` or `duration`.
    public var kind: String
    public var sets: [PhoneSet]

    public var isTimed: Bool { kind == "duration" }
}

/// A workout that runs on the phone, read from a validated `session_state`
/// with owner `phone`. The phone's ObjectBox engine is the only authority; this
/// is a read-only picture of it. It holds no health value.
public struct PhoneWorkoutState: Equatable {
    public var messageId: String
    public var sentAt: Date
    public var accountKey: String
    public var sessionId: String
    /// `active`, `paused` or `ended`.
    public var status: String
    /// `completed` or `discarded`, only when `ended`.
    public var endReason: String?
    public var name: String
    public var startedAt: Date
    public var lastSequence: Int
    public var currentSetId: String?
    public var restDeadline: Date?
    public var pausedAt: Date?
    public var pausedSeconds: Int
    public var exercises: [PhoneExercise]
    /// Lowercase ids of the commands the phone applied.
    public var appliedCommandIds: Set<String>
    /// Lowercase command id to the phone's reason.
    public var rejectedCommands: [String: String]

    public var isPaused: Bool { status == "paused" }
    public var isEnded: Bool { status == "ended" }

    /// Nil unless `message` is a `session_state` the phone owns.
    public init?(message: WatchMessage) {
        guard case .sessionState(_, let raw) = message.body, raw["owner"] as? String == "phone",
            let sessionId = raw["session_id"] as? String, let status = raw["status"] as? String,
            let name = raw["name"] as? String, let started = (raw["started_at_utc"] as? String).flatMap(WatchTimestamp.date),
            let sentAt = WatchTimestamp.date(message.sentAtUtc), let sequence = (raw["last_sequence"] as? NSNumber)?.intValue,
            let exercises = raw["exercises"] as? [[String: Any]]
        else { return nil }
        self.messageId = message.messageId.lowercased()
        self.sentAt = sentAt
        self.accountKey = message.accountKey
        self.sessionId = sessionId.lowercased()
        self.status = status
        self.endReason = raw["end_reason"] as? String
        self.name = name
        self.startedAt = started
        self.lastSequence = sequence
        self.currentSetId = (raw["current_set_id"] as? String)?.lowercased()
        self.restDeadline = (raw["rest_deadline_utc"] as? String).flatMap(WatchTimestamp.date)
        self.pausedAt = (raw["paused_at_utc"] as? String).flatMap(WatchTimestamp.date)
        self.pausedSeconds = (raw["paused_seconds"] as? NSNumber)?.intValue ?? 0
        self.appliedCommandIds = Set((raw["applied_command_ids"] as? [String] ?? []).map { $0.lowercased() })
        var rejected: [String: String] = [:]
        for item in raw["rejected_commands"] as? [[String: Any]] ?? [] {
            if let id = item["command_id"] as? String, let reason = item["reason"] as? String {
                rejected[id.lowercased()] = reason
            }
        }
        self.rejectedCommands = rejected
        self.exercises = exercises.map { e in
            PhoneExercise(
                exerciseId: e["exercise_id"] as? String ?? "", name: e["name"] as? String ?? "",
                kind: e["kind"] as? String ?? "reps",
                sets: (e["sets"] as? [[String: Any]] ?? []).map { s in
                    PhoneSet(
                        setId: (s["set_id"] as? String ?? "").lowercased(),
                        position: (s["position"] as? NSNumber)?.intValue ?? 0, kind: s["kind"] as? String ?? "working",
                        status: s["status"] as? String ?? "planned", inputUnit: s["input_unit"] as? String,
                        reps: (s["reps"] as? NSNumber)?.intValue,
                        durationSeconds: (s["duration_seconds"] as? NSNumber)?.intValue,
                        loadGrams: (s["load_grams"] as? NSNumber)?.intValue, rpe: (s["rpe"] as? NSNumber)?.doubleValue,
                        restSeconds: (s["rest_seconds"] as? NSNumber)?.intValue)
                })
        }
    }

    /// Time on the clock: since the start, minus earlier pauses and a running one.
    public func elapsed(now: Date) -> TimeInterval {
        let running = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - Double(pausedSeconds) - running)
    }

    /// Time left of the rest, or nil when none runs (or the workout is paused).
    public func restRemaining(now: Date) -> TimeInterval? {
        guard let restDeadline, !isPaused else { return nil }
        let left = restDeadline.timeIntervalSince(now)
        return left > 0 ? left : nil
    }

    public func set(_ setId: String) -> PhoneSet? {
        exercises.lazy.flatMap(\.sets).first { $0.setId == setId.lowercased() }
    }

    public func exercise(ofSet setId: String) -> PhoneExercise? {
        exercises.first { $0.sets.contains { $0.setId == setId.lowercased() } }
    }
}

/// How a follower ends: the phone finished (the watch saves the one
/// `HKWorkout` and queues `workout_link`), or discarded or went silent (the
/// watch discards what it collected).
public enum FollowerEnd: Equatable {
    case finish(sessionId: String)
    case discard(sessionId: String)
}

/// A change of the phone workout between running and paused, so the watch's
/// HealthKit session follows it.
public enum FollowerPause: Equatable {
    case pause
    case resume
}

public enum FollowerReceive: Equatable {
    /// The state is the newest; read `state`.
    case accepted
    /// Older, a duplicate, or another session than the one followed.
    case ignored
    /// Another account's state: never followed, never answered.
    case wrongAccount
    /// The phone ended the workout.
    case ended(FollowerEnd)
}

/// A command the watch sent to the phone and how it stands.
public struct FollowerCommand: Equatable {
    public enum Phase: Equatable {
        /// Sent, not yet listed by the phone ("Saving…").
        case pending
        /// Not listed after 30 s; can be retried.
        case failed
        /// The phone refused it, with its reason.
        case rejected(String)
    }

    public let id: String
    public let sessionId: String
    public let command: String
    /// The set this command is about, for the row that shows "Saving…".
    public let setId: String?
    /// The exact message that is sent again, so its command id never changes.
    public let json: String
    public var phase: Phase
    public var firstSentAt: Date
    public var lastSentAt: Date
}

/// The watch as a follower of a phone-owned workout: the phone's last state,
/// its freshness, and the commands the watch sent and waits to see applied.
/// It owns nothing about the workout and writes nothing to the journal; the
/// follower row and the link outbox live in `WatchJournal`. Time is passed in,
/// so it is a pure model. The phone's ObjectBox engine is the authority, so a
/// command is shown as saved only when the phone lists its id as applied.
public final class FollowerSession {
    /// No state for this long and the view is read-only.
    public static let staleAfter: TimeInterval = 90
    /// A pending command is sent again this often...
    public static let resendEvery: TimeInterval = 5
    /// ...and given up on after this long since it was first sent.
    public static let giveUpAfter: TimeInterval = 30
    /// No state for this long and the watch ends with discard: the phone's own
    /// end message never arrived.
    public static let silenceLimit: TimeInterval = 6 * 3600

    public let accountKey: String
    public private(set) var state: PhoneWorkoutState?
    public private(set) var commands: [FollowerCommand] = []
    /// The session this follower belongs to: the first state's, or the one
    /// recovered after a relaunch.
    public private(set) var sessionId: String?
    /// Set by `receive`: the pause or resume the newest state implies, nil when
    /// the paused flag did not change (or the state was not accepted).
    public private(set) var pauseTransition: FollowerPause?

    private let makeId: () -> String
    private var lastReceived: Date?
    private var ended: [String] = []

    /// `recovering` is the session id of a follower row found after a relaunch
    /// (no state yet); the 6 h rule then counts from `now`.
    public init(accountKey: String, makeId: @escaping () -> String, recovering: String? = nil, now: Date? = nil) {
        self.accountKey = accountKey
        self.makeId = makeId
        self.sessionId = recovering?.lowercased()
        self.lastReceived = recovering == nil ? nil : now
    }

    /// Whether a watch with `boundAccountKey` and `hasOwnSession` joins the
    /// workout `state` describes. An own active or paused session never joins
    /// (it keeps its own workout), nor does another account, nor an ended
    /// workout.
    public static func shouldJoin(boundAccountKey: String?, state: PhoneWorkoutState, hasOwnSession: Bool) -> Bool {
        guard let boundAccountKey, boundAccountKey == state.accountKey, !hasOwnSession, !state.isEnded else {
            return false
        }
        return true
    }

    // MARK: Incoming

    @discardableResult
    public func receive(_ message: WatchMessage, now: Date) -> FollowerReceive {
        pauseTransition = nil
        guard let incoming = PhoneWorkoutState(message: message) else { return .ignored }
        guard incoming.accountKey == accountKey else { return .wrongAccount }
        if ended.contains(incoming.sessionId) { return .ignored }
        if let sessionId, incoming.sessionId != sessionId { return .ignored }
        if let current = state, incoming.sentAt < current.sentAt || incoming.messageId == current.messageId {
            return .ignored
        }
        sessionId = incoming.sessionId
        if incoming.isEnded {
            ended.append(incoming.sessionId)
            if ended.count > 5 { ended.removeFirst() }
            state = nil
            commands = []
            lastReceived = nil
            let end: FollowerEnd =
                incoming.endReason == "completed"
                ? .finish(sessionId: incoming.sessionId) : .discard(sessionId: incoming.sessionId)
            return .ended(end)
        }
        let wasPaused = state?.isPaused ?? false
        if incoming.isPaused != wasPaused { pauseTransition = incoming.isPaused ? .pause : .resume }
        state = incoming
        lastReceived = now
        commands = commands.compactMap { settle($0, in: incoming) }
        return .accepted
    }

    /// Drops an applied command, marks a refused one with the phone's reason.
    private func settle(_ command: FollowerCommand, in state: PhoneWorkoutState) -> FollowerCommand? {
        guard command.sessionId == state.sessionId, !state.appliedCommandIds.contains(command.id) else { return nil }
        if let reason = state.rejectedCommands[command.id] {
            var refused = command
            refused.phase = .rejected(reason)
            return refused
        }
        return command
    }

    // MARK: Time

    /// No state for 90 s: shown read-only, nothing is sent.
    public func isStale(now: Date) -> Bool {
        guard let lastReceived else { return state != nil }
        return now.timeIntervalSince(lastReceived) >= Self.staleAfter
    }

    /// Six hours without a state: the watch discards, because the phone's own
    /// end message never arrived. Nil while there is nothing followed.
    public func silenceEnd(now: Date) -> FollowerEnd? {
        guard let sessionId, let lastReceived, now.timeIntervalSince(lastReceived) >= Self.silenceLimit else {
            return nil
        }
        return .discard(sessionId: sessionId)
    }

    /// Messages to send again now (each pending command every 5 s), none while
    /// stale. A command first sent 30 s ago or earlier is marked failed instead.
    public func dueResends(now: Date) -> [String] {
        var due: [String] = []
        let stale = isStale(now: now)
        for index in commands.indices where commands[index].phase == .pending {
            if now.timeIntervalSince(commands[index].firstSentAt) >= Self.giveUpAfter {
                commands[index].phase = .failed
            } else if !stale && now.timeIntervalSince(commands[index].lastSentAt) >= Self.resendEvery {
                commands[index].lastSentAt = now
                due.append(commands[index].json)
            }
        }
        return due
    }

    /// Tries a failed command again with the same id; the message to send, or
    /// nil when it is not failed or the view is stale.
    public func retry(commandId: String, now: Date) -> String? {
        guard !isStale(now: now),
            let index = commands.firstIndex(where: { $0.id == commandId && $0.phase == .failed })
        else { return nil }
        commands[index].phase = .pending
        commands[index].firstSentAt = now
        commands[index].lastSentAt = now
        return commands[index].json
    }

    /// Hides a refused or failed command.
    public func dismiss(commandId: String) {
        commands.removeAll { $0.id == commandId }
    }

    /// True while any command about `setId` waits for the phone.
    public func isSaving(setId: String) -> Bool {
        commands.contains { $0.setId == setId.lowercased() && $0.phase == .pending }
    }

    // MARK: Commands

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func send(
        _ name: String, setId: String? = nil, set: SetValues? = nil, restSeconds: Int? = nil,
        exerciseId: String? = nil, now: Date
    ) -> FollowerCommand? {
        guard let state, !isStale(now: now) else { return nil }
        let commandId = makeId().lowercased()
        let message = WatchMessage(
            messageId: makeId().lowercased(), sentAtUtc: Self.timestamp.string(from: now), accountKey: accountKey,
            body: .sessionCommand(
                SessionCommand(
                    sessionId: state.sessionId, commandId: commandId, command: name, set: set,
                    restSeconds: restSeconds, exerciseId: exerciseId)))
        guard let data = try? message.jsonData() else { return nil }
        let command = FollowerCommand(
            id: commandId, sessionId: state.sessionId, command: name, setId: setId?.lowercased(),
            json: String(decoding: data, as: UTF8.self), phase: .pending, firstSentAt: now, lastSentAt: now)
        commands.append(command)
        return command
    }

    /// Logs a planned set or corrects a logged one; the phone applies both.
    public func logSet(
        setId: String, reps: Int? = nil, durationSeconds: Int? = nil, loadGrams: Int? = nil, rpe: Double? = nil,
        inputUnit: String? = nil, now: Date
    ) -> FollowerCommand? {
        guard let state, let set = state.set(setId), let exercise = state.exercise(ofSet: setId) else { return nil }
        let values = SetValues(
            setId: set.setId, exerciseId: exercise.exerciseId, position: set.position, kind: set.kind,
            inputUnit: inputUnit ?? set.inputUnit ?? "kg", reps: reps, durationSeconds: durationSeconds,
            loadGrams: (loadGrams ?? 0) > 0 ? loadGrams : nil, rpe: rpe)
        return send(set.isCompleted ? "correct_set" : "log_set", setId: set.setId, set: values, now: now)
    }

    public func skipSet(setId: String, now: Date) -> FollowerCommand? {
        guard let state, let set = state.set(setId), let exercise = state.exercise(ofSet: setId) else { return nil }
        let values = SetValues(
            setId: set.setId, exerciseId: exercise.exerciseId, position: set.position, kind: set.kind,
            inputUnit: set.inputUnit ?? "kg")
        return send("skip_set", setId: set.setId, set: values, now: now)
    }

    public func addSet(exerciseId: String, now: Date) -> FollowerCommand? {
        guard let state, state.exercises.contains(where: { $0.exerciseId == exerciseId }) else { return nil }
        return send("add_set", exerciseId: exerciseId, now: now)
    }

    public func startRest(seconds: Int, now: Date) -> FollowerCommand? {
        send("start_rest", restSeconds: seconds, now: now)
    }

    public func clearRest(now: Date) -> FollowerCommand? { send("clear_rest", now: now) }
    public func pause(now: Date) -> FollowerCommand? { send("pause", now: now) }
    public func resume(now: Date) -> FollowerCommand? { send("resume", now: now) }
    public func finish(now: Date) -> FollowerCommand? { send("finish", now: now) }
    public func discard(now: Date) -> FollowerCommand? { send("discard", now: now) }
}

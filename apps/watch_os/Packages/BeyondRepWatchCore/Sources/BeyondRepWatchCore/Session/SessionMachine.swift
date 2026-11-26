import Foundation

public enum SessionError: Error, Equatable {
    case invalidTransition
    case unknownSet
    case invalidCommand
}

/// The watch's session rules: it turns user actions and phone commands into the
/// next `workout_sync/v2` event, or throws. It holds no storage; the caller
/// commits the returned event and the new state together (see `WatchJournal`).
public struct SessionMachine {
    private enum Phase { case notStarted, active, paused, completed, abandoned }

    public let sessionId: String
    public let workoutId: String
    public let owner: String
    public let accountKey: String
    public let deviceId: String
    public let timeZone: String
    private let clock: () -> Date
    private let makeId: () -> String
    private var phase = Phase.notStarted
    private var nextSequence = 0
    private var lastEventForSet: [String: String] = [:]
    private var loggedSets: Set<String> = []
    private var appliedCommandIds: Set<String> = []
    public private(set) var events: [WorkoutEventV2] = []

    public init(
        sessionId: String, workoutId: String = UUID().uuidString.lowercased(), owner: String,
        accountKey: String, deviceId: String, clock: @escaping () -> Date, timeZone: String,
        makeId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.sessionId = sessionId
        self.workoutId = workoutId
        self.owner = owner
        self.accountKey = accountKey
        self.deviceId = deviceId
        self.clock = clock
        self.timeZone = timeZone
        self.makeId = makeId
    }

    /// Rebuilds a machine from the events a journal stored, so a session survives
    /// a restart: phase, next sequence number and the last event per set come
    /// from `events`. `appliedCommandIds` are the phone commands already applied.
    public init(
        restoring events: [WorkoutEventV2], owner: String, accountKey: String, deviceId: String,
        clock: @escaping () -> Date, timeZone: String,
        appliedCommandIds: Set<String> = [],
        makeId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) throws {
        var seen = Set<String>()
        let ordered = events.filter { seen.insert($0.header.eventId).inserted }
            .sorted { $0.header.sequence < $1.header.sequence }
        guard let first = ordered.first else { throw SessionError.invalidTransition }
        self.init(
            sessionId: first.header.sessionId, workoutId: first.header.workoutId, owner: owner,
            accountKey: accountKey, deviceId: deviceId, clock: clock, timeZone: timeZone, makeId: makeId)
        self.events = ordered
        self.appliedCommandIds = Set(appliedCommandIds.map { $0.lowercased() })
        nextSequence = (ordered.map { $0.header.sequence }.max() ?? -1) + 1
        for event in ordered {
            let id = event.header.eventId
            switch event {
            case .setLogged(_, let values), .setCorrected(_, let values, _):
                lastEventForSet[values.setId] = id
                loggedSets.insert(values.setId)
            case .setSkipped(_, let setId):
                lastEventForSet[setId] = id
                loggedSets.remove(setId)
            default: break
            }
        }
        switch replay(ordered).status {
        case "paused": phase = .paused
        case "completed": phase = .completed
        case "abandoned": phase = .abandoned
        default: phase = .active
        }
    }

    /// `notStarted`, `active`, `paused`, `completed` or `abandoned`.
    public var status: String { "\(phase)" }

    /// Equals `replay(events)`.
    public var state: ReplayedWorkout { replay(events) }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: clock())
    }

    private mutating func header() -> EventHeader {
        defer { nextSequence += 1 }
        let now = timestamp()
        return EventHeader(
            eventId: makeId(), workoutId: workoutId, sessionId: sessionId, originDeviceId: deviceId,
            sequence: nextSequence, occurredAtUtc: now, recordedAtUtc: now, timeZone: timeZone)
    }

    private mutating func emit(_ make: (EventHeader) -> WorkoutEventV2) -> WorkoutEventV2 {
        let event = make(header())
        events.append(event)
        return event
    }

    private func require(_ allowed: Phase...) throws {
        guard allowed.contains(phase) else { throw SessionError.invalidTransition }
    }

    /// The `workout_started` event followed by one `exercise_added` per exercise.
    public mutating func start(
        name: String, planId: String? = nil, programDay: (programId: String, localDate: String)? = nil,
        exercises: [ExerciseAddedPayload] = []
    ) throws -> [WorkoutEventV2] {
        try require(.notStarted)
        phase = .active
        let payload = WorkoutStartedPayload(
            name: name, owner: owner, accountKey: accountKey, planId: planId,
            programId: programDay?.programId, programLocalDate: programDay?.localDate)
        var out = [emit { .workoutStarted($0, payload) }]
        for exercise in exercises { out.append(emit { .exerciseAdded($0, exercise) }) }
        return out
    }

    /// Logs a set. A set that is already logged gets a `set_corrected` that
    /// supersedes its last event instead of a second `set_logged`.
    public mutating func log(set: SetValues) throws -> WorkoutEventV2 {
        try require(.active)
        guard set.reps != nil || set.durationSeconds != nil else { throw SessionError.invalidCommand }
        if loggedSets.contains(set.setId) { return try correct(setId: set.setId, values: set) }
        let event = emit { .setLogged($0, set) }
        lastEventForSet[set.setId] = event.header.eventId
        loggedSets.insert(set.setId)
        return event
    }

    public mutating func correct(setId: String, values: SetValues) throws -> WorkoutEventV2 {
        try require(.active)
        guard values.reps != nil || values.durationSeconds != nil else { throw SessionError.invalidCommand }
        guard let previous = lastEventForSet[setId], values.setId == setId else {
            throw SessionError.unknownSet
        }
        loggedSets.insert(setId)
        let event = emit { .setCorrected($0, values, supersedesEventId: previous) }
        lastEventForSet[setId] = event.header.eventId
        return event
    }

    public mutating func skip(setId: String) throws -> WorkoutEventV2 {
        try require(.active)
        let event = emit { .setSkipped($0, setId: setId) }
        lastEventForSet[setId] = event.header.eventId
        loggedSets.remove(setId)
        return event
    }

    public mutating func startRest(seconds: Int) throws -> WorkoutEventV2 {
        try require(.active)
        guard (1...3600).contains(seconds) else { throw SessionError.invalidCommand }
        let deadline = ISO8601DateFormatter().string(from: clock().addingTimeInterval(TimeInterval(seconds)))
        return emit { .restStarted($0, seconds: seconds, deadlineUtc: deadline) }
    }

    public mutating func clearRest() throws -> WorkoutEventV2 {
        try require(.active)
        return emit { .restCleared($0) }
    }

    public mutating func pause() throws -> WorkoutEventV2 {
        try require(.active)
        phase = .paused
        return emit { .workoutPaused($0) }
    }

    public mutating func resume() throws -> WorkoutEventV2 {
        try require(.paused)
        phase = .active
        return emit { .workoutResumed($0) }
    }

    public mutating func complete() throws -> WorkoutEventV2 {
        try require(.active, .paused)
        phase = .completed
        return emit { .workoutCompleted($0) }
    }

    public mutating func abandon() throws -> WorkoutEventV2 {
        try require(.active, .paused)
        phase = .abandoned
        return emit { .workoutAbandoned($0) }
    }

    /// Maps a phone command to the same methods a watch tap uses. Delivery is
    /// at least once, so a command id that was already applied returns `nil` and
    /// changes nothing. Persist the id with the event (`WatchJournal.record`).
    @discardableResult
    public mutating func apply(command: SessionCommand) throws -> WorkoutEventV2? {
        guard command.sessionId == sessionId else { throw SessionError.invalidCommand }
        let commandId = command.commandId.lowercased()
        if appliedCommandIds.contains(commandId) { return nil }
        let event = try run(command)
        appliedCommandIds.insert(commandId)
        return event
    }

    private mutating func run(_ command: SessionCommand) throws -> WorkoutEventV2 {
        switch command.command {
        case "log_set":
            guard let set = command.set else { throw SessionError.invalidCommand }
            return try log(set: set)
        case "correct_set":
            guard let set = command.set else { throw SessionError.invalidCommand }
            return try correct(setId: set.setId, values: set)
        case "skip_set":
            guard let set = command.set else { throw SessionError.invalidCommand }
            return try skip(setId: set.setId)
        case "start_rest":
            guard let seconds = command.restSeconds else { throw SessionError.invalidCommand }
            return try startRest(seconds: seconds)
        case "clear_rest": return try clearRest()
        case "pause": return try pause()
        case "resume": return try resume()
        case "finish": return try complete()
        case "discard": return try abandon()
        default: throw SessionError.invalidCommand
        }
    }
}

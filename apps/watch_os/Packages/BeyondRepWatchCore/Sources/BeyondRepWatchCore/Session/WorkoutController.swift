import Foundation

/// One object per watch session. It runs `SessionMachine`, commits every user
/// action to the journal in one transaction before the UI may show it as
/// done, and restores itself after a relaunch. Each mutating method builds its
/// events on a copy of the machine and replaces the machine only after the
/// commit, so memory never runs ahead of disk.
public final class WorkoutController {
    private let journal: WatchJournal
    private let accountKey: String
    private let unit: String
    private let clock: () -> Date
    private let makeId: () -> String
    private var machine: SessionMachine
    private var focusExerciseId: String?
    public private(set) var template: WorkoutTemplate

    private init(
        journal: WatchJournal, accountKey: String, unit: String, clock: @escaping () -> Date,
        makeId: @escaping () -> String, machine: SessionMachine, template: WorkoutTemplate
    ) {
        self.journal = journal
        self.accountKey = accountKey
        self.unit = unit
        self.clock = clock
        self.makeId = makeId
        self.machine = machine
        self.template = template
    }

    private static func encode(_ template: WorkoutTemplate) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(template), as: UTF8.self)
    }

    /// Starts a session: the start event, one `exercise_added` per exercise
    /// and the template are committed together.
    public static func start(
        template: WorkoutTemplate, journal: WatchJournal, accountKey: String, unit: String, deviceId: String,
        clock: @escaping () -> Date, timeZone: String, makeId: @escaping () -> String
    ) throws -> WorkoutController {
        var machine = SessionMachine(
            sessionId: makeId(), workoutId: makeId(), owner: "watch", accountKey: accountKey, deviceId: deviceId,
            clock: clock, timeZone: timeZone, makeId: makeId)
        let day = template.programDay.map { (programId: $0.programId, localDate: $0.localDate) }
        let events = try machine.start(
            name: template.name, planId: template.planId, programDay: day, exercises: template.exerciseAddedPayloads)
        try journal.record(events, sessionState: machine.state, template: try encode(template))
        return WorkoutController(
            journal: journal, accountKey: accountKey, unit: unit, clock: clock, makeId: makeId, machine: machine,
            template: template)
    }

    /// The active or paused session of `accountKey` after a relaunch, or nil.
    public static func restore(
        journal: WatchJournal, accountKey: String, unit: String, deviceId: String,
        clock: @escaping () -> Date, timeZone: String
    ) throws -> WorkoutController? {
        guard let active = try journal.activeSession(accountKey: accountKey),
            let json = try journal.template(sessionId: active.sessionId),
            let template = try? JSONDecoder().decode(WorkoutTemplate.self, from: Data(json.utf8))
        else { return nil }
        let makeId: () -> String = { UUID().uuidString.lowercased() }
        let machine = try SessionMachine(
            restoring: active.events, owner: "watch", accountKey: accountKey, deviceId: deviceId, clock: clock,
            timeZone: timeZone, appliedCommandIds: active.commandIds, makeId: makeId)
        return WorkoutController(
            journal: journal, accountKey: accountKey, unit: unit, clock: clock, makeId: makeId, machine: machine,
            template: template)
    }

    public var sessionId: String { machine.sessionId }
    public var workoutId: String { machine.workoutId }
    public var state: ReplayedWorkout { machine.state }
    public var status: String { machine.status }
    public var cursor: WorkoutCursor {
        WorkoutCursor(template: template, state: machine.state, focusExerciseId: focusExerciseId)
    }
    /// Where "Add set" goes: the exercise of the most recently logged set, else
    /// the focused exercise, else the last exercise of the template.
    public var addSetExerciseId: String? {
        var logged: String?
        for event in machine.events.sorted(by: { $0.header.sequence < $1.header.sequence }) {
            if case .setLogged(_, let values) = event { logged = values.exerciseId }
        }
        return logged ?? focusExerciseId ?? template.exercises.last?.exerciseId
    }

    /// True with at least one completed working set, the rule the builder
    /// enforces: warm-ups alone cannot be saved.
    public var canSave: Bool { machine.state.completedSets >= 1 }
    public var restDeadline: Date? { RestClock.deadline(events: machine.events) }
    public var startedAt: Date {
        for case .workoutStarted(let header, _) in machine.events {
            return WatchTimestamp.date(header.occurredAtUtc) ?? clock()
        }
        return clock()
    }

    private func commit(_ build: (inout SessionMachine) throws -> [WorkoutEventV2]) throws {
        var copy = machine
        let events = try build(&copy)
        try journal.record(events, sessionState: copy.state)
        machine = copy
    }

    /// Logs a set and starts its rest in one commit (two events).
    public func log(_ values: SetValues) throws {
        let seconds = template.exercises.flatMap(\.sets).first { $0.setId == values.setId }?.restSeconds ?? 90
        try commit { m in
            let logged = try m.log(set: values)
            return [logged, try m.startRest(seconds: min(3600, max(1, seconds)))]
        }
    }

    private func lastValues(of setId: String) -> SetValues? {
        var found: SetValues?
        for event in machine.events.sorted(by: { $0.header.sequence < $1.header.sequence }) {
            switch event {
            case .setLogged(_, let values), .setCorrected(_, let values, _):
                if values.setId == setId { found = values }
            default:
                break
            }
        }
        return found
    }

    /// Corrects the set with the same values and a new RPE (nil clears it).
    public func setRpe(setId: String, rpe: Double?) throws {
        guard var values = lastValues(of: setId) else { throw SessionError.unknownSet }
        values.rpe = rpe
        try commit { [try $0.correct(setId: setId, values: values)] }
    }

    public func skip(setId: String) throws {
        try commit { [try $0.skip(setId: setId)] }
    }

    /// Adds 30 s to what remains of the rest.
    public func extendRest() throws {
        guard let deadline = restDeadline else { throw SessionError.invalidTransition }
        let seconds = RestClock.extendedSeconds(remaining: max(0, deadline.timeIntervalSince(clock())))
        try commit { [try $0.startRest(seconds: seconds)] }
    }

    public func skipRest() throws {
        guard restDeadline != nil else { return }
        try commit { [try $0.clearRest()] }
    }

    public func pause() throws { try commit { [try $0.pause()] } }
    public func resume() throws { try commit { [try $0.resume()] } }

    /// Adds a set that copies the last set's targets. It is stored with the
    /// template; the set becomes part of the workout when it is logged.
    public func addSet(exerciseId: String) throws -> String {
        var next = template
        let setId = next.addSet(exerciseId: exerciseId, makeId: makeId)
        try journal.saveTemplate(sessionId: sessionId, json: try Self.encode(next))
        template = next
        return setId
    }

    /// Adds an exercise: the `exercise_added` event and the new template are
    /// committed together.
    public func addExercise(name: String, kind: String, muscle: String?) throws -> String {
        var next = template
        let exerciseId = next.addExercise(name: name, kind: kind, muscle: muscle, makeId: makeId)
        guard let added = next.exerciseAddedPayloads.first(where: { $0.exerciseId == exerciseId }) else {
            throw SessionError.invalidCommand
        }
        var copy = machine
        let event = try copy.addExercise(added)
        try journal.record([event], sessionState: copy.state, template: try Self.encode(next))
        machine = copy
        template = next
        return exerciseId
    }

    public func focus(exerciseId: String) {
        focusExerciseId = exerciseId
    }

    /// Records `workout_completed`. The workout is not queued yet: the app
    /// saves the HKWorkout in between, then calls `queueCompleted`.
    public func markCompleted() throws {
        try commit { [try $0.complete()] }
    }

    /// Builds the `completed_workout` and queues it. Safe to repeat: a session
    /// that is already queued, delivered or rejected is left as it is.
    public func queueCompleted(healthkitWorkoutUuid: String?) throws {
        try Self.queuePendingFinish(
            sessionId: sessionId, journal: journal, unit: unit, accountKey: accountKey,
            healthkitWorkoutUuid: healthkitWorkoutUuid, makeId: makeId, clock: clock)
    }

    /// Discards the workout (`workout_abandoned`); nothing from it is sent.
    public func discard() throws {
        try commit { [try $0.abandon()] }
    }

    /// Finished sessions whose workout was never queued (the app stopped while finishing).
    public static func pendingFinish(journal: WatchJournal, accountKey: String) throws -> [String] {
        try journal.sessionsAwaitingQueue(accountKey: accountKey)
    }

    /// Finished sessions of every account whose workout was never queued, with
    /// the account each belongs to.
    public static func pendingFinishAllAccounts(journal: WatchJournal) throws -> [(sessionId: String, accountKey: String)] {
        try journal.allSessionsAwaitingQueue()
    }

    /// When the session's `workout_completed` happened, so a recovery after a
    /// relaunch ends the HealthKit workout at that time and not at launch time.
    public static func completedAt(sessionId: String, journal: WatchJournal) throws -> Date? {
        for case .workoutCompleted(let header) in try journal.events(sessionId: sessionId) {
            return WatchTimestamp.date(header.occurredAtUtc)
        }
        return nil
    }

    public static func queuePendingFinish(
        sessionId: String, journal: WatchJournal, unit: String? = nil, accountKey: String,
        healthkitWorkoutUuid: String?, makeId: () -> String, clock: () -> Date
    ) throws {
        if try journal.delivery(sessionId: sessionId) != nil { return }
        guard let json = try journal.template(sessionId: sessionId),
            let template = try? JSONDecoder().decode(WorkoutTemplate.self, from: Data(json.utf8))
        else { throw JournalError.unknownSession }
        let events = try journal.events(sessionId: sessionId)
        // Without a unit, use the one the session logged its sets in: a
        // recovery for another account must not borrow the bound account's.
        var logged: String?
        for case .setLogged(_, let values) in events { logged = logged ?? values.inputUnit }
        let message = try CompletedWorkoutBuilder.message(
            events: events, template: template, unit: unit ?? logged ?? "kg",
            accountKey: accountKey, healthkitWorkoutUuid: healthkitWorkoutUuid, messageId: makeId(),
            sentAtUtc: ISO8601DateFormatter().string(from: clock()))
        try journal.queueCompleted(message, sessionId: sessionId)
    }
}

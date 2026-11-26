import Foundation

public struct ReplayedSet: Equatable, Codable {
    public var setId: String
    /// `completed` or `skipped`.
    public var status: String
    /// `working` or `warmup`.
    public var kind: String
    public var reps: Int?
    public var durationSeconds: Int?
    public var loadGrams: Int?
    public var rpe: Double?
    /// Every event id that touched this set, in sequence order.
    public var history: [String]
}

public struct ReplayedWorkout: Equatable, Codable {
    /// `active`, `paused`, `completed` or `abandoned`.
    public var status: String
    public var sets: [ReplayedSet]
    /// Sum of reps x load over completed working sets with reps and a load.
    public var volumeGrams: Int
    /// Completed working sets (reps or seconds). Warm-ups are not counted.
    public var completedSets: Int
    /// Sequence numbers from 0 to the highest seen that never arrived.
    public var gaps: [Int]
}

/// Rebuilds a workout from its events. Duplicates (same `event_id`) are
/// dropped, order is by `sequence` whatever the delivery order, and missing
/// sequence numbers are reported in `gaps` instead of being invented. Rules
/// are in `contracts/watch_link/v1/README.md`.
public func replay(_ events: [WorkoutEventV2]) -> ReplayedWorkout {
    var seen = Set<String>()
    var unique: [(index: Int, event: WorkoutEventV2)] = []
    for (index, event) in events.enumerated() where seen.insert(event.header.eventId).inserted {
        unique.append((index, event))
    }
    unique.sort {
        $0.event.header.sequence != $1.event.header.sequence
            ? $0.event.header.sequence < $1.event.header.sequence
            : $0.index < $1.index
    }
    let present = Set(unique.map { $0.event.header.sequence })
    var gaps: [Int] = []
    if let highest = present.max() {
        gaps = (0...highest).filter { !present.contains($0) }
    }

    var status = "active"
    var order: [String] = []
    var sets: [String: ReplayedSet] = [:]

    func touch(_ setId: String, kind: String) -> ReplayedSet {
        if let existing = sets[setId] { return existing }
        order.append(setId)
        return ReplayedSet(setId: setId, status: "completed", kind: kind, history: [])
    }

    for (_, event) in unique {
        let eventId = event.header.eventId
        switch event {
        case .workoutPaused: status = "paused"
        case .workoutResumed: status = "active"
        case .workoutCompleted: status = "completed"
        case .workoutAbandoned: status = "abandoned"
        case .setLogged(_, let values), .setCorrected(_, let values, _):
            var set = touch(values.setId, kind: values.kind)
            set.status = "completed"
            set.kind = values.kind
            set.reps = values.reps
            set.durationSeconds = values.durationSeconds
            set.loadGrams = values.loadGrams
            set.rpe = values.rpe
            set.history.append(eventId)
            sets[values.setId] = set
        case .setSkipped(_, let setId):
            var set = touch(setId, kind: "working")
            set.status = "skipped"
            set.reps = nil
            set.durationSeconds = nil
            set.loadGrams = nil
            set.rpe = nil
            set.history.append(eventId)
            sets[setId] = set
        case .workoutStarted, .exerciseAdded, .restStarted, .restCleared, .platformWorkoutExported:
            break
        }
    }

    var volume = 0
    var done = 0
    let ordered = order.compactMap { sets[$0] }
    for set in ordered where set.status == "completed" && set.kind == "working" {
        done += 1
        if let reps = set.reps, let load = set.loadGrams, load > 0 { volume += reps * load }
    }
    return ReplayedWorkout(status: status, sets: ordered, volumeGrams: volume, completedSets: done, gaps: gaps)
}

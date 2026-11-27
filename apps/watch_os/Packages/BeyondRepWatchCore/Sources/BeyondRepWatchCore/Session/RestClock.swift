import Foundation

/// The rest countdown, derived from the journal's events so it survives a
/// relaunch: no timer state is stored anywhere else.
public enum RestClock {
    /// The deadline of the highest-sequence `rest_started`, unless a later
    /// `rest_cleared`, `set_logged`, `workout_paused`, `workout_completed` or
    /// `workout_abandoned` ended it.
    public static func deadline(events: [WorkoutEventV2]) -> Date? {
        var deadline: Date?
        for event in events.sorted(by: { $0.header.sequence < $1.header.sequence }) {
            switch event {
            case .restStarted(_, _, let deadlineUtc):
                deadline = WatchTimestamp.date(deadlineUtc)
            case .restCleared, .setLogged, .workoutPaused, .workoutCompleted, .workoutAbandoned:
                deadline = nil
            default:
                break
            }
        }
        return deadline
    }

    /// Seconds for a new rest that adds 30 s to what remains, 1 to 3600.
    public static func extendedSeconds(remaining: TimeInterval) -> Int {
        min(3600, max(1, Int(remaining.rounded(.up)) + 30))
    }
}

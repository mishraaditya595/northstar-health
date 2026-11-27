import Foundation

/// Decides what a launch does with a HealthKit workout session that no
/// journal session explains (the app died between ending the journal session
/// and ending HealthKit, for example a discard). HealthKit keeps such a
/// session alive and it would run on the watch for hours.
public enum OrphanSessionPolicy {
    /// True when the recovered HealthKit session may be ended and discarded:
    /// no active or paused session was restored for it, and no finished
    /// workout is still waiting to save its `HKWorkout` from it (a failed
    /// lookup or an unbound account leaves the question open, so nothing is
    /// thrown away).
    public static func shouldDiscard(restoredSession: Bool, unresolvedPendingFinish: Bool) -> Bool {
        !restoredSession && !unresolvedPendingFinish
    }
}

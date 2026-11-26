import Foundation

/// Namespace and version constants for the watch core (ADR-0012). This package
/// imports only Foundation and SQLite so `swift test` runs on a Mac without a
/// watch simulator.
public enum BeyondRepWatchCore {
    /// `contracts/workout_sync/v2` envelope version.
    public static let workoutSyncSchemaVersion = 2
    /// `contracts/watch_link/v1` message version.
    public static let watchLinkSchemaVersion = 1
}

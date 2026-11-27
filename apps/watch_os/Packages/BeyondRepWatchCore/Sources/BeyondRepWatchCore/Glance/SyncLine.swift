import Foundation

/// The status line at the top of the watch Home. The watch only knows when it
/// last stored phone data; "synced" never claims more than that.
public enum SyncLine: Equatable {
    /// Nothing bound, or nothing received yet.
    case notPaired
    /// Phone reachable; the String is the short local time of the last data.
    case synced(String)
    /// Phone not reachable; data stays and is dated.
    case phoneAway(String)

    public static func make(
        journal: WatchJournal, isPhoneReachable: Bool, now: Date, timeZone: TimeZone, locale: Locale
    ) throws -> SyncLine {
        guard try journal.binding() != nil, let ms = try journal.lastReceivedMs() else { return .notPaired }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
        return isPhoneReachable ? .synced(time) : .phoneAway(time)
    }
}

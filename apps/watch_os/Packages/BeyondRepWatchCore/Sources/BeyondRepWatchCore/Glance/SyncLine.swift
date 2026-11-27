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
        let received = Date(timeIntervalSince1970: Double(ms) / 1000)
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        let text =
            "\(dayLabel(received, now: now, timeZone: timeZone, locale: locale)) \(time.string(from: received))"
        return isPhoneReachable ? .synced(text) : .phoneAway(text)
    }

    /// "Today", "Yesterday", a weekday for the last 6 days, then "10 Oct": a
    /// bare time or weekday would read as the wrong day.
    private static func dayLabel(_ date: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = days <= 6 ? "EEE" : "d MMM"
        return formatter.string(from: date)
    }
}

import Foundation

/// Today's sleep, HRV and resting heart rate from raw HealthKit samples, with
/// the phone's day rules: a port of `buildNights` and `mergedSleepMinutes`
/// (`sleep_nights.dart`), `hrvDailyOf` (`health_overview.dart`) and
/// `reduceDaily(.latest)` (`daily_series.dart`). The golden cases in
/// `contracts/watch_link/v1/cases/health/` run through both, so the two give
/// the same numbers. Only the numbers the watch shows are derived: stage
/// minutes, in-bed time and the sleep score stay on the phone.
public enum WatchHealthDerivation {
    private static let sessionGap: TimeInterval = 60 * 60
    private static let asleepStages: Set<SleepStage> = [.light, .deep, .rem, .asleepUnspecified]

    /// Steps arrive already summed by HealthKit; 0 (or a non-finite or
    /// negative total) is missing, as on the phone's iOS reads.
    public static func today(
        sleep: [SleepSample], hrv: [ValueSample], restingHr: [ValueSample], steps: Double?, now: Date,
        timeZone: TimeZone
    ) -> WatchHealth {
        let calendar = LocalDay.calendar(timeZone)
        let today = LocalDay.string(now, calendar: calendar)
        let nights = buildNights(sleep, calendar: calendar)
        return WatchHealth(
            localDate: today,
            asleepMinutes: nights[today]?.asleep.nonZero,
            restingHrBpm: latest(restingHr, on: today, calendar: calendar).flatMap(rounded),
            hrvMs: hrvOf(hrv, on: today, nights: nights, calendar: calendar).flatMap(rounded),
            steps: steps.flatMap(rounded).flatMap { $0 > 0 ? $0 : nil })
    }

    /// Dart's `.round()`: half away from zero.
    private static func rounded(_ value: Double) -> Int? {
        value.isFinite ? Int(value.rounded(.toNearestOrAwayFromZero)) : nil
    }

    // MARK: Sleep

    /// One source's main sleep, keyed by the local date it ended on.
    private struct Night {
        let start: Date
        let end: Date
        let date: String
        let asleep: Int
        /// Merged deep + rem + light minutes.
        let staged: Int
    }

    /// Whole minutes covered by the segments, counting overlaps once.
    static func mergedMinutes(_ segments: [(from: Date, to: Date)]) -> Int {
        var total: TimeInterval = 0
        var start: Date?
        var end: Date?
        for s in segments.sorted(by: { $0.from < $1.from }) {
            if s.to <= s.from { continue }
            if let currentEnd = end, s.from <= currentEnd {
                if s.to > currentEnd { end = s.to }
            } else {
                if let start, let end { total += end.timeIntervalSince(start) }
                start = s.from
                end = s.to
            }
        }
        if let start, let end { total += end.timeIntervalSince(start) }
        return Int(total / 60)
    }

    /// A run of asleep segments with no gap over 60 minutes. Awake and in-bed
    /// segments are not tracked: they never change the asleep minutes.
    private struct Session {
        var start: Date
        var end: Date
        var asleep: [SleepSample]
    }

    private static func splitSessions(_ samples: [SleepSample]) -> [Session] {
        var sessions: [Session] = []
        for s in samples.filter({ asleepStages.contains($0.stage) }).sorted(by: { $0.from < $1.from }) {
            if var current = sessions.last, s.from.timeIntervalSince(current.end) <= sessionGap {
                current.asleep.append(s)
                if s.to > current.end { current.end = s.to }
                sessions[sessions.count - 1] = current
            } else {
                sessions.append(Session(start: s.from, end: s.to, asleep: [s]))
            }
        }
        return sessions
    }

    /// A session ending before 03:00 is a nap or a late-evening start unless
    /// it crosses a date.
    private static func isMainSleepCandidate(_ s: Session, calendar: Calendar) -> Bool {
        calendar.component(.hour, from: s.end) >= 3
            || LocalDay.string(s.end, calendar: calendar) > LocalDay.string(s.start, calendar: calendar)
    }

    private static func night(_ s: Session, calendar: Calendar) -> Night {
        func minutes(_ stage: SleepStage) -> Int {
            mergedMinutes(s.asleep.filter { $0.stage == stage }.map { (from: $0.from, to: $0.to) })
        }
        return Night(
            start: s.start, end: s.end, date: LocalDay.string(s.end, calendar: calendar),
            asleep: mergedMinutes(s.asleep.map { (from: $0.from, to: $0.to) }),
            staged: minutes(.deep) + minutes(.rem) + minutes(.light))
    }

    /// At most one night per local date. Per source the longest candidate of
    /// a date wins (the first on a tie); across sources the one with most
    /// deep + rem + light, then most asleep, then the smaller source key.
    private static func buildNights(_ samples: [SleepSample], calendar: Calendar) -> [String: Night] {
        var bySource: [String: [SleepSample]] = [:]
        for s in samples { bySource[s.sourceKey, default: []].append(s) }
        var byDate: [String: (key: String, night: Night)] = [:]
        for key in bySource.keys.sorted() {
            var perDate: [String: Night] = [:]
            for session in splitSessions(bySource[key] ?? []) where isMainSleepCandidate(session, calendar: calendar) {
                let n = night(session, calendar: calendar)
                if let kept = perDate[n.date], n.asleep <= kept.asleep { continue }
                perDate[n.date] = n
            }
            for n in perDate.values {
                if let kept = byDate[n.date], !beats(n, key, kept.night, kept.key) { continue }
                byDate[n.date] = (key, n)
            }
        }
        return byDate.mapValues { $0.night }
    }

    private static func beats(_ a: Night, _ aKey: String, _ b: Night, _ bKey: String) -> Bool {
        if a.staged != b.staged { return a.staged > b.staged }
        if a.asleep != b.asleep { return a.asleep > b.asleep }
        return aKey < bKey
    }

    // MARK: Heart

    /// The newest sample (by end time) ending on [day]; the first one on a tie.
    private static func latest(_ samples: [ValueSample], on day: String, calendar: Calendar) -> Double? {
        var best: ValueSample?
        for s in samples where LocalDay.string(s.to, calendar: calendar) == day {
            if let current = best, s.to <= current.to { continue }
            best = s
        }
        return best?.value
    }

    /// The mean of the samples inside that day's night, else the mean of the
    /// day's samples outside any night.
    private static func hrvOf(
        _ samples: [ValueSample], on day: String, nights: [String: Night], calendar: Calendar
    ) -> Double? {
        let ordered = nights.values.sorted { $0.date < $1.date }
        var overnight: [Double] = []
        var daytime: [Double] = []
        for s in samples {
            if let n = ordered.first(where: { s.from >= $0.start && s.to <= $0.end }) {
                if n.date == day { overnight.append(s.value) }
            } else if LocalDay.string(s.to, calendar: calendar) == day {
                daytime.append(s.value)
            }
        }
        let chosen = overnight.isEmpty ? daytime : overnight
        return chosen.isEmpty ? nil : chosen.reduce(0, +) / Double(chosen.count)
    }
}

private extension Int {
    /// A total of 0 minutes is missing, not "0m".
    var nonZero: Int? { self > 0 ? self : nil }
}

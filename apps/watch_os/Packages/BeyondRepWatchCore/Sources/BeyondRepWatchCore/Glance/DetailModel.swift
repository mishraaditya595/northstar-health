import Foundation

public struct DayPoint: Equatable {
    public let date: Date
    /// One-letter weekday ("M").
    public let label: String
    /// Nil for a day the phone sent no value for; never 0 for missing.
    public let value: Int?
    public let isToday: Bool

    public init(date: Date, label: String, value: Int?, isToday: Bool) {
        self.date = date
        self.label = label
        self.value = value
        self.isToday = isToday
    }
}

public struct SleepStages: Equatable {
    public let deep: Int
    public let core: Int
    public let rem: Int
    public let awake: Int

    public init(deep: Int, core: Int, rem: Int, awake: Int) {
        self.deep = deep
        self.core = core
        self.rem = rem
        self.awake = awake
    }
}

/// One metric's detail screen: today, the phone's usual and the 7 days ending
/// today, all from today's `health_snapshot`. Nothing is computed beyond the
/// week average; the phone wrote every number.
public struct DetailModel: Equatable {
    public let title: String
    public let value: String
    public let unit: String?
    public let caption: String?
    public let usual: Int?
    /// Always 7 days ending today, oldest first.
    public let week: [DayPoint]
    /// Only when the snapshot has all four stage keys.
    public let stages: SleepStages?
    /// Mean of the days with a value, rounded; nil when none has one.
    public let weekAverage: Int?

    public init(
        title: String, value: String, unit: String?, caption: String?, usual: Int?, week: [DayPoint],
        stages: SleepStages?, weekAverage: Int?
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.caption = caption
        self.usual = usual
        self.week = week
        self.stages = stages
        self.weekAverage = weekAverage
    }

    /// Nil when nothing is bound or there is no snapshot for today's local
    /// date, so yesterday's week is never shown.
    public static func make(
        metric: Metric, journal: WatchJournal, now: Date, timeZone: TimeZone, locale: Locale
    ) throws -> DetailModel? {
        let calendar = LocalDay.calendar(timeZone)
        let today = LocalDay.string(now, calendar: calendar)
        try journal.purgeHealth(exceptLocalDate: today)
        guard let binding = try journal.binding(),
            let message = try journal.health(accountKey: binding.accountKey, forLocalDate: today),
            case .healthSnapshot(_, let raw) = message.body
        else { return nil }

        func int(_ value: Any?) -> Int? { (value as? NSNumber).map { $0.intValue } }
        let sleep = raw["sleep"] as? [String: Any]
        let info: (title: String, unit: String?, weekKey: String, top: Int?, usual: Int?)
        switch metric {
        case .sleep:
            info = ("Sleep", nil, "asleep_minutes", int(sleep?["asleep_minutes"]), nil)
        case .restingHr:
            info = (
                "Resting HR", "bpm", "resting_hr_bpm", int(raw["resting_hr_bpm"]), int(raw["resting_hr_usual_bpm"])
            )
        case .hrv:
            info = ("HRV", "ms", "hrv_ms", int(raw["hrv_ms"]), int(raw["hrv_usual_ms"]))
        case .steps:
            info = ("Steps", nil, "steps", int(raw["steps"]), nil)
        }

        let (title, unit, weekKey, top, usual) = info

        var days: [String: [String: Any]] = [:]
        for case let day as [String: Any] in raw["week"] as? [Any] ?? [] {
            if let date = day["local_date"] as? String { days[date] = day }
        }
        let labeler = DateFormatter()
        labeler.calendar = calendar
        labeler.locale = locale
        labeler.timeZone = timeZone
        labeler.dateFormat = "EEEEE"
        let startOfToday = calendar.startOfDay(for: now)
        var week: [DayPoint] = []
        for back in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -back, to: startOfToday) else { continue }
            let key = LocalDay.string(date, calendar: calendar)
            var value = int(days[key]?[weekKey])
            if value == nil, back == 0 { value = top }
            week.append(DayPoint(date: date, label: labeler.string(from: date), value: value, isToday: back == 0))
        }

        let present = week.compactMap { $0.value }
        let average = present.isEmpty
            ? nil : Int((Double(present.reduce(0, +)) / Double(present.count)).rounded())

        let shown = top ?? week.last?.value
        let value: String
        if let shown {
            switch metric {
            case .sleep: value = GlanceState.sleepText(minutes: shown)
            case .steps:
                let count = NumberFormatter()
                count.locale = locale
                count.numberStyle = .decimal
                value = count.string(from: NSNumber(value: shown)) ?? String(shown)
            default: value = String(shown)
            }
        } else {
            value = GlanceState.missing
        }

        var caption: String?
        switch metric {
        case .sleep: caption = int(sleep?["score"]).map { "Score \($0)" }
        case .restingHr, .hrv: caption = usual.map { "Usual \($0) \(unit ?? "")" }
        case .steps: caption = "So far today"
        }

        var stages: SleepStages?
        if let sleep, let deep = int(sleep["deep_minutes"]), let core = int(sleep["core_minutes"]),
            let rem = int(sleep["rem_minutes"]), let awake = int(sleep["awake_minutes"]), metric == .sleep
        {
            stages = SleepStages(deep: deep, core: core, rem: rem, awake: awake)
        }

        return DetailModel(
            title: title, value: value, unit: unit, caption: caption, usual: usual, week: week, stages: stages,
            weekAverage: average)
    }
}

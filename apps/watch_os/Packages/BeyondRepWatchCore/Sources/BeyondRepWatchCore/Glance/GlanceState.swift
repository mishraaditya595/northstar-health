import Foundation

public struct ReadinessLine: Equatable {
    public let score: Int
    public let band: String
    public let headline: String
}

/// How a status line is coloured. The phone decides it for readiness factors;
/// the watch decides it for the tile lines below.
public enum Tone: String, Equatable {
    case good, neutral, caution
}

/// The four health tiles; also the key for a detail screen.
public enum Metric: Equatable {
    case sleep, restingHr, hrv, steps
}

public struct GlanceTile: Equatable {
    public let label: String
    public let value: String
    public let unit: String?
    /// One coloured line under the value ("Score 90", "−2 vs usual"); nil when
    /// the phone sent nothing to compare with.
    public let status: String?
    public let tone: Tone
    public let metric: Metric

    public init(label: String, value: String, unit: String?, status: String?, tone: Tone, metric: Metric) {
        self.label = label
        self.value = value
        self.unit = unit
        self.status = status
        self.tone = tone
        self.metric = metric
    }
}

public struct PlanRow: Equatable {
    public let id: String
    public let name: String
    /// "6 exercises" for today's program workout, nil when the count is unknown or zero.
    public let subtitle: String?
    public let exerciseCount: Int

    public init(id: String, name: String, subtitle: String? = nil, exerciseCount: Int = 0) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.exerciseCount = exerciseCount
    }
}

public struct Glance: Equatable {
    /// One readiness input with the phone's wording.
    public struct Factor: Equatable {
        public let input: String
        public let status: String
        public let tone: Tone

        public init(input: String, status: String, tone: Tone) {
            self.input = input
            self.status = status
            self.tone = tone
        }
    }

    public let readiness: ReadinessLine?
    /// The phone's one-line reason under the readiness headline.
    public let readinessReason: String?
    public let factors: [Factor]
    public let tiles: [GlanceTile]
    public let caption: String
    public let today: PlanRow?
    public let plans: [PlanRow]
}

/// What the Home screen shows, computed from the journal. Only values the
/// phone sent are shown; missing is "—", never 0, and health from another
/// local date is never shown.
public enum GlanceState: Equatable {
    case notPaired
    case ready(Glance)

    public static let missing = "—"
    public static let refreshCaption = "Open BeyondRep on your iPhone to refresh"

    public static func make(journal: WatchJournal, now: Date, timeZone: TimeZone, locale: Locale) throws -> GlanceState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let today = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)

        // Health values end at local midnight (ADR-0012), also when nothing
        // is paired.
        try journal.purgeHealth(exceptLocalDate: today)
        guard let binding = try journal.binding() else { return .notPaired }
        let key = binding.accountKey

        var plans: [PlanRow] = []
        var todayRow: PlanRow?
        if let message = try journal.plans(accountKey: key), case .plansSnapshot(let raw) = message.body {
            for case let plan as [String: Any] in raw["plans"] as? [Any] ?? [] {
                if let id = plan["plan_id"] as? String, let name = plan["name"] as? String {
                    plans.append(PlanRow(id: id, name: name, exerciseCount: (plan["exercises"] as? [Any])?.count ?? 0))
                }
            }
            if let t = raw["today"] as? [String: Any], t["local_date"] as? String == today,
                let id = t["plan_id"] as? String, let label = t["label"] as? String
            {
                // The snapshot carries no week or day of the program, so the
                // subtitle is the exercise count of the plan, when known.
                let count = plans.first { $0.id == id }?.exerciseCount ?? 0
                todayRow = PlanRow(
                    id: id, name: label,
                    subtitle: count == 0 ? nil : (count == 1 ? "1 exercise" : "\(count) exercises"),
                    exerciseCount: count)
                // Shown as Today, so not listed again below.
                plans.removeAll { $0.id == id }
            }
        }

        guard let health = try journal.health(accountKey: key, forLocalDate: today),
            case .healthSnapshot(_, let raw) = health.body
        else {
            return .ready(Glance(
                readiness: nil, readinessReason: nil, factors: [], tiles: tiles(nil, locale: locale),
                caption: refreshCaption, today: todayRow, plans: plans))
        }

        var readiness: ReadinessLine?
        var reason: String?
        var factors: [Glance.Factor] = []
        if let r = raw["readiness"] as? [String: Any], let score = (r["score"] as? NSNumber)?.intValue,
            let band = r["band"] as? String, let headline = r["headline"] as? String
        {
            readiness = ReadinessLine(score: score, band: band, headline: headline)
            reason = r["reason"] as? String
            for case let f as [String: Any] in r["factors"] as? [Any] ?? [] {
                if let input = f["input"] as? String, let status = f["status"] as? String,
                    let tone = (f["tone"] as? String).flatMap(Tone.init(rawValue:))
                {
                    factors.append(Glance.Factor(input: input, status: status, tone: tone))
                }
            }
        }

        var caption = refreshCaption
        if let asOf = raw["as_of_utc"] as? String, let date = parseDate(asOf) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            caption = "as of " + formatter.string(from: date)
        }
        return .ready(Glance(
            readiness: readiness, readinessReason: reason, factors: factors, tiles: tiles(raw, locale: locale),
            caption: caption, today: todayRow, plans: plans))
    }

    private static func parseDate(_ text: String) -> Date? {
        WatchTimestamp.date(text)
    }

    /// "7h 12m", or "45m" under an hour.
    static func sleepText(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// "−2 vs usual" (U+2212 minus) or "+2 vs usual", and whether it is better.
    /// Nothing without both numbers; the phone's baseline is the only "usual".
    private static func versusUsual(_ value: Int?, _ usual: Int?, betterWhenHigher: Bool) -> (String?, Tone) {
        guard let value, let usual else { return (nil, .neutral) }
        let diff = value - usual
        if diff == 0 { return ("same as usual", .neutral) }
        let text = (diff < 0 ? "\u{2212}" : "+") + "\(abs(diff)) vs usual"
        return (text, (betterWhenHigher ? diff > 0 : diff < 0) ? .good : .neutral)
    }

    private static func tiles(_ raw: [String: Any]?, locale: Locale) -> [GlanceTile] {
        func int(_ value: Any?) -> Int? { (value as? NSNumber).map { $0.intValue } }
        let count = NumberFormatter()
        count.locale = locale
        count.numberStyle = .decimal

        var sleepValue = missing
        var sleepStatus: String?
        if let sleep = raw?["sleep"] as? [String: Any] {
            if let minutes = int(sleep["asleep_minutes"]) { sleepValue = sleepText(minutes: minutes) }
            if let score = int(sleep["score"]) { sleepStatus = "Score \(score)" }
        }
        let rhr = int(raw?["resting_hr_bpm"])
        let hrv = int(raw?["hrv_ms"])
        let steps = int(raw?["steps"])
        let rhrLine = versusUsual(rhr, int(raw?["resting_hr_usual_bpm"]), betterWhenHigher: false)
        let hrvLine = versusUsual(hrv, int(raw?["hrv_usual_ms"]), betterWhenHigher: true)
        return [
            GlanceTile(
                label: "Sleep", value: sleepValue, unit: nil, status: sleepStatus,
                tone: sleepStatus == nil ? .neutral : .good, metric: .sleep),
            GlanceTile(
                label: "Resting HR", value: rhr.map(String.init) ?? missing, unit: rhr == nil ? nil : "bpm",
                status: rhrLine.0, tone: rhrLine.1, metric: .restingHr),
            GlanceTile(
                label: "HRV", value: hrv.map(String.init) ?? missing, unit: hrv == nil ? nil : "ms",
                status: hrvLine.0, tone: hrvLine.1, metric: .hrv),
            GlanceTile(
                label: "Steps", value: steps.flatMap { count.string(from: NSNumber(value: $0)) } ?? missing,
                unit: nil, status: steps == nil ? nil : "today", tone: .neutral, metric: .steps),
        ]
    }
}

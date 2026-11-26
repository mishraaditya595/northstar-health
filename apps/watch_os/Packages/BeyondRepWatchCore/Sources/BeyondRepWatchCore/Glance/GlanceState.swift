import Foundation

public struct ReadinessLine: Equatable {
    public let score: Int
    public let band: String
    public let headline: String
}

public struct GlanceTile: Equatable {
    public let label: String
    public let value: String
    public let unit: String?

    public init(label: String, value: String, unit: String?) {
        self.label = label
        self.value = value
        self.unit = unit
    }
}

public struct PlanRow: Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Glance: Equatable {
    public let readiness: ReadinessLine?
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
        guard let binding = try journal.binding() else { return .notPaired }
        let key = binding.accountKey

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let today = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)

        var plans: [PlanRow] = []
        var todayRow: PlanRow?
        if let message = try journal.plans(accountKey: key), case .plansSnapshot(let raw) = message.body {
            for case let plan as [String: Any] in raw["plans"] as? [Any] ?? [] {
                if let id = plan["plan_id"] as? String, let name = plan["name"] as? String {
                    plans.append(PlanRow(id: id, name: name))
                }
            }
            if let t = raw["today"] as? [String: Any], t["local_date"] as? String == today,
                let id = t["plan_id"] as? String, let label = t["label"] as? String
            {
                todayRow = PlanRow(id: id, name: label)
            }
        }

        guard let health = try journal.health(accountKey: key, forLocalDate: today),
            case .healthSnapshot(_, let raw) = health.body
        else {
            return .ready(Glance(
                readiness: nil, tiles: tiles(nil, locale: locale), caption: refreshCaption,
                today: todayRow, plans: plans))
        }

        var readiness: ReadinessLine?
        if let r = raw["readiness"] as? [String: Any], let score = (r["score"] as? NSNumber)?.intValue,
            let band = r["band"] as? String, let headline = r["headline"] as? String
        {
            readiness = ReadinessLine(score: score, band: band, headline: headline)
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
            readiness: readiness, tiles: tiles(raw, locale: locale), caption: caption,
            today: todayRow, plans: plans))
    }

    private static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: text) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    private static func tiles(_ raw: [String: Any]?, locale: Locale) -> [GlanceTile] {
        func int(_ value: Any?) -> Int? { (value as? NSNumber).map { $0.intValue } }
        let count = NumberFormatter()
        count.locale = locale
        count.numberStyle = .decimal

        var sleepValue = missing
        var sleepUnit: String?
        if let sleep = raw?["sleep"] as? [String: Any] {
            if let minutes = int(sleep["asleep_minutes"]) {
                sleepValue = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
            }
            if let score = int(sleep["score"]) { sleepUnit = "score \(score)" }
        }
        let rhr = int(raw?["resting_hr_bpm"])
        let hrv = int(raw?["hrv_ms"])
        let steps = int(raw?["steps"])
        return [
            GlanceTile(label: "Sleep", value: sleepValue, unit: sleepUnit),
            GlanceTile(label: "Resting HR", value: rhr.map(String.init) ?? missing, unit: rhr == nil ? nil : "bpm"),
            GlanceTile(label: "HRV", value: hrv.map(String.init) ?? missing, unit: hrv == nil ? nil : "ms"),
            GlanceTile(
                label: "Steps", value: steps.flatMap { count.string(from: NSNumber(value: $0)) } ?? missing, unit: nil),
        ]
    }
}

#if DEBUG
import Foundation
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Synthetic values for the SwiftUI previews only. Nothing here is real data.
enum PreviewData {
    static let glance: GlanceState = .ready(
        Glance(
            readiness: ReadinessLine(score: 78, band: "good", headline: "Good to train"),
            readinessReason: "HRV above your normal · slept 7h 12m",
            factors: [
                Glance.Factor(input: "sleep", status: "Slept 7h 12m", tone: .good),
                Glance.Factor(input: "hrv", status: "Above usual", tone: .good),
                Glance.Factor(input: "resting_hr", status: "Below usual", tone: .good),
                Glance.Factor(input: "training_load", status: "Normal", tone: .neutral),
            ],
            tiles: [
                GlanceTile(label: "Sleep", value: "7h 12m", unit: nil, status: "Score 90", tone: .good, metric: .sleep),
                GlanceTile(
                    label: "Resting HR", value: "61", unit: "bpm", status: "\u{2212}2 vs usual", tone: .good,
                    metric: .restingHr),
                GlanceTile(label: "HRV", value: "48", unit: "ms", status: "+6 vs usual", tone: .good, metric: .hrv),
                GlanceTile(label: "Steps", value: "4,210", unit: nil, status: "today", tone: .neutral, metric: .steps),
            ],
            caption: "as of 10:30 AM",
            today: PlanRow(id: "plan-1", name: "Pull day", subtitle: "6 exercises", exerciseCount: 6),
            plans: [
                PlanRow(id: "plan-0", name: "Push day", exerciseCount: 5),
                PlanRow(id: "plan-2", name: "Leg day", exerciseCount: 7),
            ]))

    static var emptyPlans: Glance {
        guard case .ready(let g) = glance else { fatalError("preview glance") }
        return Glance(
            readiness: g.readiness, readinessReason: g.readinessReason, factors: g.factors, tiles: g.tiles,
            caption: g.caption, today: nil, plans: [])
    }

    private static func week(_ values: [Int?]) -> [DayPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let today = calendar.startOfDay(for: Date())
        let labeler = DateFormatter()
        labeler.dateFormat = "EEEEE"
        return values.enumerated().map { index, value in
            let back = values.count - 1 - index
            let date = calendar.date(byAdding: .day, value: -back, to: today)!
            return DayPoint(date: date, label: labeler.string(from: date), value: value, isToday: back == 0)
        }
    }

    static func detail(_ metric: Metric) -> DetailModel {
        switch metric {
        case .sleep:
            return DetailModel(
                title: "Sleep", value: "7h 12m", unit: nil, caption: "Score 90", usual: nil,
                week: week([412, 398, 455, nil, 430, 441, 432]),
                stages: SleepStages(deep: 80, core: 220, rem: 95, awake: 18), weekAverage: 428)
        case .restingHr:
            return DetailModel(
                title: "Resting HR", value: "61", unit: "bpm", caption: "Usual 63 bpm", usual: 63,
                week: week([64, 63, 65, 62, nil, 63, 61]), stages: nil, weekAverage: 63)
        case .hrv:
            return DetailModel(
                title: "HRV", value: "48", unit: "ms", caption: "Usual 42 ms", usual: 42,
                week: week([38, 41, 44, 40, 43, nil, 48]), stages: nil, weekAverage: 42)
        case .steps:
            return DetailModel(
                title: "Steps", value: "4,210", unit: nil, caption: "So far today", usual: nil,
                week: week([8120, 9040, 10110, 6020, 7300, 11200, 4210]), stages: nil, weekAverage: 8000)
        }
    }
}
#endif

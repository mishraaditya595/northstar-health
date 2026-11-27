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

#if DEBUG
extension PreviewData {
    private static let accountKey = String(repeating: "0123456789abcdef", count: 4)

    private static var plansRaw: [String: Any] {
        [
            "generated_at_utc": "2026-10-23T01:00:00Z",
            "plans": [
                [
                    "plan_id": "plan-preview", "name": "Push day",
                    "exercises": [
                        [
                            "exercise_id": "builtin.v1.preview-press", "name": "Bench press", "kind": "reps",
                            "muscle": "chest",
                            "sets": [
                                ["position": 0, "kind": "working", "target_reps": 8, "target_load_grams": 60000],
                                ["position": 1, "kind": "working", "target_reps": 8, "target_load_grams": 60000],
                                ["position": 2, "kind": "working", "target_reps": 8, "target_load_grams": 60000],
                            ],
                        ],
                        [
                            "exercise_id": "builtin.v1.preview-plank", "name": "Plank", "kind": "duration",
                            "sets": [["position": 0, "kind": "working", "target_seconds": 45]],
                        ],
                    ],
                ]
            ],
            "recent_exercises": [] as [Any],
        ]
    }

    /// A model with a running workout: `sets` logged, optionally still resting.
    /// Uses a throwaway journal file; nothing here is real data.
    @MainActor
    static func workoutModel(sets: Int, resting: Bool, finished: Bool = false) -> (AppModel, WorkoutController) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).sqlite")
        let model = AppModel(journalURL: url)
        // A second connection writes the binding and plans the model reads.
        let journal = try! WatchJournal(url: url)
        try! journal.saveBinding(
            WatchMessage(
                messageId: UUID().uuidString.lowercased(), sentAtUtc: "2026-10-23T01:00:00Z", accountKey: accountKey,
                body: .accountBinding(unit: "kg")))
        try! journal.savePlans(
            WatchMessage(
                messageId: UUID().uuidString.lowercased(), sentAtUtc: "2026-10-23T01:00:00Z", accountKey: accountKey,
                body: .plansSnapshot(raw: plansRaw)))
        let template = WorkoutTemplate.fromPlan(
            plansSnapshot: plansRaw, planId: "plan-preview", makeId: { UUID().uuidString.lowercased() })!
        let controller = try! WorkoutController.start(
            template: template, journal: journal, accountKey: accountKey, unit: "kg",
            deviceId: "watch-preview", clock: Date.init, timeZone: TimeZone.current.identifier,
            makeId: { UUID().uuidString.lowercased() })
        for _ in 0..<sets {
            guard let position = controller.cursor.current else { break }
            try! controller.log(controller.cursor.prefill(for: position, unit: "kg"))
        }
        if !resting { try? controller.skipRest() }
        if finished { try? controller.markCompleted() }
        model.attachPreview(workout: controller)
        return (model, controller)
    }

    static let summary = WorkoutSummary(
        name: "Push day", elapsed: 2_715, sets: 9, averageHeartRate: 112, sessionId: "preview-session")
}
#endif

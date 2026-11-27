import Foundation
@testable import BeyondRepWatchCore

/// Synthetic watch_link messages for the inbox and glance tests.
enum TestMessages {
    static let keyA = String(repeating: "0123456789abcdef", count: 4)
    static let keyB = String(repeating: "fedcba9876543210", count: 4)

    static func id() -> String { UUID().uuidString.lowercased() }

    static func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    static let t0 = "2026-10-23T01:00:00Z"

    static func binding(_ key: String = keyA, unit: String = "kg", at: String = t0) -> WatchMessage {
        WatchMessage(messageId: id(), sentAtUtc: at, accountKey: key, body: .accountBinding(unit: unit))
    }

    static func cleared(_ key: String = keyA, wipe: Bool = false, at: String = t0) -> WatchMessage {
        WatchMessage(messageId: id(), sentAtUtc: at, accountKey: key, body: .accountCleared(wipeUnsent: wipe))
    }

    static func plans(
        _ key: String = keyA, names: [String] = ["Synthetic push day"], today: (id: String, label: String, date: String)? = nil,
        exerciseCount: Int = 0
    ) -> WatchMessage {
        var raw: [String: Any] = [
            "generated_at_utc": "2026-10-23T01:00:00Z",
            "plans": names.enumerated().map { (i, name) -> [String: Any] in
                [
                    "plan_id": "plan-\(i)", "name": name,
                    "exercises": (0..<exerciseCount).map { n -> [String: Any] in
                        ["exercise_id": "ex-\(n)", "name": "Move \(n)", "kind": "reps", "sets": [] as [Any]]
                    },
                ]
            },
            "recent_exercises": [] as [Any],
        ]
        if let today {
            raw["today"] = [
                "plan_id": today.id, "program_id": "program-1", "local_date": today.date, "label": today.label,
            ]
        }
        return WatchMessage(
            messageId: id(), sentAtUtc: "2026-10-23T01:00:00Z", accountKey: key, body: .plansSnapshot(raw: raw))
    }

    /// `asOf` 2026-10-23T01:40:00Z is 07:10 on 2026-10-23 in Asia/Kolkata.
    static func health(
        _ key: String = keyA, localDate: String = "2026-10-23", asOf: String = "2026-10-23T01:40:00Z",
        extra: [String: Any]? = nil
    ) -> WatchMessage {
        var raw: [String: Any] = [
            "local_date": localDate, "as_of_utc": asOf,
            "readiness": ["score": 72, "band": "good", "headline": "Ready to train", "reason": "Synthetic reason."],
            "sleep": ["score": 81, "asleep_minutes": 432],
            "resting_hr_bpm": 54, "hrv_ms": 62, "hrv_kind": "rmssd", "steps": 1200,
        ]
        if let extra { for (k, v) in extra { raw[k] = v } }
        return WatchMessage(
            messageId: id(), sentAtUtc: "2026-10-23T01:45:00Z", accountKey: key,
            body: .healthSnapshot(localDate: localDate, raw: raw))
    }

    static func json(_ message: WatchMessage) throws -> String {
        String(decoding: try message.jsonData(), as: UTF8.self)
    }
}

#if DEBUG
import SwiftUI
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Synthetic data only: a state the iPhone could send.
enum FollowerPreviewData {
    static let accountKey = String(repeating: "0123456789abcdef", count: 4)

    static func state(resting: Bool) -> PhoneWorkoutState {
        let now = Date()
        let set1 = "11111111-1111-4111-8111-111111111111"
        let set2 = "22222222-2222-4222-8222-222222222222"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var raw: [String: Any] = [
            "owner": "phone", "session_id": "33333333-3333-4333-8333-333333333333", "status": "active",
            "name": "Push day", "started_at_utc": formatter.string(from: now.addingTimeInterval(-900)),
            "last_sequence": 3, "current_set_id": resting ? set2 : set1,
            "exercises": [
                [
                    "exercise_id": "44444444-4444-4444-8444-444444444444", "name": "Bench press", "kind": "reps",
                    "sets": [
                        ["set_id": set1, "position": 0, "kind": "working", "status": resting ? "completed" : "planned",
                         "input_unit": "kg", "reps": 8, "load_grams": 60000],
                        ["set_id": set2, "position": 1, "kind": "working", "status": "planned", "input_unit": "kg",
                         "reps": 8, "load_grams": 60000],
                    ],
                ]
            ],
        ]
        if resting { raw["rest_deadline_utc"] = formatter.string(from: now.addingTimeInterval(60)) }
        let message = WatchMessage(
            messageId: UUID().uuidString.lowercased(), sentAtUtc: formatter.string(from: now), accountKey: accountKey,
            body: .sessionState(sessionId: "33333333-3333-4333-8333-333333333333", raw: raw))
        return PhoneWorkoutState(message: message)!
    }
}

#Preview("Follower set") {
    FollowerPreviewHost(resting: false)
}

#Preview("Follower rest") {
    FollowerPreviewHost(resting: true)
}

private struct FollowerPreviewHost: View {
    let resting: Bool
    @StateObject private var model = AppModel(
        journalURL: FileManager.default.temporaryDirectory.appendingPathComponent("follower-\(UUID().uuidString).sqlite"))

    var body: some View {
        let state = FollowerPreviewData.state(resting: resting)
        let follower = FollowerSession(accountKey: FollowerPreviewData.accountKey, makeId: { UUID().uuidString })
        if resting {
            FollowerRestPage(model: model, follower: follower, state: state)
        } else {
            FollowerSetPage(model: model, recorder: model.recorder, follower: follower, state: state)
        }
    }
}
#endif

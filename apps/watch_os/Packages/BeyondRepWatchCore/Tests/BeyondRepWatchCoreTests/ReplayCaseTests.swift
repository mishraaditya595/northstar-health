import XCTest
@testable import BeyondRepWatchCore

final class ReplayCaseTests: XCTestCase {
    /// The replay result in the shape of a case's `expected` object.
    private func expectedShape(_ w: ReplayedWorkout) -> NSDictionary {
        let sets: [[String: Any]] = w.sets.map { s in
            var d: [String: Any] = ["set_id": s.setId, "status": s.status, "history": s.history]
            if let v = s.reps { d["reps"] = v }
            if let v = s.durationSeconds { d["duration_seconds"] = v }
            if let v = s.loadGrams { d["load_grams"] = v }
            if let v = s.rpe { d["rpe"] = v }
            return d
        }
        return [
            "status": w.status, "sets": sets, "volume_grams": w.volumeGrams,
            "completed_sets": w.completedSets, "gaps": w.gaps,
        ]
    }

    func testEveryReplayCaseMatches() throws {
        let files = try FixtureLoader.files(in: "contracts/watch_link/v1/cases/replay")
        XCTAssertGreaterThanOrEqual(files.count, 8)
        for file in files {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            let events = try (object?["events"] as? [Any] ?? []).map { try WorkoutEventV2(object: $0) }
            let expected = object?["expected"] as? NSDictionary
            XCTAssertEqual(expectedShape(replay(events)), expected, file.lastPathComponent)
        }
    }
}

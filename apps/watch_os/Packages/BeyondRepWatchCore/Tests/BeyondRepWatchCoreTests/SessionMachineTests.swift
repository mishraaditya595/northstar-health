import XCTest
@testable import BeyondRepWatchCore

final class SessionMachineTests: XCTestCase {
    private let key = String(repeating: "0123456789abcdef", count: 4)
    private let session = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let exercise = "builtin.v1.synthetic-move-1"

    private func makeMachine() -> SessionMachine {
        var tick = 0
        let base = Date(timeIntervalSince1970: 1_792_000_000)
        return SessionMachine(
            sessionId: session, owner: "watch", accountKey: key, deviceId: "watch-installation-a",
            clock: { tick += 1; return base.addingTimeInterval(TimeInterval(tick)) },
            timeZone: "Asia/Kolkata")
    }

    private func started() throws -> SessionMachine {
        var m = makeMachine()
        _ = try m.start(name: "Synthetic push day")
        return m
    }

    private func set(_ n: Int, reps: Int = 8, load: Int = 60000) -> SetValues {
        SetValues(
            setId: "dddddddd-dddd-4ddd-8ddd-00000000000\(n)", exerciseId: exercise, position: n,
            reps: reps, loadGrams: load)
    }

    func testSequenceIncreasesByOnePerEvent() throws {
        var m = makeMachine()
        var all = try m.start(
            name: "Synthetic push day",
            exercises: [ExerciseAddedPayload(exerciseId: exercise, name: "Synthetic move", kind: "reps", position: 0)])
        all.append(try m.log(set: set(1)))
        all.append(try m.startRest(seconds: 90))
        all.append(try m.complete())
        XCTAssertEqual(all.map { $0.header.sequence }, [0, 1, 2, 3, 4])
        XCTAssertEqual(m.events, all)
    }

    func testLogWhilePausedThrows() throws {
        var m = try started()
        _ = try m.pause()
        XCTAssertThrowsError(try m.log(set: set(1))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
        _ = try m.resume()
        XCTAssertNoThrow(try m.log(set: set(1)))
    }

    func testNothingAfterComplete() throws {
        var m = try started()
        _ = try m.complete()
        XCTAssertThrowsError(try m.log(set: set(1)))
        XCTAssertThrowsError(try m.pause())
        XCTAssertThrowsError(try m.complete())
        XCTAssertThrowsError(try m.abandon())
    }

    func testCorrectSupersedesTheLastEventForThatSet() throws {
        var m = try started()
        let first = try m.log(set: set(1))
        let second = try m.correct(setId: set(1).setId, values: set(1, reps: 9))
        let third = try m.correct(setId: set(1).setId, values: set(1, reps: 10))
        guard case .setCorrected(_, _, let s2) = second, case .setCorrected(_, _, let s3) = third else {
            return XCTFail("expected corrections")
        }
        XCTAssertEqual(s2, first.header.eventId)
        XCTAssertEqual(s3, second.header.eventId)
        XCTAssertEqual(m.state.sets.first?.reps, 10)
        XCTAssertEqual(m.state.sets.first?.history.count, 3)
        XCTAssertThrowsError(try m.correct(setId: set(2).setId, values: set(2))) {
            XCTAssertEqual($0 as? SessionError, .unknownSet)
        }
    }

    func testStateMatchesReplayOfEmittedEventsInAnyDeliveryOrder() throws {
        var m = try started()
        for n in 1...4 {
            _ = try m.log(set: set(n))
            _ = try m.startRest(seconds: 60)
            _ = try m.clearRest()
            if n == 2 { _ = try m.correct(setId: set(1).setId, values: set(1, reps: 7)) }
            if n == 3 { _ = try m.skip(setId: set(5).setId) }
        }
        _ = try m.pause()
        _ = try m.resume()
        _ = try m.log(set: SetValues(setId: "dddddddd-dddd-4ddd-8ddd-0000000000aa", exerciseId: exercise, position: 9, durationSeconds: 45))
        _ = try m.complete()
        XCTAssertEqual(m.events.count, 19)
        XCTAssertEqual(replay(m.events.reversed() + m.events), m.state)
        XCTAssertEqual(m.state.status, "completed")
        XCTAssertEqual(m.state.gaps, [])
        XCTAssertEqual(m.state.completedSets, 5)
    }

    func testCommandFinishMapsToComplete() throws {
        var m = try started()
        let event = try m.apply(
            command: SessionCommand(
                sessionId: session, commandId: "88888888-4444-4444-8444-000000000002", command: "finish"))
        guard case .workoutCompleted = event else { return XCTFail("expected workout_completed") }
        XCTAssertEqual(m.state.status, "completed")
    }

    func testCommandLogSetMapsToLog() throws {
        var m = try started()
        let event = try m.apply(
            command: SessionCommand(
                sessionId: session, commandId: "88888888-4444-4444-8444-000000000001",
                command: "log_set", set: set(1)))
        guard case .setLogged = event else { return XCTFail("expected set_logged") }
    }
}

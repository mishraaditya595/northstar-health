import XCTest
@testable import BeyondRepWatchCore

final class FollowerSessionTests: XCTestCase {
    private let keyA = TestMessages.keyA
    private let keyB = TestMessages.keyB
    private let sessionId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let set1 = "dddddddd-dddd-4ddd-8ddd-dddddddddd01"
    private let set2 = "dddddddd-dddd-4ddd-8ddd-dddddddddd02"
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)
    private var counter = 0

    private func ids() -> () -> String {
        var n = 0
        return {
            n += 1
            return String(format: "88888888-4444-4444-8444-%012d", n)
        }
    }

    private func session(key: String? = nil) -> FollowerSession {
        FollowerSession(accountKey: key ?? keyA, makeId: ids())
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func phoneState(
        key: String? = nil, at: TimeInterval = 0, id: String? = nil, status: String = "active",
        endReason: String? = nil, sessionId: String? = nil, owner: String = "phone",
        applied: [String] = [], rejected: [[String: String]] = [], restDeadline: TimeInterval? = nil,
        pausedAt: TimeInterval? = nil, pausedSeconds: Int? = nil, set1Status: String = "planned"
    ) -> WatchMessage {
        var body: [String: Any] = [
            "session_id": sessionId ?? self.sessionId, "owner": owner, "status": status,
            "name": "Synthetic push day", "started_at_utc": iso(t0), "last_sequence": 3,
            "exercises": [
                [
                    "exercise_id": "ex-press", "name": "Synthetic press", "kind": "reps",
                    "sets": [
                        set1Status == "completed"
                            ? ["set_id": set1, "position": 0, "kind": "working", "status": "completed",
                               "input_unit": "kg", "reps": 8, "load_grams": 60000]
                            : ["set_id": set1, "position": 0, "kind": "working", "status": set1Status,
                               "input_unit": "kg", "reps": 8, "load_grams": 60000, "rest_seconds": 75],
                        ["set_id": set2, "position": 1, "kind": "working", "status": "planned", "input_unit": "lb"],
                    ],
                ] as [String: Any],
                [
                    "exercise_id": "ex-hold", "name": "Synthetic hold", "kind": "duration",
                    "sets": [["set_id": "dddddddd-dddd-4ddd-8ddd-dddddddddd03", "position": 0, "kind": "working",
                              "status": "planned", "input_unit": "kg", "duration_seconds": 30]],
                ] as [String: Any],
            ],
        ]
        if status != "ended" { body["current_set_id"] = set1Status == "completed" ? set2 : set1 }
        if let endReason { body["end_reason"] = endReason }
        if let restDeadline { body["rest_deadline_utc"] = iso(t0.addingTimeInterval(restDeadline)) }
        if let pausedAt { body["paused_at_utc"] = iso(t0.addingTimeInterval(pausedAt)) }
        if let pausedSeconds { body["paused_seconds"] = pausedSeconds }
        if !applied.isEmpty { body["applied_command_ids"] = applied }
        if !rejected.isEmpty { body["rejected_commands"] = rejected }
        return WatchMessage(
            messageId: id ?? String(format: "99999999-3333-4333-8333-%012d", Int(at)),
            sentAtUtc: iso(t0.addingTimeInterval(at)), accountKey: key ?? keyA,
            body: .sessionState(sessionId: sessionId ?? self.sessionId, raw: body))
    }

    // MARK: Reading a state

    func testReadsASetsRestAndTimedExercises() throws {
        let state = try XCTUnwrap(PhoneWorkoutState(message: phoneState(restDeadline: 60)))
        XCTAssertEqual(state.sessionId, sessionId)
        XCTAssertEqual(state.name, "Synthetic push day")
        XCTAssertEqual(state.currentSetId, set1)
        XCTAssertEqual(state.exercises.map(\.name), ["Synthetic press", "Synthetic hold"])
        XCTAssertEqual(state.exercises[1].kind, "duration")
        let first = state.exercises[0].sets[0]
        XCTAssertEqual(first.reps, 8)
        XCTAssertEqual(first.loadGrams, 60000)
        XCTAssertEqual(first.restSeconds, 75)
        XCTAssertEqual(state.exercises[0].sets[1].inputUnit, "lb")
        XCTAssertEqual(state.restDeadline, t0.addingTimeInterval(60))
        XCTAssertEqual(state.restRemaining(now: t0.addingTimeInterval(20)) ?? 0, 40, accuracy: 0.01)
        XCTAssertNil(state.restRemaining(now: t0.addingTimeInterval(61)))
    }

    func testAWatchOwnedStateIsNotAPhoneWorkout() {
        XCTAssertNil(PhoneWorkoutState(message: phoneState(owner: "watch")))
        XCTAssertNil(PhoneWorkoutState(message: TestMessages.binding()))
    }

    func testElapsedSubtractsPausesAndNoRestWhilePaused() throws {
        let running = try XCTUnwrap(PhoneWorkoutState(message: phoneState(pausedSeconds: 40)))
        XCTAssertEqual(running.elapsed(now: t0.addingTimeInterval(300)), 260, accuracy: 0.01)
        let paused = try XCTUnwrap(
            PhoneWorkoutState(
                message: phoneState(status: "paused", restDeadline: 600, pausedAt: 100, pausedSeconds: 10)))
        XCTAssertEqual(paused.elapsed(now: t0.addingTimeInterval(300)), 90, accuracy: 0.01)
        XCTAssertNil(paused.restRemaining(now: t0.addingTimeInterval(300)))
    }

    // MARK: Account and the join rule

    func testAStateForTheBoundKeyIsAcceptedAndAnotherKeyIsNot() {
        let follower = session()
        XCTAssertEqual(follower.receive(phoneState(key: keyB), now: t0), .wrongAccount)
        XCTAssertNil(follower.state)
        XCTAssertEqual(follower.receive(phoneState(), now: t0), .accepted)
        XCTAssertEqual(follower.state?.sessionId, sessionId)
    }

    func testShouldJoinRule() throws {
        let state = try XCTUnwrap(PhoneWorkoutState(message: phoneState()))
        XCTAssertTrue(FollowerSession.shouldJoin(boundAccountKey: keyA, state: state, hasOwnSession: false))
        // An own active or paused session never joins.
        XCTAssertFalse(FollowerSession.shouldJoin(boundAccountKey: keyA, state: state, hasOwnSession: true))
        // Another account, or no binding at all.
        XCTAssertFalse(FollowerSession.shouldJoin(boundAccountKey: keyB, state: state, hasOwnSession: false))
        XCTAssertFalse(FollowerSession.shouldJoin(boundAccountKey: nil, state: state, hasOwnSession: false))
        // A workout that already ended is not joined.
        let ended = try XCTUnwrap(
            PhoneWorkoutState(message: phoneState(status: "ended", endReason: "completed")))
        XCTAssertFalse(FollowerSession.shouldJoin(boundAccountKey: keyA, state: ended, hasOwnSession: false))
    }

    func testOlderAndDuplicateStatesAreIgnoredAndAnotherSessionIsIgnored() {
        let follower = session()
        XCTAssertEqual(follower.receive(phoneState(at: 10, id: "99999999-3333-4333-8333-000000000010"), now: t0), .accepted)
        XCTAssertEqual(follower.receive(phoneState(at: 5), now: t0), .ignored)
        XCTAssertEqual(
            follower.receive(phoneState(at: 10, id: "99999999-3333-4333-8333-000000000010"), now: t0), .ignored)
        XCTAssertEqual(
            follower.receive(phoneState(at: 20, sessionId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"), now: t0),
            .ignored)
        XCTAssertEqual(follower.state?.sessionId, sessionId)
        XCTAssertEqual(follower.receive(phoneState(at: 30, set1Status: "completed"), now: t0), .accepted)
        XCTAssertEqual(follower.state?.currentSetId, set2)
    }

    // MARK: Commands

    func testACommandIsConfirmedByAppliedIdsAndRejectedWithItsReason() throws {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        let log = try XCTUnwrap(follower.logSet(setId: set1, reps: 8, loadGrams: 60000, now: t0))
        let skip = try XCTUnwrap(follower.skipSet(setId: set2, now: t0))
        XCTAssertEqual(log.phase, .pending)
        XCTAssertTrue(follower.isSaving(setId: set1))
        follower.receive(
            phoneState(at: 1, applied: [log.id], rejected: [["command_id": skip.id, "reason": "not_allowed"]]),
            now: t0.addingTimeInterval(1))
        XCTAssertFalse(follower.isSaving(setId: set1))
        XCTAssertNil(follower.commands.first { $0.id == log.id }, "an applied command is gone")
        let refused = try XCTUnwrap(follower.commands.first { $0.id == skip.id })
        XCTAssertEqual(refused.phase, .rejected("not_allowed"))
    }

    func testCommandsAreValidContractMessagesForTheBoundAccount() throws {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        let sent: [FollowerCommand?] = [
            follower.logSet(setId: set1, reps: 8, loadGrams: 60000, rpe: 8, now: t0),
            follower.skipSet(setId: set2, now: t0),
            follower.addSet(exerciseId: "ex-press", now: t0),
            follower.startRest(seconds: 90, now: t0),
            follower.clearRest(now: t0),
            follower.pause(now: t0),
            follower.resume(now: t0),
            follower.finish(now: t0),
            follower.discard(now: t0),
        ]
        var names: [String] = []
        for command in sent {
            let c = try XCTUnwrap(command)
            let message = try WatchMessage(json: Data(c.json.utf8))
            XCTAssertEqual(message.accountKey, keyA)
            guard case .sessionCommand(let body) = message.body else { return XCTFail("not a command") }
            XCTAssertEqual(body.sessionId, sessionId)
            XCTAssertEqual(body.commandId, c.id)
            names.append(body.command)
        }
        XCTAssertEqual(
            names, ["log_set", "skip_set", "add_set", "start_rest", "clear_rest", "pause", "resume", "finish", "discard"])
    }

    func testALoggedSetBecomesACorrectionAndKeepsItsPosition() throws {
        let follower = session()
        follower.receive(phoneState(set1Status: "completed"), now: t0)
        let c = try XCTUnwrap(follower.logSet(setId: set1, reps: 10, loadGrams: 62500, now: t0))
        let message = try WatchMessage(json: Data(c.json.utf8))
        guard case .sessionCommand(let body) = message.body else { return XCTFail("not a command") }
        XCTAssertEqual(body.command, "correct_set")
        XCTAssertEqual(body.set?.exerciseId, "ex-press")
        XCTAssertEqual(body.set?.position, 0)
        XCTAssertEqual(body.set?.reps, 10)
        XCTAssertEqual(body.set?.loadGrams, 62500)
    }

    func testAnUnknownSetSendsNothing() {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        XCTAssertNil(follower.logSet(setId: "dddddddd-dddd-4ddd-8ddd-ddddddddddff", reps: 1, now: t0))
        XCTAssertNil(follower.skipSet(setId: "dddddddd-dddd-4ddd-8ddd-ddddddddddff", now: t0))
        XCTAssertNil(follower.addSet(exerciseId: "no-such", now: t0))
        XCTAssertTrue(follower.commands.isEmpty)
    }

    func testNothingIsSentWithoutAStateOrWhileStale() {
        let follower = session()
        XCTAssertNil(follower.pause(now: t0))
        follower.receive(phoneState(), now: t0)
        XCTAssertFalse(follower.isStale(now: t0.addingTimeInterval(89)))
        XCTAssertTrue(follower.isStale(now: t0.addingTimeInterval(90)))
        XCTAssertNil(follower.pause(now: t0.addingTimeInterval(91)))
        follower.receive(phoneState(at: 100), now: t0.addingTimeInterval(100))
        XCTAssertFalse(follower.isStale(now: t0.addingTimeInterval(100)))
        XCTAssertNotNil(follower.pause(now: t0.addingTimeInterval(101)))
    }

    func testAPendingCommandIsResentEvery5SecondsFor30SecondsThenFails() throws {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        let c = try XCTUnwrap(follower.pause(now: t0))
        XCTAssertTrue(follower.dueResends(now: t0.addingTimeInterval(4)).isEmpty)
        XCTAssertEqual(follower.dueResends(now: t0.addingTimeInterval(5)), [c.json])
        XCTAssertTrue(follower.dueResends(now: t0.addingTimeInterval(9)).isEmpty)
        XCTAssertEqual(follower.dueResends(now: t0.addingTimeInterval(10)), [c.json])
        var last = t0.addingTimeInterval(10)
        while last < t0.addingTimeInterval(29) {
            last = last.addingTimeInterval(1)
            _ = follower.dueResends(now: last)
        }
        XCTAssertTrue(follower.dueResends(now: t0.addingTimeInterval(30)).isEmpty)
        XCTAssertEqual(follower.commands.first?.phase, .failed)
        // Retrying keeps the command id and starts again.
        let again = try XCTUnwrap(follower.retry(commandId: c.id, now: t0.addingTimeInterval(40)))
        XCTAssertEqual(again, c.json)
        XCTAssertEqual(follower.commands.first?.phase, .pending)
    }

    func testNoResendWhileStale() throws {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        _ = try XCTUnwrap(follower.pause(now: t0.addingTimeInterval(80)))
        XCTAssertTrue(follower.dueResends(now: t0.addingTimeInterval(95)).isEmpty)
    }

    func testCommandsAreDroppedWhenTheSessionEnds() throws {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        _ = try XCTUnwrap(follower.pause(now: t0))
        follower.receive(phoneState(at: 5, status: "ended", endReason: "completed"), now: t0)
        XCTAssertTrue(follower.commands.isEmpty)
    }

    // MARK: How it ends

    func testCompletedEndsWithFinishAndLink() {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        XCTAssertEqual(
            follower.receive(phoneState(at: 5, status: "ended", endReason: "completed"), now: t0),
            .ended(.finish(sessionId: sessionId)))
        XCTAssertNil(follower.state)
        // A late state of the ended session is not a new workout.
        XCTAssertEqual(follower.receive(phoneState(at: 9), now: t0), .ignored)
    }

    func testDiscardedEndsWithDiscard() {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        XCTAssertEqual(
            follower.receive(phoneState(at: 5, status: "ended", endReason: "discarded"), now: t0),
            .ended(.discard(sessionId: sessionId)))
    }

    func testAnEndedStateOfAnotherAccountOrSessionChangesNothing() {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        XCTAssertEqual(
            follower.receive(phoneState(key: keyB, at: 5, status: "ended", endReason: "completed"), now: t0),
            .wrongAccount)
        XCTAssertEqual(
            follower.receive(
                phoneState(at: 6, status: "ended", endReason: "completed", sessionId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
                now: t0), .ignored)
        XCTAssertNotNil(follower.state)
    }

    func testSixHoursWithoutAStateGivesDiscard() {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        XCTAssertNil(follower.silenceEnd(now: t0.addingTimeInterval(6 * 3600 - 1)))
        XCTAssertEqual(
            follower.silenceEnd(now: t0.addingTimeInterval(6 * 3600)), .discard(sessionId: sessionId))
        // Nothing to end without a state.
        XCTAssertNil(session().silenceEnd(now: t0.addingTimeInterval(7 * 3600)))
    }

    // MARK: Recovery after a relaunch

    func testARecoveredFollowerHasNoStateUntilTheNextOne() {
        let follower = FollowerSession(accountKey: keyA, makeId: ids(), recovering: sessionId, now: t0)
        XCTAssertNil(follower.state)
        XCTAssertEqual(follower.sessionId, sessionId)
        // A state of another session than the recovered one is not taken.
        XCTAssertEqual(
            follower.receive(phoneState(sessionId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"), now: t0), .ignored)
        XCTAssertEqual(follower.receive(phoneState(), now: t0), .accepted)
        // The 6 h rule counts from the recovery when no state arrives.
        let silent = FollowerSession(accountKey: keyA, makeId: ids(), recovering: sessionId, now: t0)
        XCTAssertEqual(
            silent.silenceEnd(now: t0.addingTimeInterval(6 * 3600)), .discard(sessionId: sessionId))
    }

    func testNoHealthValueIsInACommand() throws {
        let follower = session()
        follower.receive(phoneState(), now: t0)
        let c = try XCTUnwrap(follower.logSet(setId: set1, reps: 8, loadGrams: 60000, now: t0))
        let text = c.json.lowercased()
        for word in ["heart", "kcal", "energy", "bpm"] { XCTAssertFalse(text.contains(word), word) }
    }
}

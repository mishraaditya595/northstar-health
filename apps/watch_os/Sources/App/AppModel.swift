import Foundation
import HealthKit
import SwiftUI
import WatchKit
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Owns the watch journal and the glance the Home screen shows. All journal
/// access happens on the main actor, which is the one serial owner the
/// journal requires.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var glance: GlanceState = .notPaired
    @Published private(set) var syncLine: SyncLine = .notPaired
    @Published private(set) var isPhoneReachable = false
    /// The running (or just finished) workout. The controller is not
    /// observable, so every action bumps `revision` to redraw the screens.
    @Published private(set) var workout: WorkoutController?
    @Published private(set) var revision = 0
    /// True from a Start tap until the session is running, so a double tap
    /// cannot start two sessions while HealthKit asks for permission.
    @Published private(set) var isStarting = false
    @Published private(set) var summary: WorkoutSummary?
    @Published private(set) var waiting = WaitingWorkouts(waiting: 0, waitingOtherAccount: 0)
    /// Length of the rest in progress, for the ring.
    @Published private(set) var restTotalSeconds: Double = 90
    /// The workout the iPhone owns and this watch follows (stage 5b). Not
    /// observable: every change bumps `revision`. Nil when there is none.
    private(set) var follower: FollowerSession?
    let recorder = WorkoutRecorder()
    private var details: [Metric: DetailModel] = [:]

    /// What the watch read itself (sleep, steps, HRV, resting heart rate).
    /// Memory only: never written to the journal, `UserDefaults` or a file,
    /// never sent to the phone, never logged. Dropped when the account
    /// changes and at midnight.
    private var held: HeldWatchHealth?
    private let healthReader = HealthGlanceReader()
    /// Only the newest read may store its result.
    private var healthReadId = 0
    /// Set before the first await so two Home triggers never ask twice.
    private var didAskForHealth = false
    private var periodicHealthTask: Task<Void, Never>?

    /// Sends the acks for what the inbox stored; set by `PhoneLink`.
    weak var link: PhoneLink?

    /// The live link to the iPhone (stage 5a): the mirrored workout session,
    /// else WatchConnectivity messages. Memory only, nothing is stored.
    private lazy var liveLink = LiveLink(recorder: recorder, phone: { [weak self] in self?.link })
    private var liveHeartbeat: Task<Void, Never>?
    /// Refusals that have no journal row (a command for another session),
    /// listed in the next states, newest last.
    private var extraRejections: [SessionStateBuilder.Rejection] = []
    /// A discard that is still telling the iPhone before it ends HealthKit.
    private var endingTask: Task<Void, Never>?

    /// Ticks every 5 s while following: resends, staleness, the 6 h rule and
    /// the 60 s wait for the first state.
    private var followerTicker: Task<Void, Never>?
    private var followerJoinedAt = Date()
    private var followerPersisted = false
    /// A restore that is running, so a launch by the iPhone waits for it
    /// before it decides whether the watch has its own session.
    private var restoreTask: Task<Void, Never>?
    /// The first state must arrive within this time of the launch.
    private static let followerConnectLimit: TimeInterval = 60

    private let journal: WatchJournal?
    private let inbox: PhoneInbox?
    private var midnightTask: Task<Void, Never>?

    private var restHapticTask: Task<Void, Never>?
    private var hapticDeadline: Date?
    private var observedDeadline: Date?

    /// `journalURL` is for previews; the app uses its Application Support folder.
    init(journalURL: URL? = nil) {
        let url: URL?
        if let journalURL {
            url = journalURL
        } else {
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            url = support?.appendingPathComponent("beyondrep-watch.sqlite")
        }
        let journal = url.flatMap { try? WatchJournal(url: $0) }
        self.journal = journal
        self.inbox = journal.map { PhoneInbox(journal: $0) }
        pruneStale()
        refresh()
        scheduleMidnightRefresh()
        recorder.onRemoteMessage = { [weak self] data in self?.receive(liveMessage: data) }
    }

    deinit {
        liveHeartbeat?.cancel()
        midnightTask?.cancel()
        followerTicker?.cancel()
        restHapticTask?.cancel()
        periodicHealthTask?.cancel()
    }

    func receive(applicationContext: [String: Any]) {
        acknowledge(try? inbox?.receive(applicationContext: applicationContext))
        refresh()
        // A health snapshot changes what the phone's numbers are; read ours again.
        Task { await refreshWatchHealth() }
    }

    func receive(userInfo: [String: Any]) {
        acknowledge(try? inbox?.receive(userInfo: userInfo))
        refresh()
        // An ack removes a sent workout; a new binding may free queued ones.
        sendQueued()
    }

    /// Tells the phone what the watch stored. An ack carries ids and a result
    /// only; the phone is the one that says "synced".
    private func acknowledge(_ outcomes: [AckOutcome]?) {
        guard let outcomes, !outcomes.isEmpty else { return }
        let now = Date()
        link?.send(acks: outcomes.map { AckBuilder.json(for: $0, messageId: UUID(), now: now) })
    }

    func setPhoneReachable(_ reachable: Bool) {
        isPhoneReachable = reachable
        refresh()
        if reachable {
            sendQueued()
            // The iPhone app just opened: show it the workout at once.
            broadcastLiveState()
        }
    }

    // MARK: Live link (the iPhone follows and controls a workout the watch owns)

    private static let liveTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// The current `session_state` of `controller`. The send time has
    /// milliseconds: the iPhone keeps the newest state by it.
    private func liveStateMessage(for controller: WorkoutController) -> WatchMessage? {
        try? controller.sessionState(
            messageId: UUID().uuidString.lowercased(), sentAtUtc: Self.liveTimestamp.string(from: Date()),
            extraRejections: extraRejections)
    }

    /// Sends the state of the running workout on the live link, if there is one.
    func broadcastLiveState() {
        guard let workout, let message = liveStateMessage(for: workout) else { return }
        liveLink.send(message)
    }

    /// A state after every journal change (`didAct`) and one every 30 s while
    /// a workout is active or paused, so the iPhone can tell a quiet link from
    /// a lost one.
    private func updateLiveHeartbeat() {
        let live = workout.map { $0.status == "active" || $0.status == "paused" } ?? false
        if live, liveHeartbeat == nil {
            liveHeartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                    if Task.isCancelled { return }
                    await self?.recorder.retryMirroringIfNeeded()
                    self?.broadcastLiveState()
                }
            }
        } else if !live {
            liveHeartbeat?.cancel()
            liveHeartbeat = nil
        }
    }

    /// A message from the iPhone on the live link (mirrored session or
    /// WatchConnectivity; both can deliver the same command, and a command id
    /// is applied once). Only `session_command` is read; everything is checked
    /// against this account and session by `WorkoutController.apply`.
    func receive(liveMessage data: Data) {
        if let phoneState = try? WatchMessage(json: data), case .sessionState = phoneState.body {
            receiveFollowerState(phoneState)
            return
        }
        guard let message = try? WatchMessage(json: data), case .sessionCommand(let command) = message.body,
            let controller = workout, let outcome = try? controller.apply(message)
        else { return }
        switch outcome {
        case .needsFinish:
            Task { await completeFinish(controller) }
        case .applied:
            if controller.status == "abandoned" { wrapUpDiscard(controller) }
        case .rejected(.unknownSession):
            let id = command.commandId.lowercased()
            if !extraRejections.contains(where: { $0.commandId == id }) {
                extraRejections.append(SessionStateBuilder.Rejection(commandId: id, reason: "unknown_session"))
                extraRejections = Array(extraRejections.suffix(20))
            }
        case .rejected, .duplicate, .ignored:
            break
        }
        didAct()
    }

    func detail(for metric: Metric) -> DetailModel? {
        details[metric]
    }

    /// Drops a binding the phone has not refreshed for 90 days (never during or while
    /// starting a workout, never unsent workouts). Errors are ignored; the next call retries.
    func pruneStale() {
        guard !isStarting, workout == nil, follower == nil else { return }
        _ = try? journal?.pruneStale(nowMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    /// Recomputes the glance, the detail screens and the sync line; also
    /// called when the app becomes active.
    func refresh() {
        guard let journal else { return }
        // The phone signed in as someone else: a followed workout is dropped.
        if let follower, boundAccount?.accountKey != follower.accountKey { endFollower(.discard(sessionId: follower.sessionId ?? "")) }
        let now = Date()
        // The held values are only ever for the account that is bound now.
        let watch = held?.ifCurrent(boundKey: boundAccount?.accountKey)
        if watch == nil { held = nil }
        if let next = try? GlanceState.make(
            journal: journal, now: now, timeZone: .current, locale: .current, watch: watch)
        {
            glance = next
        }
        var next: [Metric: DetailModel] = [:]
        for metric in [Metric.sleep, .restingHr, .hrv, .steps] {
            if let detail = try? DetailModel.make(
                metric: metric, journal: journal, now: now, timeZone: .current, locale: .current,
                watch: watch)
            {
                next[metric] = detail
            }
        }
        details = next
        if let next = try? WaitingWorkouts.make(journal: journal) { waiting = next }
        revision += 1
        if let line = try? SyncLine.make(
            journal: journal, isPhoneReachable: isPhoneReachable, now: now, timeZone: .current,
            locale: .current)
        {
            syncLine = line
        }
    }

    // MARK: Health read by the watch

    /// Reads today's values from this watch's HealthKit store and redraws.
    /// Returns at once without an account binding: nothing is read for an
    /// unpaired watch. A failed or denied read leaves its value missing.
    func refreshWatchHealth() async {
        guard let key = boundAccount?.accountKey else { return }
        healthReadId += 1
        let id = healthReadId
        let read = await healthReader.read(now: Date(), timeZone: .current)
        // A newer read started, or the account changed while HealthKit worked.
        guard id == healthReadId, boundAccount?.accountKey == key else { return }
        let before = held ?? HeldWatchHealth(accountKey: key, health: read.health)
        held = before.updated(accountKey: key, read: read.health, failed: read.failed)
        refresh()
    }

    /// The Home is showing: asks for the HealthKit permission once (when
    /// HealthKit has not decided yet), reads, and keeps reading every 5
    /// minutes while the app is active.
    func homeAppeared() async {
        guard boundAccount != nil else { return }
        startPeriodicHealthRefresh()
        if !didAskForHealth {
            didAskForHealth = true
            if await healthReader.shouldRequestAuthorization() {
                await healthReader.requestAuthorization()
            }
        }
        await refreshWatchHealth()
    }

    func startPeriodicHealthRefresh() {
        guard periodicHealthTask == nil else { return }
        periodicHealthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                if Task.isCancelled { return }
                // Sample queries work during a workout, so this keeps reading then too.
                guard let self else { return }
                await self.refreshWatchHealth()
            }
        }
    }

    func stopPeriodicHealthRefresh() {
        periodicHealthTask?.cancel()
        periodicHealthTask = nil
    }


    // MARK: Following a workout the iPhone owns (stage 5b)

    /// The iPhone started a workout and launched the watch app. Joins only
    /// when the watch has an account binding and no session of its own;
    /// otherwise nothing starts. The HealthKit session starts at once (it
    /// collects heart rate and is the one `HKWorkout` this watch saves); the
    /// first `session_state` names the phone workout.
    func joinPhoneWorkout(configuration: HKWorkoutConfiguration) async {
        // A relaunch is still restoring a session of its own: wait for it.
        await restoreTask?.value
        guard let account = boundAccount, workout == nil, follower == nil, !isStarting, summary == nil else { return }
        // Set before the first await so a second launch cannot join twice.
        follower = FollowerSession(accountKey: account.accountKey, makeId: { UUID().uuidString.lowercased() })
        followerJoinedAt = Date()
        followerPersisted = false
        revision += 1
        await endingTask?.value
        _ = await recorder.requestAuthorization()
        do {
            try await recorder.begin(workoutId: nil, at: Date(), configuration: configuration)
        } catch {
            // Without a HealthKit session there is no heart rate and no
            // HKWorkout: the watch does not follow.
            recorder.discard()
            follower = nil
            revision += 1
            return
        }
        startFollowerTicker()
    }

    /// Picks a follower up after a relaunch: its row names the session and
    /// HealthKit kept the session alive. When HealthKit lost it, the one
    /// HKWorkout may still have been saved before the app died, and then only
    /// the link is missing.
    private func restoreFollower() async {
        guard let journal, let row = try? journal.follower() else { return }
        guard row.accountKey == boundAccount?.accountKey else {
            // Another account: never followed. The orphan policy ends the session.
            try? journal.clearFollower()
            return
        }
        if await recorder.recover(workoutId: row.sessionId) {
            follower = FollowerSession(
                accountKey: row.accountKey, makeId: { UUID().uuidString.lowercased() }, recovering: row.sessionId,
                now: Date())
            followerJoinedAt = Date()
            followerPersisted = true
            startFollowerTicker()
            sendFollowerJoin(sessionId: row.sessionId)
        } else {
            if case .found(let uuid) = await recorder.savedWorkout(workoutId: row.sessionId) {
                queueLink(sessionId: row.sessionId, accountKey: row.accountKey, healthkitWorkoutUuid: uuid)
            } else {
                try? journal.clearFollower()
            }
        }
    }

    private func sendFollowerJoin(sessionId: String) {
        guard let follower else { return }
        let message = WatchMessage(
            messageId: UUID().uuidString.lowercased(), sentAtUtc: Self.liveTimestamp.string(from: Date()),
            accountKey: follower.accountKey, body: .join(sessionId: sessionId))
        liveLink.send(message)
    }

    private func receiveFollowerState(_ message: WatchMessage) {
        guard let follower else { return }
        if follower.state == nil, let incoming = PhoneWorkoutState(message: message), !incoming.isEnded,
            !FollowerSession.shouldJoin(
                boundAccountKey: boundAccount?.accountKey, state: incoming, hasOwnSession: workout != nil)
        {
            // Another account's workout: this watch is not part of it.
            endFollower(.discard(sessionId: incoming.sessionId))
            return
        }
        switch follower.receive(message, now: Date()) {
        case .accepted:
            if !followerPersisted, let sessionId = follower.sessionId, let journal {
                followerPersisted = true
                try? journal.saveFollower(
                    sessionId: sessionId, accountKey: follower.accountKey,
                    joinedAtMs: Int64(followerJoinedAt.timeIntervalSince1970 * 1000), phase: "following")
                recorder.adopt(workoutId: sessionId)
                // The phone sends its state again at once; later states keep it fresh.
                sendFollowerJoin(sessionId: sessionId)
            }
        case .ended(let end):
            if let sessionId = follower.sessionId { recorder.adopt(workoutId: sessionId) }
            endFollower(end)
        case .wrongAccount:
            endFollower(.discard(sessionId: follower.sessionId ?? ""))
        case .ignored:
            break
        }
        revision += 1
    }

    /// Ends following. `finish` saves the one HKWorkout and queues the link;
    /// `discard` drops what HealthKit collected. Either way the iPhone has
    /// the workout, and the watch returns to Home.
    private func endFollower(_ end: FollowerEnd) {
        guard let current = follower else { return }
        follower = nil
        followerTicker?.cancel()
        followerTicker = nil
        revision += 1
        switch end {
        case .finish(let sessionId):
            let previous = endingTask
            endingTask = Task { [weak self] in
                await previous?.value
                guard let self else { return }
                self.recorder.adopt(workoutId: sessionId)
                let uuid = await self.recorder.finish(at: Date())
                if let uuid {
                    self.queueLink(sessionId: sessionId, accountKey: current.accountKey, healthkitWorkoutUuid: uuid)
                } else {
                    // HealthKit denied or failed: no workout was saved, so nothing to link.
                    try? self.journal?.clearFollower()
                }
            }
        case .discard:
            try? journal?.clearFollower()
            recorder.discard()
        }
    }

    /// Commits the `workout_link` (and drops the follower row) in the
    /// journal, then sends it. It is resent until the phone acks it.
    private func queueLink(sessionId: String, accountKey: String, healthkitWorkoutUuid: String) {
        let message = WatchMessage(
            messageId: UUID().uuidString.lowercased(), sentAtUtc: Self.liveTimestamp.string(from: Date()),
            accountKey: accountKey, body: .workoutLink(workoutId: sessionId, healthkitWorkoutUuid: healthkitWorkoutUuid))
        _ = try? journal?.queueWorkoutLink(message)
        sendQueued()
        revision += 1
    }

    private func startFollowerTicker() {
        followerTicker?.cancel()
        followerTicker = Task { [weak self] in
            var beats = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                beats += 1
                if beats % 6 == 0 { await self.recorder.retryMirroringIfNeeded() }
                self.followerTick()
            }
        }
    }

    private func followerTick() {
        guard let follower else { return }
        let now = Date()
        if follower.sessionId == nil, now.timeIntervalSince(followerJoinedAt) >= Self.followerConnectLimit {
            // The iPhone never sent a state: leave, so no session runs for nothing.
            endFollower(.discard(sessionId: ""))
            return
        }
        if let end = follower.silenceEnd(now: now) {
            endFollower(end)
            return
        }
        for json in follower.dueResends(now: now) { liveLink.send(json: json) }
        revision += 1
    }

    /// Builds one command with the follower and sends it. Shown as saved only
    /// when the phone lists it as applied. False when there is nothing to send
    /// (no follower, a stale view or an unknown set).
    @discardableResult
    func follow(_ make: (FollowerSession, Date) -> FollowerCommand?) -> Bool {
        guard let follower, let command = make(follower, Date()) else { return false }
        liveLink.send(json: command.json)
        revision += 1
        return true
    }

    func followerRetry(commandId: String) {
        guard let follower, let json = follower.retry(commandId: commandId, now: Date()) else { return }
        liveLink.send(json: json)
        revision += 1
    }

    func followerDismiss(commandId: String) {
        follower?.dismiss(commandId: commandId)
        revision += 1
    }

    // MARK: Workouts

    private var boundAccount: (accountKey: String, unit: String)? {
        try? journal?.binding()
    }

    /// The unit weights are entered in: the phone's unit (the binding).
    var inputUnit: String { boundAccount?.unit ?? "kg" }

    /// Starting needs an account binding (the phone signed in) and no workout running.
    var canStart: Bool { boundAccount != nil && workout == nil && follower == nil }

    /// A stable id for this watch install, written into every event.
    private var deviceId: String {
        let key = "watchInstallationId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let made = "watch-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(made, forKey: key)
        return made
    }

    private func plansBody() -> [String: Any]? {
        guard let account = boundAccount, let message = try? journal?.plans(accountKey: account.accountKey),
            case .plansSnapshot(let raw) = message.body
        else { return nil }
        return raw
    }

    /// A fresh template (new exercise and set ids) of one plan, or of today's
    /// program workout when `planId` is nil.
    func template(planId: String?) -> WorkoutTemplate? {
        guard let raw = plansBody() else { return nil }
        let makeId: () -> String = { UUID().uuidString.lowercased() }
        if let planId { return WorkoutTemplate.fromPlan(plansSnapshot: raw, planId: planId, makeId: makeId) }
        return WorkoutTemplate.today(plansSnapshot: raw, makeId: makeId)
    }

    /// Exercises the phone listed as recent, for "+ Add exercise".
    var recentExercises: [(name: String, kind: String)] {
        guard let raw = plansBody(), let items = raw["recent_exercises"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = item["name"] as? String, let kind = item["kind"] as? String else { return nil }
            return (name, kind)
        }
    }

    func startWorkout(_ template: WorkoutTemplate) async {
        guard let journal, let account = boundAccount, workout == nil, follower == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        // A discard in progress still holds the previous HealthKit session.
        await endingTask?.value
        _ = await recorder.requestAuthorization()
        guard
            let controller = try? WorkoutController.start(
                template: template, journal: journal, accountKey: account.accountKey, unit: account.unit,
                deviceId: deviceId, clock: Date.init, timeZone: TimeZone.current.identifier,
                makeId: { UUID().uuidString.lowercased() })
        else { return }
        workout = controller
        summary = nil
        extraRejections = []
        // HealthKit failures are ignored: the workout still records, without
        // heart rate and without a saved HKWorkout.
        try? await recorder.begin(workoutId: controller.workoutId, at: controller.startedAt)
        didAct()
    }

    /// Runs one controller action. A failed commit leaves the screen as it
    /// was: nothing is shown as done before it is stored. Returns whether the
    /// action committed.
    @discardableResult
    func act(_ action: (WorkoutController) throws -> Void) -> Bool {
        guard let workout else { return false }
        let committed = (try? action(workout)) != nil
        didAct()
        return committed
    }

    /// HealthKit changes only after the journal commit succeeded.
    func pauseOrResume() {
        guard let workout else { return }
        if workout.status == "paused" {
            if act({ try $0.resume() }) { recorder.resume() }
        } else {
            if act({ try $0.pause() }) { recorder.pause() }
        }
    }

    /// Save: record the finish, save the one HKWorkout, queue the completed
    /// workout, send it, and show the summary.
    func finishWorkout() async {
        guard let controller = workout, controller.canSave else { return }
        do { try controller.markCompleted() } catch { return }
        await completeFinish(controller)
    }

    /// After `workout_completed` is committed (by a tap or by the iPhone's
    /// `finish`): tell the iPhone the workout ended while the mirrored session
    /// still exists, then save the one HKWorkout, queue the completed workout
    /// and show the summary.
    private func completeFinish(_ controller: WorkoutController) async {
        if let ended = liveStateMessage(for: controller) { await liveLink.sendEnded(ended) }
        let uuid = await recorder.finish(at: Date())
        try? controller.queueCompleted(healthkitWorkoutUuid: uuid)
        let elapsed = Date().timeIntervalSince(controller.startedAt)
        summary = WorkoutSummary(
            name: controller.template.name, elapsed: elapsed, sets: controller.state.completedSets,
            averageHeartRate: recorder.averageHeartRate, sessionId: controller.sessionId)
        sendQueued()
        didAct()
    }

    /// Commit first: if the journal write fails the workout and HealthKit stay as they were.
    func discardWorkout() {
        guard let controller = workout, act({ try $0.discard() }) else { return }
        wrapUpDiscard(controller)
        didAct()
    }

    /// After `workout_abandoned` is committed (by a tap or by the iPhone's
    /// `discard`): the iPhone gets the ended state while the mirrored session
    /// still exists, then HealthKit drops what it collected.
    private func wrapUpDiscard(_ controller: WorkoutController) {
        let ended = liveStateMessage(for: controller)
        workout = nil
        let previous = endingTask
        endingTask = Task { [weak self] in
            await previous?.value
            if let ended { await self?.liveLink.sendEnded(ended) }
            self?.recorder.discard()
        }
    }

    func dismissSummary() {
        summary = nil
        workout = nil
        didAct()
    }

    /// The status line of the summary. "Saved to iPhone" only after the
    /// phone's ack; reachable is not the same as stored.
    var summaryStatus: String {
        guard let summary else { return "" }
        let state = try? journal?.delivery(sessionId: summary.sessionId)
        if state == "delivered" { return "Saved to iPhone" }
        return isPhoneReachable
            ? "Saved on watch \u{00B7} sent to iPhone" : "Saved on watch \u{00B7} waiting for iPhone"
    }

    /// Restores a running workout of the bound account after a relaunch,
    /// queues every finished-but-unqueued workout of any account, then sends
    /// what waits. Restoring an active session of another account is not done.
    func restoreWorkout() async {
        let task = restoreTask ?? Task { await self.performRestore() }
        restoreTask = task
        await task.value
        restoreTask = nil
    }

    private func performRestore() async {
        guard let journal else { return }
        if let account = boundAccount, workout == nil,
            let restored = try? WorkoutController.restore(
                journal: journal, accountKey: account.accountKey, unit: account.unit, deviceId: deviceId,
                clock: Date.init, timeZone: TimeZone.current.identifier)
        {
            workout = restored
            _ = await recorder.recover(workoutId: restored.workoutId)
        }
        if workout == nil { await restoreFollower() }
        var unresolvedPendingFinish = boundAccount == nil
        for pending in (try? WorkoutController.pendingFinishAllAccounts(journal: journal)) ?? [] {
            var uuid: String?
            if let workoutId = try? journal.events(sessionId: pending.sessionId).first?.header.workoutId {
                // The HKWorkout may already be saved; never save a second one.
                switch await recorder.savedWorkout(workoutId: workoutId) {
                case .found(let found):
                    uuid = found
                case .failed:
                    // Do not queue without a UUID: the next launch retries.
                    unresolvedPendingFinish = true
                    continue
                case .notFound:
                    // Another running session owns the recovered HealthKit session.
                    if workout != nil || follower != nil { continue }
                    // Only finished here, so the iPhone has nothing to follow.
                    if await recorder.recover(workoutId: workoutId, mirror: false) {
                        let end = try? WorkoutController.completedAt(sessionId: pending.sessionId, journal: journal)
                        uuid = await recorder.finish(at: end ?? Date())
                    }
                }
            }
            try? WorkoutController.queuePendingFinish(
                sessionId: pending.sessionId, journal: journal, accountKey: pending.accountKey,
                healthkitWorkoutUuid: uuid, makeId: { UUID().uuidString.lowercased() }, clock: Date.init)
        }
        // A HealthKit session no journal session explains (the app died after a
        // discard committed) would run for hours: end it.
        if OrphanSessionPolicy.shouldDiscard(
            restoredSession: workout != nil || follower != nil, unresolvedPendingFinish: unresolvedPendingFinish)
        {
            _ = await recorder.discardOrphanedSession()
        }
        sendQueued()
        didAct()
    }

    /// Sends each queued completed workout of the bound account that is not
    /// already in flight. A workout of another account stays queued: it is
    /// never sent under this account and never deleted.
    func sendQueued() {
        guard let journal, let account = boundAccount else { return }
        let outstanding = link?.outstandingIds() ?? []
        for message in (try? journal.pendingCompleted(limit: 20)) ?? []
        where message.accountKey == account.accountKey && !outstanding.contains(message.messageId.lowercased()) {
            link?.send(completed: message)
        }
        // A link is resent until the phone acks it (the ack removes it).
        for message in (try? journal.pendingLinks(limit: 20)) ?? []
        where message.accountKey == account.accountKey && !outstanding.contains(message.messageId.lowercased()) {
            link?.send(completed: message)
        }
    }

    private func didAct() {
        revision += 1
        broadcastLiveState()
        updateLiveHeartbeat()
        let deadline = workout?.restDeadline
        if deadline != observedDeadline {
            observedDeadline = deadline
            if let deadline { restTotalSeconds = max(1, deadline.timeIntervalSinceNow) }
            scheduleRestHaptic(deadline)
        }
    }

    /// One haptic per rest deadline, scheduled from the deadline itself so it
    /// also fires with the screen off (the workout session keeps the app running).
    private func scheduleRestHaptic(_ deadline: Date?) {
        restHapticTask?.cancel()
        guard let deadline, deadline != hapticDeadline else { return }
        // A deadline long past (a relaunch after the rest ended) gets no haptic.
        if deadline.timeIntervalSinceNow < -5 {
            hapticDeadline = deadline
            return
        }
        restHapticTask = Task { [weak self] in
            let seconds = deadline.timeIntervalSinceNow
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            if Task.isCancelled { return }
            WKInterfaceDevice.current().play(.stop)
            self?.hapticDeadline = deadline
            self?.revision += 1
        }
    }

    #if DEBUG
    /// Previews only: shows a workout or summary without HealthKit.
    func attachPreview(workout: WorkoutController?, summary: WorkoutSummary? = nil) {
        self.workout = workout
        self.summary = summary
        revision += 1
    }
    #endif

    /// Health values are for one local date, so the glance is recomputed when
    /// the date changes even if the app stays open.
    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        midnightTask = Task { [weak self] in
            while !Task.isCancelled {
                let calendar = Calendar.current
                guard let midnight = calendar.nextDate(
                    after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 1),
                    matchingPolicy: .nextTime)
                else { return }
                let seconds = max(1, midnight.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { return }
                // Yesterday's values must not show on the new day while the
                // read is in flight.
                self?.held = nil
                self?.refresh()
                await self?.refreshWatchHealth()
            }
        }
    }
}

/// What the summary screen shows after Save. No health values beyond the
/// average heart rate the watch itself measured; none of it is sent.
struct WorkoutSummary: Equatable {
    let name: String
    let elapsed: TimeInterval
    let sets: Int
    let averageHeartRate: Int?
    let sessionId: String
}

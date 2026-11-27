import Foundation
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
        guard !isStarting, workout == nil else { return }
        _ = try? journal?.pruneStale(nowMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    /// Recomputes the glance, the detail screens and the sync line; also
    /// called when the app becomes active.
    func refresh() {
        guard let journal else { return }
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

    // MARK: Workouts

    private var boundAccount: (accountKey: String, unit: String)? {
        try? journal?.binding()
    }

    /// The unit weights are entered in: the phone's unit (the binding).
    var inputUnit: String { boundAccount?.unit ?? "kg" }

    /// Starting needs an account binding (the phone signed in) and no workout running.
    var canStart: Bool { boundAccount != nil && workout == nil }

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
        guard let journal, let account = boundAccount, workout == nil, !isStarting else { return }
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
        guard let journal else { return }
        if let account = boundAccount, workout == nil,
            let restored = try? WorkoutController.restore(
                journal: journal, accountKey: account.accountKey, unit: account.unit, deviceId: deviceId,
                clock: Date.init, timeZone: TimeZone.current.identifier)
        {
            workout = restored
            _ = await recorder.recover(workoutId: restored.workoutId)
        }
        for pending in (try? WorkoutController.pendingFinishAllAccounts(journal: journal)) ?? [] {
            var uuid: String?
            if let workoutId = try? journal.events(sessionId: pending.sessionId).first?.header.workoutId {
                // The HKWorkout may already be saved; never save a second one.
                switch await recorder.savedWorkout(workoutId: workoutId) {
                case .found(let found):
                    uuid = found
                case .failed:
                    // Do not queue without a UUID: the next launch retries.
                    continue
                case .notFound:
                    // Another running session owns the recovered HealthKit session.
                    if workout != nil { continue }
                    if await recorder.recover(workoutId: workoutId) {
                        let end = try? WorkoutController.completedAt(sessionId: pending.sessionId, journal: journal)
                        uuid = await recorder.finish(at: end ?? Date())
                    }
                }
            }
            try? WorkoutController.queuePendingFinish(
                sessionId: pending.sessionId, journal: journal, accountKey: pending.accountKey,
                healthkitWorkoutUuid: uuid, makeId: { UUID().uuidString.lowercased() }, clock: Date.init)
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

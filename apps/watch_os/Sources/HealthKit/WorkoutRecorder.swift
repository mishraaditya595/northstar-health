import Foundation
import HealthKit

/// The result of looking for an already saved `HKWorkout`.
enum SavedWorkoutLookup: Equatable {
    case found(String)
    case notFound
    case failed
}

/// The one HealthKit permission request of the watch app: share
/// `workoutType()`; read heart rate and active energy (during a workout) and
/// steps, sleep, HRV and resting heart rate (the Home tiles, see
/// `HealthGlanceReader`). One request covers all of them, so the person sees
/// one prompt, and asking again once decided does nothing.
enum HealthAccess {
    static let share: Set<HKSampleType> = [HKObjectType.workoutType()]
    static let read: Set<HKObjectType> = [
        HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.stepCount), HKCategoryType(.sleepAnalysis),
        HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.restingHeartRate),
    ]

    /// True only while HealthKit has never asked for exactly these types.
    /// HealthKit hides read denials, so "decided" is all it can tell.
    static func shouldRequest(store: HKHealthStore) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: share, read: read) { status, error in
                continuation.resume(returning: error == nil && status == .shouldRequest)
            }
        }
    }

    /// Asks; true when the person allowed saving workouts.
    static func request(store: HKHealthStore) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            return false
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }
}

/// The thin HealthKit wrapper that owns the live workout session. It holds no
/// workout rules (those are in `WorkoutController`). Heart rate and energy
/// stay on the watch: the completed workout carries only the saved
/// `HKWorkout` UUID.
@MainActor
final class WorkoutRecorder: NSObject, ObservableObject {
    @Published private(set) var heartRate: Int?
    @Published private(set) var activeKilocalories: Double?
    /// The average heart rate of the session so far, for the summary only.
    @Published private(set) var averageHeartRate: Int?

    /// True while the workout session is mirrored to the iPhone (iOS 17+). The
    /// mirrored session is the live link's first choice and keeps the phone
    /// app alive in the background.
    private(set) var isMirroring = false
    /// A live message the phone sent through the mirrored session (a
    /// `session_command`). The model decides what it means.
    var onRemoteMessage: (@MainActor (Data) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var workoutId: String?
    private var isStartingMirror = false

    /// Asks once; true when the person allowed saving workouts. Denied or
    /// unavailable HealthKit is not an error: the workout still records.
    func requestAuthorization() async -> Bool {
        await HealthAccess.request(store: store)
    }

    func begin(workoutId: String, at date: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        self.workoutId = workoutId
        heartRate = nil
        activeKilocalories = nil
        averageHeartRate = nil
        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
        await startMirroring()
    }

    /// Mirrors the session to the iPhone. A failure (no iPhone in reach, an
    /// iPhone below iOS 17) leaves the live link on WatchConnectivity; the
    /// next heartbeat tries again (`retryMirroringIfNeeded`). An error that
    /// says the session is already mirrored counts as mirroring.
    private func startMirroring() async {
        guard let session, !isStartingMirror else { return }
        isStartingMirror = true
        defer { isStartingMirror = false }
        do {
            try await session.startMirroringToCompanionDevice()
            isMirroring = true
        } catch {
            isMirroring = Self.isAlreadyMirroring(error)
        }
    }

    /// HealthKit has no documented code for this, so the error text is
    /// matched (a device check in `docs/RELEASE.md` confirms it).
    private static func isAlreadyMirroring(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("already") && text.contains("mirror")
    }

    /// Called by the 30 s live heartbeat while a workout is active or paused:
    /// a mirror the disconnect callback dropped (the iPhone went out of
    /// range) is started again. Never faster than the heartbeat.
    func retryMirroringIfNeeded() async {
        guard session != nil, !isMirroring else { return }
        await startMirroring()
    }

    /// Sends one live message through the mirrored session and reports
    /// whether HealthKit delivered it, so the caller can use the fallback
    /// when it did not. The completion runs on any queue; it is called with
    /// false at once when there is no mirrored session.
    func send(_ data: Data, completion: @escaping @Sendable (Bool) -> Void) {
        guard isMirroring, let session else {
            completion(false)
            return
        }
        session.sendToRemoteWorkoutSession(data: data) { success, _ in completion(success) }
    }

    /// Like `send`, but returns once HealthKit reports the data handled or
    /// after `timeout` seconds, so the last state goes out before the session
    /// ends and a slow link never holds up finishing. False when it was not
    /// delivered (no mirror, a failure or the timeout), so the caller sends it
    /// the other way too.
    func sendAndWait(_ data: Data, timeout: TimeInterval) async -> Bool {
        guard isMirroring, let session else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = Once()
            session.sendToRemoteWorkoutSession(data: data) { success, _ in
                once.run { continuation.resume(returning: success) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.run { continuation.resume(returning: false) }
            }
        }
    }

    private func stopMirroring() {
        guard isMirroring, let session else { return }
        isMirroring = false
        session.stopMirroringToCompanionDevice { _, _ in }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends the session and saves one `HKWorkout` that carries the BeyondRep
    /// workout id in `HKMetadataKeyExternalUUID`. Returns its UUID (lowercase),
    /// or nil when HealthKit is unavailable, denied or failed.
    func finish(at date: Date) async -> String? {
        guard let session, let builder else { return nil }
        stopMirroring()
        session.end()
        var uuid: String?
        do {
            try await builder.endCollection(at: date)
            if let workoutId {
                try await builder.addMetadata([HKMetadataKeyExternalUUID: workoutId])
            }
            uuid = try await builder.finishWorkout()?.uuid.uuidString.lowercased()
        } catch {
            uuid = nil
        }
        clear()
        return uuid
    }

    /// Ends the session and deletes whatever it collected.
    func discard() {
        stopMirroring()
        session?.end()
        builder?.discardWorkout()
        clear()
    }

    /// Reattaches to a session HealthKit kept alive while the app was not
    /// running. `workoutId` is the BeyondRep workout it belongs to.
    /// `mirror: false` for a session that is only being finished or discarded:
    /// there is nothing for the iPhone to follow.
    func recover(workoutId: String? = nil, mirror: Bool = true) async -> Bool {
        do {
            guard let recovered = try await store.recoverActiveWorkoutSession() else { return false }
            let builder = recovered.associatedWorkoutBuilder()
            recovered.delegate = self
            builder.delegate = self
            session = recovered
            self.builder = builder
            if let workoutId { self.workoutId = workoutId }
            if mirror { await startMirroring() }
            return true
        } catch {
            return false
        }
    }

    /// Ends and discards a HealthKit session nothing in the journal explains
    /// (see `OrphanSessionPolicy`). True when there was one.
    func discardOrphanedSession() async -> Bool {
        guard session == nil, await recover(mirror: false) else { return false }
        discard()
        return true
    }

    /// The `HKWorkout` already saved for `workoutId`, found by its external
    /// UUID among the workouts this app saved, so recovery never saves a
    /// second one. A query error is `failed`, not `notFound`: the caller must
    /// not queue without a UUID then.
    func savedWorkout(workoutId: String) async -> SavedWorkoutLookup {
        guard HKHealthStore.isHealthDataAvailable() else { return .notFound }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [workoutId]),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil
            ) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: .failed)
                } else if let uuid = samples?.first?.uuid.uuidString.lowercased() {
                    continuation.resume(returning: .found(uuid))
                } else {
                    continuation.resume(returning: .notFound)
                }
            }
            store.execute(query)
        }
    }

    private func clear() {
        isMirroring = false
        session = nil
        builder = nil
        workoutId = nil
    }
}

extension WorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    /// The iPhone sent live data (a `session_command`) through the mirrored session.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor [weak self] in
            for item in data { self?.onRemoteMessage?(item) }
        }
    }

    /// The mirror dropped (the iPhone app ended it or went out of reach); live
    /// messages use WatchConnectivity until the workout ends.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.isMirroring = false
        }
    }
}

/// Runs a body once, from whichever thread gets there first.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        var latestBpm: Int?
        var latestKcal: Double?
        var latestAverage: Int?
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                let statistics = workoutBuilder.statistics(for: quantityType)
            else { continue }
            if quantityType == HKQuantityType(.heartRate) {
                let unit = HKUnit.count().unitDivided(by: .minute())
                latestBpm = statistics.mostRecentQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
                latestAverage = statistics.averageQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
            } else if quantityType == HKQuantityType(.activeEnergyBurned) {
                latestKcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            }
        }
        // Immutable copies: the Task closure must not capture mutable vars.
        let bpm = latestBpm
        let kcal = latestKcal
        let average = latestAverage
        Task { @MainActor [weak self] in
            if let bpm { self?.heartRate = bpm }
            if let kcal { self?.activeKilocalories = kcal }
            if let average { self?.averageHeartRate = average }
        }
    }
}

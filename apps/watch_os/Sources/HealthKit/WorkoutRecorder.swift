import Foundation
import HealthKit

/// The thin HealthKit wrapper that owns the live workout session. It holds no
/// workout rules (those are in `WorkoutController`). Permissions are the
/// minimum: share `workoutType()`; read heart rate and active energy. Heart
/// rate and energy stay on the watch: the completed workout carries only the
/// saved `HKWorkout` UUID.
@MainActor
final class WorkoutRecorder: NSObject, ObservableObject {
    @Published private(set) var heartRate: Int?
    @Published private(set) var activeKilocalories: Double?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var workoutId: String?

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
    ]

    /// Asks once; true when the person allowed saving workouts. Denied or
    /// unavailable HealthKit is not an error: the workout still records.
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: Self.readTypes)
        } catch {
            return false
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
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
        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends the session and saves one `HKWorkout` that carries the BeyondRep
    /// workout id in `HKMetadataKeyExternalUUID`. Returns its UUID (lowercase),
    /// or nil when HealthKit is unavailable, denied or failed.
    func finish(at date: Date) async -> String? {
        guard let session, let builder else { return nil }
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
        session?.end()
        builder?.discardWorkout()
        clear()
    }

    /// Reattaches to a session HealthKit kept alive while the app was not
    /// running. `workoutId` is the BeyondRep workout it belongs to.
    func recover(workoutId: String? = nil) async -> Bool {
        do {
            guard let recovered = try await store.recoverActiveWorkoutSession() else { return false }
            let builder = recovered.associatedWorkoutBuilder()
            recovered.delegate = self
            builder.delegate = self
            session = recovered
            self.builder = builder
            if let workoutId { self.workoutId = workoutId }
            return true
        } catch {
            return false
        }
    }

    /// The UUID of the `HKWorkout` already saved for `workoutId`, found by its
    /// external UUID, so recovery never saves a second one.
    func savedWorkoutUuid(workoutId: String) async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [workoutId])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first?.uuid.uuidString.lowercased())
            }
            store.execute(query)
        }
    }

    private func clear() {
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
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        var bpm: Int?
        var kcal: Double?
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                let statistics = workoutBuilder.statistics(for: quantityType)
            else { continue }
            if quantityType == HKQuantityType(.heartRate) {
                let unit = HKUnit.count().unitDivided(by: .minute())
                bpm = statistics.mostRecentQuantity().map { Int($0.doubleValue(for: unit).rounded()) }
            } else if quantityType == HKQuantityType(.activeEnergyBurned) {
                kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            }
        }
        Task { @MainActor [weak self] in
            if let bpm { self?.heartRate = bpm }
            if let kcal { self?.activeKilocalories = kcal }
        }
    }
}

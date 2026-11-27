import Foundation
import HealthKit
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Reads today's sleep, steps, HRV and resting heart rate from the watch's own
/// HealthKit store for the Home tiles. A thin mapping: the day rules are in
/// `WatchHealthDerivation` (tested with the golden cases). Nothing is stored,
/// logged or sent; the result lives in `AppModel` memory only. A query that
/// fails or has no permission leaves only its own value missing; `read` also
/// names the fields whose query returned an error, so the app can keep the
/// value it already holds for them.
final class HealthGlanceReader {
    private let store = HKHealthStore()

    /// True when HealthKit has not yet asked about the glance's types.
    func shouldRequestAuthorization() async -> Bool {
        await HealthAccess.shouldRequest(store: store)
    }

    func requestAuthorization() async {
        _ = await HealthAccess.request(store: store)
    }

    func read(now: Date, timeZone: TimeZone) async -> (health: WatchHealth, failed: Set<WatchHealthField>) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = calendar.startOfDay(for: now)
        // Last night starts the evening before, so look back to noon yesterday.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight.addingTimeInterval(-86_400)
        let noonYesterday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday) ?? yesterday

        async let sleepSamples = self.samples(HKCategoryType(.sleepAnalysis), from: noonYesterday, to: now)
        async let hrvSamples = self.samples(HKQuantityType(.heartRateVariabilitySDNN), from: noonYesterday, to: now)
        async let rhrSamples = self.samples(HKQuantityType(.restingHeartRate), from: midnight, to: now)
        async let steps = self.stepCount(from: midnight, to: now)

        let sleepRead = await sleepSamples
        let hrvRead = await hrvSamples
        let rhrRead = await rhrSamples
        let stepsRead = await steps
        // The HRV rule needs the night, so a failed sleep read fails both.
        var failed = Set<WatchHealthField>()
        if sleepRead == nil { failed.formUnion([.asleep, .hrv]) }
        if hrvRead == nil { failed.insert(.hrv) }
        if rhrRead == nil { failed.insert(.restingHr) }
        if stepsRead == nil { failed.insert(.steps) }

        let sleep = (sleepRead ?? []).compactMap { sample -> SleepSample? in
            guard let category = sample as? HKCategorySample, let stage = Self.stage(category.value) else {
                return nil
            }
            return SleepSample(
                from: category.startDate, to: category.endDate, stage: stage,
                sourceKey: category.sourceRevision.source.bundleIdentifier)
        }
        let health = WatchHealthDerivation.today(
            sleep: sleep,
            hrv: Self.values(hrvRead ?? [], unit: .secondUnit(with: .milli)),
            restingHr: Self.values(rhrRead ?? [], unit: .count().unitDivided(by: .minute())),
            steps: stepsRead, now: now, timeZone: timeZone)
        return (health, failed)
    }

    private static func stage(_ rawValue: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .light
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .awake: return .awake
        default: return nil
        }
    }

    private static func values(_ samples: [HKSample], unit: HKUnit) -> [ValueSample] {
        samples.compactMap { sample in
            (sample as? HKQuantitySample).map {
                ValueSample(from: $0.startDate, to: $0.endDate, value: $0.quantity.doubleValue(for: unit))
            }
        }
    }

    /// Samples overlapping the window; nil when the query returned an error.
    private func samples(_ type: HKSampleType, from start: Date, to end: Date) async -> [HKSample]? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                continuation.resume(returning: error == nil ? (samples ?? []) : nil)
            }
            store.execute(query)
        }
    }

    /// HealthKit's own sum (it merges overlapping sources); 0 when there are no
    /// samples (HealthKit reports that as errorNoData, which is not a failure);
    /// nil on any other error.
    private func stepCount(from start: Date, to end: Date) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    let noData = (error as? HKError)?.code == .errorNoData
                    continuation.resume(returning: noData ? 0 : nil)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                }
            }
            store.execute(query)
        }
    }
}

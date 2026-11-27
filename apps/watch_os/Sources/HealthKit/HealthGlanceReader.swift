import Foundation
import HealthKit
#if canImport(BeyondRepWatchCore)
import BeyondRepWatchCore
#endif

/// Reads today's sleep, steps, HRV and resting heart rate from the watch's own
/// HealthKit store for the Home tiles. A thin mapping: the day rules are in
/// `WatchHealthDerivation` (tested with the golden cases). Nothing is stored,
/// logged or sent; the result lives in `AppModel` memory only. A query that
/// fails or has no permission leaves only its own value missing.
final class HealthGlanceReader {
    private let store = HKHealthStore()

    /// True when HealthKit has not yet asked about the glance's types.
    func shouldRequestAuthorization() async -> Bool {
        await HealthAccess.shouldRequest(store: store)
    }

    func requestAuthorization() async {
        _ = await HealthAccess.request(store: store)
    }

    func read(now: Date, timeZone: TimeZone) async -> WatchHealth {
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

        let sleep = await sleepSamples.compactMap { sample -> SleepSample? in
            guard let category = sample as? HKCategorySample, let stage = Self.stage(category.value) else {
                return nil
            }
            return SleepSample(
                from: category.startDate, to: category.endDate, stage: stage,
                sourceKey: category.sourceRevision.source.bundleIdentifier)
        }
        return WatchHealthDerivation.today(
            sleep: sleep,
            hrv: Self.values(await hrvSamples, unit: .secondUnit(with: .milli)),
            restingHr: Self.values(await rhrSamples, unit: .count().unitDivided(by: .minute())),
            steps: await steps, now: now, timeZone: timeZone)
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

    /// Samples overlapping the window; empty on any error.
    private func samples(_ type: HKSampleType, from start: Date, to end: Date) async -> [HKSample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    /// HealthKit's own sum (it merges overlapping sources); nil on any error.
    private func stepCount(from start: Date, to end: Date) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            store.execute(query)
        }
    }
}

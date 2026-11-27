import Foundation

/// Sleep stages as the phone names them (`SleepStage` in
/// `sleep_nights.dart`); the raw values are the golden-case spellings.
public enum SleepStage: String, Equatable {
    case light, deep, rem
    case asleepUnspecified = "asleep_unspecified"
    case awake
    case inBed = "in_bed"
}

public struct SleepSample: Equatable {
    public let from: Date
    public let to: Date
    public let stage: SleepStage
    /// The writing app (bundle identifier); tells sources apart.
    public let sourceKey: String

    public init(from: Date, to: Date, stage: SleepStage, sourceKey: String) {
        self.from = from
        self.to = to
        self.stage = stage
        self.sourceKey = sourceKey
    }
}

public struct ValueSample: Equatable {
    public let from: Date
    public let to: Date
    public let value: Double

    public init(from: Date, to: Date, value: Double) {
        self.from = from
        self.to = to
        self.value = value
    }
}

/// What the watch read from its own HealthKit store for one local date. Held
/// in memory only: never written to the journal, sent to the phone or logged.
/// A value the watch could not read is nil, never 0.
public struct WatchHealth: Equatable {
    public let localDate: String
    public let asleepMinutes: Int?
    public let restingHrBpm: Int?
    public let hrvMs: Int?
    public let steps: Int?

    public init(
        localDate: String, asleepMinutes: Int? = nil, restingHrBpm: Int? = nil, hrvMs: Int? = nil,
        steps: Int? = nil
    ) {
        self.localDate = localDate
        self.asleepMinutes = asleepMinutes
        self.restingHrBpm = restingHrBpm
        self.hrvMs = hrvMs
        self.steps = steps
    }

    public var hasAnyValue: Bool {
        asleepMinutes != nil || restingHrBpm != nil || hrvMs != nil || steps != nil
    }
}

/// Today's four numbers after combining the phone's snapshot with what the
/// watch read (ADR-0012 decision 4, amendment 2026-11-27).
enum HealthMerge {
    struct Today: Equatable {
        var sleepMinutes: Int?
        var restingHr: Int?
        var hrv: Int?
        var steps: Int?
    }

    static func int(_ value: Any?) -> Int? { (value as? NSNumber).map { $0.intValue } }

    /// The phone's value wins for sleep, resting heart rate and HRV; the watch
    /// fills in what the phone did not send. Steps take the larger of the two,
    /// since they only grow during a day and each store may lack the other
    /// device's samples. [watch] must already be for today's local date.
    static func today(snapshot raw: [String: Any]?, watch: WatchHealth?) -> Today {
        let phoneSteps = int(raw?["steps"])
        let steps: Int?
        switch (phoneSteps, watch?.steps) {
        case (let p?, let w?): steps = max(p, w)
        case (let p?, nil): steps = p
        case (nil, let w): steps = w
        }
        return Today(
            sleepMinutes: int((raw?["sleep"] as? [String: Any])?["asleep_minutes"]) ?? watch?.asleepMinutes,
            restingHr: int(raw?["resting_hr_bpm"]) ?? watch?.restingHrBpm,
            hrv: int(raw?["hrv_ms"]) ?? watch?.hrvMs,
            steps: steps)
    }
}

/// A value of `WatchHealth` whose HealthKit query can fail.
public enum WatchHealthField: Hashable {
    case asleep, restingHr, hrv, steps
}

/// What the app keeps in memory between reads, with the account it was read
/// for. The watch is bound to one account at a time, so a sign out or a
/// rebind to another account must never show these values.
public struct HeldWatchHealth: Equatable {
    public let accountKey: String
    public let health: WatchHealth

    public init(accountKey: String, health: WatchHealth) {
        self.accountKey = accountKey
        self.health = health
    }

    /// The values while [boundKey] (the bound account, nil when unbound) is
    /// still the account they were read for; nil otherwise.
    public func ifCurrent(boundKey: String?) -> WatchHealth? {
        boundKey == accountKey ? health : nil
    }

    /// The held values after a new read. A field in [failed] (its query
    /// returned an error, not "no data") that the read left missing keeps the
    /// value held now, when that is for the same account and local date.
    public func updated(accountKey newKey: String, read: WatchHealth, failed: Set<WatchHealthField>)
        -> HeldWatchHealth
    {
        guard newKey == accountKey, read.localDate == health.localDate else {
            return HeldWatchHealth(accountKey: newKey, health: read)
        }
        let merged = WatchHealth(
            localDate: read.localDate,
            asleepMinutes: read.asleepMinutes ?? (failed.contains(.asleep) ? health.asleepMinutes : nil),
            restingHrBpm: read.restingHrBpm ?? (failed.contains(.restingHr) ? health.restingHrBpm : nil),
            hrvMs: read.hrvMs ?? (failed.contains(.hrv) ? health.hrvMs : nil),
            steps: read.steps ?? (failed.contains(.steps) ? health.steps : nil))
        return HeldWatchHealth(accountKey: newKey, health: merged)
    }
}

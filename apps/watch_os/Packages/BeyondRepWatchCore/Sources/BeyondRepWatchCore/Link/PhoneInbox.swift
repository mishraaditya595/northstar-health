import Foundation

/// Decodes what the phone sends (application context and user info) and stores
/// it in the journal. Nothing here throws for a bad entry: it is skipped and
/// counted. Plans and health for any account other than the stored binding are
/// dropped, so one account's data never shows under another.
public final class PhoneInbox {
    private let journal: WatchJournal
    /// Entries that could not be decoded or did not match their key (for tests).
    public private(set) var rejectedCount = 0
    /// Well-formed entries that were not applied because a newer binding or a
    /// later clear for the account is already stored (for tests).
    public private(set) var ignoredCount = 0
    /// One entry per applied `ack` for a completed workout, so the app can refresh.
    public private(set) var lastAckEffects: [AckEffect] = []

    public init(journal: WatchJournal) {
        self.journal = journal
    }

    /// Context keys are message types and each value is a JSON string. The
    /// binding is applied first because dictionary order is arbitrary.
    /// Returns one outcome for each message handled, in that order, for the
    /// watch to acknowledge. Undecodable entries have no outcome.
    @discardableResult
    public func receive(applicationContext: [String: Any], now: Date = Date()) throws -> [AckOutcome] {
        var outcomes: [AckOutcome] = []
        for type in ["account_binding", "account_cleared", "plans_snapshot", "health_snapshot"] {
            guard let value = applicationContext[type] else { continue }
            guard let message = decode(value), message.type == type else {
                rejectedCount += 1
                continue
            }
            if let outcome = try apply(message, now: now) { outcomes.append(outcome) }
        }
        return outcomes
    }

    /// One-off messages arrive as `["json": String]`.
    @discardableResult
    public func receive(userInfo: [String: Any], now: Date = Date()) throws -> [AckOutcome] {
        guard let message = decode(userInfo["json"]) else {
            rejectedCount += 1
            return []
        }
        return try apply(message, now: now).map { [$0] } ?? []
    }

    private func decode(_ value: Any?) -> WatchMessage? {
        guard let text = value as? String else { return nil }
        return try? WatchMessage(json: Data(text.utf8))
    }

    private func apply(_ message: WatchMessage, now: Date) throws -> AckOutcome? {
        func outcome(_ result: String, _ reason: String? = nil) -> AckOutcome {
            AckOutcome(
                messageId: message.messageId.lowercased(), accountKey: message.accountKey, result: result,
                reason: reason)
        }
        // Only data that was newly stored counts as received: the launch
        // replay of the last context is all duplicates and says nothing about
        // when the phone last sent.
        func received() throws {
            try journal.recordReceived(atMs: Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))
        }
        switch message.body {
        case .accountBinding:
            // Application context and user info are separate, unordered
            // channels, and the watch replays the last context on launch, so
            // only send times decide what is current.
            guard let sentAt = WatchTimestamp.milliseconds(message.sentAtUtc) else {
                rejectedCount += 1
                return nil
            }
            if let clearedAt = try journal.clearedAt(message.accountKey), sentAt <= clearedAt {
                ignoredCount += 1  // sent before the account was cleared
                return nil
            }
            if let current = try journal.bindingState() {
                if current.messageId == message.messageId.lowercased() {  // already applied
                    return outcome("duplicate")
                }
                if sentAt < current.sentAtMs {
                    ignoredCount += 1  // older than the binding in place
                    return nil
                }
                if current.accountKey != message.accountKey {
                    // Unsent workouts of the previous account stay (wipeUnsent: false).
                    try journal.clearAccount(current.accountKey, wipeUnsent: false)
                }
            }
            try journal.saveBinding(message)
            try received()
            return outcome("stored")
        case .accountCleared(let wipeUnsent):
            guard let sentAt = WatchTimestamp.milliseconds(message.sentAtUtc) else {
                rejectedCount += 1
                return nil
            }
            try journal.recordCleared(message.accountKey, sentAtMs: sentAt)
            // A clear older than the binding in place is late: that binding is
            // newer, so it stays. Account deletion always applies, because a
            // deleted account is never bound again.
            if !wipeUnsent, let current = try journal.bindingState(),
                current.accountKey == message.accountKey, sentAt < current.sentAtMs
            {
                ignoredCount += 1
                return outcome("stored")  // the tombstone is stored
            }
            try journal.clearAccount(message.accountKey, wipeUnsent: wipeUnsent)
            return outcome("stored")
        case .plansSnapshot:
            // Without a binding there is no account to answer for: no ack.
            guard let bound = try journal.binding() else { return nil }
            guard bound.accountKey == message.accountKey else { return outcome("rejected", "wrong_account") }
            if try journal.plans(accountKey: bound.accountKey)?.messageId.lowercased()
                == message.messageId.lowercased()
            {
                return outcome("duplicate")
            }
            try journal.savePlans(message)
            try received()
            return outcome("stored")
        case .healthSnapshot(let localDate, _):
            guard let bound = try journal.binding() else { return nil }
            guard bound.accountKey == message.accountKey else { return outcome("rejected", "wrong_account") }
            if try journal.health(accountKey: bound.accountKey, forLocalDate: localDate)?.messageId.lowercased()
                == message.messageId.lowercased()
            {
                return outcome("duplicate")
            }
            try journal.saveHealth(message)
            try received()
            return outcome("stored")
        case .ack(let ackedMessageId, let result, _):
            // An ack is never acked. It counts only when its account is the
            // one the queued workout was recorded under.
            guard
                let queuedKey = try journal.queuedCompletedAccountKey(messageId: ackedMessageId)
                    ?? journal.queuedLinkAccountKey(messageId: ackedMessageId)
            else {
                return nil  // already applied, or never queued: nothing changes
            }
            guard queuedKey == message.accountKey else {
                ignoredCount += 1
                return nil
            }
            if let effect = try journal.applyAck(ackedMessageId: ackedMessageId, result: result) {
                lastAckEffects.append(effect)
            }
            return nil
        default:
            rejectedCount += 1  // watch-bound types are not phone-to-watch glance data yet
            return nil
        }
    }
}

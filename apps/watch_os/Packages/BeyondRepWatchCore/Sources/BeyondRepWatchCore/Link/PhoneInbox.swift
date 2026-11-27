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

    public init(journal: WatchJournal) {
        self.journal = journal
    }

    /// Context keys are message types and each value is a JSON string. The
    /// binding is applied first because dictionary order is arbitrary.
    public func receive(applicationContext: [String: Any]) throws {
        for type in ["account_binding", "account_cleared", "plans_snapshot", "health_snapshot"] {
            guard let value = applicationContext[type] else { continue }
            guard let message = decode(value), message.type == type else {
                rejectedCount += 1
                continue
            }
            try apply(message)
        }
    }

    /// One-off messages arrive as `["json": String]`.
    public func receive(userInfo: [String: Any]) throws {
        guard let message = decode(userInfo["json"]) else {
            rejectedCount += 1
            return
        }
        try apply(message)
    }

    private func decode(_ value: Any?) -> WatchMessage? {
        guard let text = value as? String else { return nil }
        return try? WatchMessage(json: Data(text.utf8))
    }

    private func apply(_ message: WatchMessage) throws {
        switch message.body {
        case .accountBinding:
            // Application context and user info are separate, unordered
            // channels, and the watch replays the last context on launch, so
            // only send times decide what is current.
            guard let sentAt = WatchTimestamp.milliseconds(message.sentAtUtc) else {
                rejectedCount += 1
                return
            }
            if let clearedAt = try journal.clearedAt(message.accountKey), sentAt <= clearedAt {
                ignoredCount += 1  // sent before the account was cleared
                return
            }
            if let current = try journal.bindingState() {
                if current.messageId == message.messageId.lowercased() { return }  // already applied
                if sentAt < current.sentAtMs {
                    ignoredCount += 1  // older than the binding in place
                    return
                }
                if current.accountKey != message.accountKey {
                    // Unsent workouts of the previous account stay (wipeUnsent: false).
                    try journal.clearAccount(current.accountKey, wipeUnsent: false)
                }
            }
            try journal.saveBinding(message)
        case .accountCleared(let wipeUnsent):
            guard let sentAt = WatchTimestamp.milliseconds(message.sentAtUtc) else {
                rejectedCount += 1
                return
            }
            try journal.recordCleared(message.accountKey, sentAtMs: sentAt)
            // A clear older than the binding in place is late: that binding is
            // newer, so it stays. Account deletion always applies, because a
            // deleted account is never bound again.
            if !wipeUnsent, let current = try journal.bindingState(),
                current.accountKey == message.accountKey, sentAt < current.sentAtMs
            {
                ignoredCount += 1
                return
            }
            try journal.clearAccount(message.accountKey, wipeUnsent: wipeUnsent)
        case .plansSnapshot:
            guard try journal.binding()?.accountKey == message.accountKey else { return }
            try journal.savePlans(message)
        case .healthSnapshot:
            guard try journal.binding()?.accountKey == message.accountKey else { return }
            try journal.saveHealth(message)
        default:
            rejectedCount += 1  // watch-bound types are not phone-to-watch glance data yet
        }
    }
}

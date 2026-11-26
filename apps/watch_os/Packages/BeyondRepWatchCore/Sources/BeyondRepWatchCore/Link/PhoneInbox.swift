import Foundation

/// Decodes what the phone sends (application context and user info) and stores
/// it in the journal. Nothing here throws for a bad entry: it is skipped and
/// counted. Plans and health for any account other than the stored binding are
/// dropped, so one account's data never shows under another.
public final class PhoneInbox {
    private let journal: WatchJournal
    /// Entries that could not be decoded or did not match their key (for tests).
    public private(set) var rejectedCount = 0

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
            if let current = try journal.binding(), current.accountKey != message.accountKey {
                // Unsent workouts of the previous account stay (wipeUnsent: false).
                try journal.clearAccount(current.accountKey, wipeUnsent: false)
            }
            try journal.saveBinding(message)
        case .accountCleared(let wipeUnsent):
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

import Foundation

/// What the watch did with one phone message, to send back as an `ack`. It
/// holds ids and a result only, never a health value.
public struct AckOutcome: Equatable {
    public let messageId: String
    public let accountKey: String
    /// `stored`, `duplicate` or `rejected`.
    public let result: String
    /// `wrong_account` for a rejected message, otherwise nil.
    public let reason: String?

    public init(messageId: String, accountKey: String, result: String, reason: String?) {
        self.messageId = messageId
        self.accountKey = accountKey
        self.result = result
        self.reason = reason
    }
}

public enum AckBuilder {
    /// A valid watch_link `ack` message as JSON text, for `transferUserInfo`.
    public static func json(for outcome: AckOutcome, messageId: UUID, now: Date) -> String {
        let message = WatchMessage(
            messageId: messageId.uuidString.lowercased(), sentAtUtc: ISO8601DateFormatter().string(from: now),
            accountKey: outcome.accountKey,
            body: .ack(ackedMessageId: outcome.messageId, result: outcome.result, reason: outcome.reason))
        // The body is built from validated parts, so encoding cannot fail.
        return String(decoding: (try? message.jsonData()) ?? Data(), as: UTF8.self)
    }
}

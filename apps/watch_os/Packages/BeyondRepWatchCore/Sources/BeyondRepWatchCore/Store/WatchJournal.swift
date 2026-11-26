import Foundation

public enum JournalError: Error, Equatable {
    case unknownSession
    case injectedFailure
}

/// The watch's durable store: event journal, outbound message queue (outbox),
/// session state, and the phone's plans and today's health snapshot. One
/// transaction per user action writes state and the outbound message together,
/// so after a crash both exist or neither does.
public final class WatchJournal {
    private let db: SQLiteDatabase
    private let clock: () -> Date
    private let makeId: () -> String

    /// Test hook: throw after the event row is inserted, before the outbox row.
    var failAfterEventInsert = false

    public init(
        url: URL, clock: @escaping () -> Date = Date.init,
        makeId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) throws {
        db = try SQLiteDatabase(url: url)
        self.clock = clock
        self.makeId = makeId
        try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS events(event_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, sequence INTEGER NOT NULL, json TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS outbox(message_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, json TEXT NOT NULL, created_at TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS sessions(session_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, status TEXT NOT NULL, state_json TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS plans(account_key TEXT PRIMARY KEY, json TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS health(account_key TEXT PRIMARY KEY, local_date TEXT NOT NULL, json TEXT NOT NULL)")
            try db.setUserVersion(1)
        }
    }

    private func encode(_ message: WatchMessage) throws -> String {
        String(decoding: try message.jsonData(), as: UTF8.self)
    }

    private func decode(_ text: String) throws -> WatchMessage {
        try WatchMessage(json: Data(text.utf8))
    }

    private func now() -> String { ISO8601DateFormatter().string(from: clock()) }

    private func enqueue(_ message: WatchMessage) throws {
        try db.execute(
            "INSERT OR IGNORE INTO outbox(message_id, account_key, json, created_at) VALUES(?,?,?,?)",
            [.text(message.messageId.lowercased()), .text(message.accountKey), .text(try encode(message)), .text(now())])
    }

    /// Stores the event, queues it for the phone and saves the session state in
    /// one transaction. A repeated event id changes nothing. A `completed`
    /// message (the final workout) is queued in the same transaction.
    public func record(
        _ event: WorkoutEventV2, sessionState: ReplayedWorkout, completed: WatchMessage? = nil
    ) throws {
        try db.transaction {
            let header = event.header
            let accountKey: String
            if case .workoutStarted(_, let payload) = event {
                accountKey = payload.accountKey
            } else {
                let rows = try db.query("SELECT account_key FROM sessions WHERE session_id = ?", [.text(header.sessionId)])
                guard case .text(let key)? = rows.first?.first else { throw JournalError.unknownSession }
                accountKey = key
            }
            let inserted = try db.execute(
                "INSERT OR IGNORE INTO events(event_id, session_id, sequence, json) VALUES(?,?,?,?)",
                [.text(header.eventId), .text(header.sessionId), .int(Int64(header.sequence)),
                 .text(String(decoding: try event.jsonData(), as: UTF8.self))])
            if inserted == 0 { return }
            if failAfterEventInsert { throw JournalError.injectedFailure }
            try enqueue(WatchMessage(
                messageId: makeId(), sentAtUtc: now(), accountKey: accountKey, body: .workoutEvent(event)))
            if let completed { try enqueue(completed) }
            let state = String(decoding: try JSONEncoder().encode(sessionState), as: UTF8.self)
            try db.execute(
                "INSERT INTO sessions(session_id, account_key, status, state_json) VALUES(?,?,?,?) "
                    + "ON CONFLICT(session_id) DO UPDATE SET status = excluded.status, state_json = excluded.state_json",
                [.text(header.sessionId), .text(accountKey), .text(sessionState.status), .text(state)])
        }
    }

    public func pendingOutbox(limit: Int) throws -> [WatchMessage] {
        try db.query("SELECT json FROM outbox ORDER BY rowid LIMIT ?", [.int(Int64(limit))]).compactMap { (row: [SQLValue]) -> WatchMessage? in
            guard case .text(let text)? = row.first else { return nil }
            return try decode(text)
        }
    }

    /// Removes the acknowledged message; acknowledging twice does nothing.
    public func acknowledge(messageId: UUID) throws {
        try db.execute("DELETE FROM outbox WHERE message_id = ?", [.text(messageId.uuidString.lowercased())])
    }

    /// Queues a completed workout for the phone.
    public func saveCompleted(_ message: WatchMessage) throws {
        try db.transaction { try enqueue(message) }
    }

    public func savePlans(_ message: WatchMessage) throws {
        guard case .plansSnapshot = message.body else { throw ContractError("invalid_value") }
        try db.execute(
            "INSERT OR REPLACE INTO plans(account_key, json) VALUES(?,?)",
            [.text(message.accountKey), .text(try encode(message))])
    }

    public func plans(accountKey: String) throws -> WatchMessage? {
        let rows = try db.query("SELECT json FROM plans WHERE account_key = ?", [.text(accountKey)])
        guard case .text(let text)? = rows.first?.first else { return nil }
        return try decode(text)
    }

    public func saveHealth(_ message: WatchMessage) throws {
        guard case .healthSnapshot(let localDate, _) = message.body else { throw ContractError("invalid_value") }
        try db.execute(
            "INSERT OR REPLACE INTO health(account_key, local_date, json) VALUES(?,?,?)",
            [.text(message.accountKey), .text(localDate), .text(try encode(message))])
    }

    /// Today's snapshot only: any other date, even a stored one, is nil.
    public func health(accountKey: String, forLocalDate localDate: String) throws -> WatchMessage? {
        let rows = try db.query(
            "SELECT json FROM health WHERE account_key = ? AND local_date = ?",
            [.text(accountKey), .text(localDate)])
        guard case .text(let text)? = rows.first?.first else { return nil }
        return try decode(text)
    }

    /// Drops the plans and health snapshot for `key`. With `wipeUnsent` (account
    /// deletion only) it also drops that key's sessions, events and queue.
    public func clearAccount(_ key: String, wipeUnsent: Bool) throws {
        try db.transaction {
            try db.execute("DELETE FROM plans WHERE account_key = ?", [.text(key)])
            try db.execute("DELETE FROM health WHERE account_key = ?", [.text(key)])
            guard wipeUnsent else { return }
            try db.execute(
                "DELETE FROM events WHERE session_id IN (SELECT session_id FROM sessions WHERE account_key = ?)",
                [.text(key)])
            try db.execute("DELETE FROM sessions WHERE account_key = ?", [.text(key)])
            try db.execute("DELETE FROM outbox WHERE account_key = ?", [.text(key)])
        }
    }

    /// The newest active or paused session with its events and replayed state.
    public func activeSession() throws -> (events: [WorkoutEventV2], state: ReplayedWorkout)? {
        let rows = try db.query(
            "SELECT session_id FROM sessions WHERE status IN ('active','paused') ORDER BY rowid DESC LIMIT 1")
        guard case .text(let sessionId)? = rows.first?.first else { return nil }
        let events = try db.query(
            "SELECT json FROM events WHERE session_id = ? ORDER BY sequence", [.text(sessionId)]
        ).compactMap { row -> WorkoutEventV2? in
            guard case .text(let text) = row[0] else { return nil }
            return try? WorkoutEventV2(json: Data(text.utf8))
        }
        return (events, replay(events))
    }
}

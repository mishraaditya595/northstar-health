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

    /// Where a test makes `record` throw, to prove the transaction rolls back.
    enum FailurePoint: Equatable {
        /// After the event at this batch index is inserted, before its outbox row.
        case afterEventInsert(index: Int)
        case afterCompletedEnqueue
        case afterSessionUpsert
    }

    var failAt: FailurePoint?

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
            try db.execute("CREATE TABLE IF NOT EXISTS applied_commands(session_id TEXT NOT NULL, command_id TEXT NOT NULL, PRIMARY KEY(session_id, command_id))")
            try db.execute("CREATE TABLE IF NOT EXISTS health(account_key TEXT PRIMARY KEY, local_date TEXT NOT NULL, json TEXT NOT NULL)")
            // Version 3 adds the account binding. Tables are created only when
            // missing, so a version 2 database keeps every row.
            try db.execute("CREATE TABLE IF NOT EXISTS binding(slot INTEGER PRIMARY KEY CHECK(slot = 1), account_key TEXT NOT NULL, unit TEXT NOT NULL)")
            try db.setUserVersion(3)
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

    /// Stores the events (one session, in order), queues each for the phone and
    /// saves the session state in one transaction: if anything throws, nothing
    /// is written. An event id already stored is skipped; if every event is a
    /// repeat nothing changes. `commandId` (a phone command these events
    /// answer) is stored in the same transaction so a late duplicate is ignored
    /// after a restart. A `completed` message (the final workout) is queued in
    /// the same transaction.
    public func record(
        _ events: [WorkoutEventV2], sessionState: ReplayedWorkout, completed: WatchMessage? = nil,
        commandId: String? = nil
    ) throws {
        guard let sessionId = events.first?.header.sessionId else { return }
        try db.transaction {
            var accountKey: String?
            for case .workoutStarted(_, let payload) in events { accountKey = payload.accountKey }
            if accountKey == nil {
                let rows = try db.query("SELECT account_key FROM sessions WHERE session_id = ?", [.text(sessionId)])
                guard case .text(let key)? = rows.first?.first else { throw JournalError.unknownSession }
                accountKey = key
            }
            guard let accountKey else { throw JournalError.unknownSession }
            var inserted = 0
            for (index, event) in events.enumerated() {
                let header = event.header
                guard header.sessionId == sessionId else { throw JournalError.unknownSession }
                let changed = try db.execute(
                    "INSERT OR IGNORE INTO events(event_id, session_id, sequence, json) VALUES(?,?,?,?)",
                    [.text(header.eventId), .text(header.sessionId), .int(Int64(header.sequence)),
                     .text(String(decoding: try event.jsonData(), as: UTF8.self))])
                if changed == 0 { continue }
                inserted += 1
                if failAt == .afterEventInsert(index: index) { throw JournalError.injectedFailure }
                try enqueue(WatchMessage(
                    messageId: makeId(), sentAtUtc: now(), accountKey: accountKey, body: .workoutEvent(event)))
            }
            if inserted == 0 { return }
            if let completed {
                try enqueue(completed)
                if failAt == .afterCompletedEnqueue { throw JournalError.injectedFailure }
            }
            let state = String(decoding: try JSONEncoder().encode(sessionState), as: UTF8.self)
            try db.execute(
                "INSERT INTO sessions(session_id, account_key, status, state_json) VALUES(?,?,?,?) "
                    + "ON CONFLICT(session_id) DO UPDATE SET status = excluded.status, state_json = excluded.state_json",
                [.text(sessionId), .text(accountKey), .text(sessionState.status), .text(state)])
            if failAt == .afterSessionUpsert { throw JournalError.injectedFailure }
            if let commandId {
                try db.execute(
                    "INSERT OR IGNORE INTO applied_commands(session_id, command_id) VALUES(?,?)",
                    [.text(sessionId), .text(commandId.lowercased())])
            }
        }
    }

    public func record(
        _ event: WorkoutEventV2, sessionState: ReplayedWorkout, completed: WatchMessage? = nil,
        commandId: String? = nil
    ) throws {
        try record([event], sessionState: sessionState, completed: completed, commandId: commandId)
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

    /// Remembers which account the phone is signed in as (one row). The
    /// caller clears the previous account first when the key changes.
    public func saveBinding(_ message: WatchMessage) throws {
        guard case .accountBinding(let unit) = message.body else { throw ContractError("invalid_value") }
        try db.execute(
            "INSERT OR REPLACE INTO binding(slot, account_key, unit) VALUES(1,?,?)",
            [.text(message.accountKey), .text(unit)])
    }

    public func binding() throws -> (accountKey: String, unit: String)? {
        let rows = try db.query("SELECT account_key, unit FROM binding WHERE slot = 1")
        guard let row = rows.first, case .text(let key) = row[0], case .text(let unit) = row[1] else { return nil }
        return (key, unit)
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
        try db.transaction {
            try db.execute("DELETE FROM health WHERE local_date != ?", [.text(localDate)])
            try db.execute(
                "INSERT OR REPLACE INTO health(account_key, local_date, json) VALUES(?,?,?)",
                [.text(message.accountKey), .text(localDate), .text(try encode(message))])
        }
    }

    /// Today's snapshot only. Health values are cleared at local midnight
    /// (ADR-0012), so rows for any other date are deleted here, on read and on
    /// save, and are never returned.
    public func health(accountKey: String, forLocalDate localDate: String) throws -> WatchMessage? {
        try db.execute("DELETE FROM health WHERE local_date != ?", [.text(localDate)])
        let rows = try db.query(
            "SELECT json FROM health WHERE account_key = ? AND local_date = ?",
            [.text(accountKey), .text(localDate)])
        guard case .text(let text)? = rows.first?.first else { return nil }
        return try decode(text)
    }

    /// Drops the plans, health snapshot and binding for `key`. With `wipeUnsent` (account
    /// deletion only) it also drops that key's sessions, events and queue.
    public func clearAccount(_ key: String, wipeUnsent: Bool) throws {
        try db.transaction {
            try db.execute("DELETE FROM plans WHERE account_key = ?", [.text(key)])
            try db.execute("DELETE FROM health WHERE account_key = ?", [.text(key)])
            try db.execute("DELETE FROM binding WHERE account_key = ?", [.text(key)])
            guard wipeUnsent else { return }
            try db.execute(
                "DELETE FROM events WHERE session_id IN (SELECT session_id FROM sessions WHERE account_key = ?)",
                [.text(key)])
            try db.execute(
                "DELETE FROM applied_commands WHERE session_id IN (SELECT session_id FROM sessions WHERE account_key = ?)",
                [.text(key)])
            try db.execute("DELETE FROM sessions WHERE account_key = ?", [.text(key)])
            try db.execute("DELETE FROM outbox WHERE account_key = ?", [.text(key)])
        }
    }

    /// `accountKey`'s newest active or paused session with its events, replayed
    /// state and the phone command ids already applied. Another account's
    /// session is never returned.
    public func activeSession(
        accountKey: String
    ) throws -> (events: [WorkoutEventV2], state: ReplayedWorkout, commandIds: Set<String>)? {
        let rows = try db.query(
            "SELECT session_id FROM sessions WHERE account_key = ? AND status IN ('active','paused') "
                + "ORDER BY rowid DESC LIMIT 1", [.text(accountKey)])
        guard case .text(let sessionId)? = rows.first?.first else { return nil }
        let events = try db.query(
            "SELECT json FROM events WHERE session_id = ? ORDER BY sequence", [.text(sessionId)]
        ).compactMap { row -> WorkoutEventV2? in
            guard case .text(let text) = row[0] else { return nil }
            return try? WorkoutEventV2(json: Data(text.utf8))
        }
        let commands = try db.query(
            "SELECT command_id FROM applied_commands WHERE session_id = ?", [.text(sessionId)]
        ).compactMap { row -> String? in
            guard case .text(let text) = row[0] else { return nil }
            return text
        }
        return (events, replay(events), Set(commands))
    }
}

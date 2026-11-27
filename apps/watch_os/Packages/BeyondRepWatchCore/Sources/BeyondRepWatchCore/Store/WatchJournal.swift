import Foundation

/// What an applied `ack` did to a session.
public enum AckEffect: Equatable {
    case delivered(sessionId: String)
    case rejected(sessionId: String)
}

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
            // Version 3 adds the account binding, version 4 its message id and
            // send time plus per-account clear tombstones. Tables are created
            // only when missing and columns added only when absent, so an
            // older database keeps every row.
            try db.execute("CREATE TABLE IF NOT EXISTS binding(slot INTEGER PRIMARY KEY CHECK(slot = 1), account_key TEXT NOT NULL, unit TEXT NOT NULL, message_id TEXT NOT NULL DEFAULT '', sent_at_ms INTEGER NOT NULL DEFAULT 0)")
            let columns = try db.query("PRAGMA table_info(binding)").compactMap { (row: [SQLValue]) -> String? in
                guard row.count > 1, case .text(let name) = row[1] else { return nil }
                return name
            }
            if !columns.contains("sent_at_ms") {
                try db.execute("ALTER TABLE binding ADD COLUMN message_id TEXT NOT NULL DEFAULT ''")
                try db.execute("ALTER TABLE binding ADD COLUMN sent_at_ms INTEGER NOT NULL DEFAULT 0")
            }
            try db.execute("CREATE TABLE IF NOT EXISTS cleared(account_key TEXT PRIMARY KEY, sent_at_ms INTEGER NOT NULL)")
            // Version 5 adds when the watch last stored phone data (the sync line).
            try db.execute("CREATE TABLE IF NOT EXISTS link_state(slot INTEGER PRIMARY KEY CHECK(slot = 1), last_received_ms INTEGER NOT NULL)")
            // Version 6 adds the message type and session to the outbox, and the
            // delivery state and workout template to sessions.
            try Self.addColumn(db, table: "outbox", column: "type", definition: "TEXT NOT NULL DEFAULT ''")
            try Self.addColumn(db, table: "outbox", column: "session_id", definition: "TEXT NOT NULL DEFAULT ''")
            try Self.addColumn(db, table: "sessions", column: "delivery", definition: "TEXT")
            try Self.addColumn(db, table: "sessions", column: "template_json", definition: "TEXT")
            try Self.backfillOutbox(db)
            // Version 7 adds the result of each phone command (`applied` or
            // `rejected` with a reason) and when it was handled.
            try Self.addColumn(db, table: "applied_commands", column: "result", definition: "TEXT NOT NULL DEFAULT 'applied'")
            try Self.addColumn(db, table: "applied_commands", column: "reason", definition: "TEXT")
            try Self.addColumn(db, table: "applied_commands", column: "applied_at_ms", definition: "INTEGER NOT NULL DEFAULT 0")
            try db.setUserVersion(7)
        }
    }

    private static func addColumn(_ db: SQLiteDatabase, table: String, column: String, definition: String) throws {
        let names = try db.query("PRAGMA table_info(\(table))").compactMap { (row: [SQLValue]) -> String? in
            guard row.count > 1, case .text(let name) = row[1] else { return nil }
            return name
        }
        if !names.contains(column) {
            try db.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
        }
    }

    /// Rows written before version 6 have no type or session; fill them from
    /// their JSON so the filtered outbox sees them.
    private static func backfillOutbox(_ db: SQLiteDatabase) throws {
        let rows = try db.query("SELECT message_id, json FROM outbox WHERE type = ''")
        for row in rows {
            guard case .text(let id) = row[0], case .text(let text) = row[1],
                let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
                let type = object["type"] as? String
            else { continue }
            var sessionId = ""
            if let body = object["body"] as? [String: Any], let event = body["event"] as? [String: Any],
                let value = event["session_id"] as? String
            {
                sessionId = value
            }
            try db.execute(
                "UPDATE outbox SET type = ?, session_id = ? WHERE message_id = ?",
                [.text(type), .text(sessionId), .text(id)])
        }
    }

    private func encode(_ message: WatchMessage) throws -> String {
        String(decoding: try message.jsonData(), as: UTF8.self)
    }

    private func decode(_ text: String) throws -> WatchMessage {
        try WatchMessage(json: Data(text.utf8))
    }

    private func now() -> String { ISO8601DateFormatter().string(from: clock()) }

    private func enqueue(_ message: WatchMessage, sessionId: String = "") throws {
        var owner = sessionId
        if owner.isEmpty, case .workoutEvent(let event) = message.body { owner = event.header.sessionId }
        try db.execute(
            "INSERT OR IGNORE INTO outbox(message_id, account_key, json, created_at, type, session_id) VALUES(?,?,?,?,?,?)",
            [.text(message.messageId.lowercased()), .text(message.accountKey), .text(try encode(message)), .text(now()),
             .text(message.type), .text(owner)])
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
        commandId: String? = nil, template: String? = nil
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
                try enqueue(completed, sessionId: sessionId)
                if failAt == .afterCompletedEnqueue { throw JournalError.injectedFailure }
            }
            let state = String(decoding: try JSONEncoder().encode(sessionState), as: UTF8.self)
            try db.execute(
                "INSERT INTO sessions(session_id, account_key, status, state_json) VALUES(?,?,?,?) "
                    + "ON CONFLICT(session_id) DO UPDATE SET status = excluded.status, state_json = excluded.state_json",
                [.text(sessionId), .text(accountKey), .text(sessionState.status), .text(state)])
            if let template {
                try db.execute(
                    "UPDATE sessions SET template_json = ? WHERE session_id = ?", [.text(template), .text(sessionId)])
            }
            // A discarded workout sends nothing: drop whatever was queued for it.
            if sessionState.status == "abandoned" {
                try db.execute("DELETE FROM outbox WHERE session_id = ?", [.text(sessionId)])
            }
            if failAt == .afterSessionUpsert { throw JournalError.injectedFailure }
            if let commandId {
                try insertCommand(sessionId: sessionId, commandId: commandId, result: "applied", reason: nil)
            }
            // A discarded session leaves nothing to resend against; a completed
            // one keeps its rows until the phone's ack, so a resent `finish`
            // stays a duplicate.
            if sessionState.status == "abandoned" {
                try db.execute("DELETE FROM applied_commands WHERE session_id = ?", [.text(sessionId)])
            }
        }
    }

    private func insertCommand(sessionId: String, commandId: String, result: String, reason: String?) throws {
        try db.execute(
            "INSERT OR IGNORE INTO applied_commands(session_id, command_id, result, reason, applied_at_ms) VALUES(?,?,?,?,?)",
            [.text(sessionId), .text(commandId.lowercased()), .text(result),
             reason.map { SQLValue.text($0) } ?? .null,
             .int(Int64((clock().timeIntervalSince1970 * 1000).rounded(.down)))])
    }

    /// Remembers a phone command that changed no event: a rejected one, or one
    /// that had nothing to do. The first result for an id stands.
    public func recordCommand(sessionId: String, commandId: String, result: String, reason: String?) throws {
        try insertCommand(sessionId: sessionId, commandId: commandId, result: result, reason: reason)
    }

    /// What the watch did with a phone command, nil when it never saw the id.
    public func commandResult(sessionId: String, commandId: String) throws -> (result: String, reason: String?)? {
        let rows = try db.query(
            "SELECT result, reason FROM applied_commands WHERE session_id = ? AND command_id = ?",
            [.text(sessionId), .text(commandId.lowercased())])
        guard let row = rows.first, case .text(let result) = row[0] else { return nil }
        if case .text(let reason) = row[1] { return (result, reason) }
        return (result, nil)
    }

    /// Every command the session handled, oldest first.
    public func commandLog(sessionId: String) throws -> [(commandId: String, result: String, reason: String?)] {
        try db.query(
            "SELECT command_id, result, reason FROM applied_commands WHERE session_id = ? ORDER BY rowid",
            [.text(sessionId)]
        ).compactMap { row in
            guard case .text(let id) = row[0], case .text(let result) = row[1] else { return nil }
            if case .text(let reason) = row[2] { return (id, result, reason) }
            return (id, result, nil)
        }
    }

    public func record(
        _ event: WorkoutEventV2, sessionState: ReplayedWorkout, completed: WatchMessage? = nil,
        commandId: String? = nil, template: String? = nil
    ) throws {
        try record(
            [event], sessionState: sessionState, completed: completed, commandId: commandId, template: template)
    }

    public func pendingOutbox(limit: Int) throws -> [WatchMessage] {
        try db.query("SELECT json FROM outbox ORDER BY rowid LIMIT ?", [.int(Int64(limit))]).compactMap { (row: [SQLValue]) -> WatchMessage? in
            guard case .text(let text)? = row.first else { return nil }
            return try decode(text)
        }
    }

    /// Completed workouts waiting for the phone, oldest first. Event messages
    /// in the outbox are not returned.
    public func pendingCompleted(limit: Int) throws -> [WatchMessage] {
        try db.query(
            "SELECT json FROM outbox WHERE type = 'completed_workout' ORDER BY rowid LIMIT ?", [.int(Int64(limit))]
        ).compactMap { (row: [SQLValue]) -> WatchMessage? in
            guard case .text(let text)? = row.first else { return nil }
            return try decode(text)
        }
    }

    /// Queues the finished workout and marks the session `queued` in one
    /// transaction. A second call for the same message changes nothing, and a
    /// session already delivered or rejected stays that way.
    public func queueCompleted(_ message: WatchMessage, sessionId: String) throws {
        try db.transaction {
            try enqueue(message, sessionId: sessionId)
            try db.execute(
                "UPDATE sessions SET delivery = 'queued' WHERE session_id = ? AND delivery IS NULL", [.text(sessionId)])
        }
    }

    /// Applies the phone's `ack` for a completed workout: the message, the
    /// session's other queued messages, its events and applied commands are
    /// deleted and the session is marked `delivered` (`stored`, `duplicate`) or
    /// `rejected`. An unknown or already applied id returns nil.
    public func applyAck(ackedMessageId: String, result: String) throws -> AckEffect? {
        try db.transaction { () throws -> AckEffect? in
            let rows = try db.query(
                "SELECT session_id FROM outbox WHERE message_id = ? AND type = 'completed_workout'",
                [.text(ackedMessageId.lowercased())])
            guard case .text(let sessionId)? = rows.first?.first else { return nil }
            if sessionId.isEmpty {
                try db.execute("DELETE FROM outbox WHERE message_id = ?", [.text(ackedMessageId.lowercased())])
                return nil
            }
            let rejected = result == "rejected"
            try db.execute("DELETE FROM outbox WHERE session_id = ?", [.text(sessionId)])
            try db.execute("DELETE FROM events WHERE session_id = ?", [.text(sessionId)])
            try db.execute("DELETE FROM applied_commands WHERE session_id = ?", [.text(sessionId)])
            try db.execute(
                "UPDATE sessions SET delivery = ? WHERE session_id = ?",
                [.text(rejected ? "rejected" : "delivered"), .text(sessionId)])
            if rejected { return AckEffect.rejected(sessionId: sessionId) }
            return AckEffect.delivered(sessionId: sessionId)
        }
    }

    /// `queued`, `delivered` or `rejected`; nil before the workout is queued.
    public func delivery(sessionId: String) throws -> String? {
        let rows = try db.query("SELECT delivery FROM sessions WHERE session_id = ?", [.text(sessionId)])
        guard case .text(let text)? = rows.first?.first else { return nil }
        return text
    }

    /// Every stored event of a session in sequence order, whatever its status.
    public func events(sessionId: String) throws -> [WorkoutEventV2] {
        try db.query("SELECT json FROM events WHERE session_id = ? ORDER BY sequence", [.text(sessionId)])
            .compactMap { row -> WorkoutEventV2? in
                guard case .text(let text) = row[0] else { return nil }
                return try? WorkoutEventV2(json: Data(text.utf8))
            }
    }

    /// The account key of a queued completed workout, nil when it is not queued.
    public func queuedCompletedAccountKey(messageId: String) throws -> String? {
        let rows = try db.query(
            "SELECT account_key FROM outbox WHERE message_id = ? AND type = 'completed_workout'",
            [.text(messageId.lowercased())])
        guard case .text(let key)? = rows.first?.first else { return nil }
        return key
    }

    /// Sessions of `accountKey` that were completed but whose workout was never
    /// queued (the app stopped between the two steps of finishing).
    public func sessionsAwaitingQueue(accountKey: String) throws -> [String] {
        try db.query(
            "SELECT session_id FROM sessions WHERE account_key = ? AND status = 'completed' AND delivery IS NULL "
                + "ORDER BY rowid", [.text(accountKey)]
        ).compactMap { row in
            guard case .text(let id)? = row.first else { return nil }
            return id
        }
    }

    /// The same, for every account: `(sessionId, accountKey)` pairs. Queueing
    /// needs no binding; only sending does.
    public func allSessionsAwaitingQueue() throws -> [(sessionId: String, accountKey: String)] {
        try db.query(
            "SELECT session_id, account_key FROM sessions WHERE status = 'completed' AND delivery IS NULL "
                + "ORDER BY rowid"
        ).compactMap { row in
            guard case .text(let id)? = row.first, case .text(let key)? = row.last else { return nil }
            return (id, key)
        }
    }

    /// Queued completed workouts, split by whether they belong to `boundKey`.
    public func waitingCounts(boundKey: String?) throws -> (thisAccount: Int, otherAccounts: Int) {
        var mine = 0
        var other = 0
        for row in try db.query("SELECT account_key FROM outbox WHERE type = 'completed_workout'") {
            guard case .text(let key)? = row.first else { continue }
            if let boundKey, key == boundKey { mine += 1 } else { other += 1 }
        }
        return (mine, other)
    }

    /// Saves the template. With `commandId` the phone command that asked for
    /// it is recorded in the same transaction.
    public func saveTemplate(sessionId: String, json: String, commandId: String? = nil) throws {
        try db.transaction {
            try db.execute(
                "UPDATE sessions SET template_json = ? WHERE session_id = ?", [.text(json), .text(sessionId)])
            if let commandId {
                try insertCommand(sessionId: sessionId, commandId: commandId, result: "applied", reason: nil)
            }
        }
    }

    public func template(sessionId: String) throws -> String? {
        let rows = try db.query("SELECT template_json FROM sessions WHERE session_id = ?", [.text(sessionId)])
        guard case .text(let text)? = rows.first?.first else { return nil }
        return text
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
        guard case .accountBinding(let unit) = message.body,
            let sentAtMs = WatchTimestamp.milliseconds(message.sentAtUtc)
        else { throw ContractError("invalid_value") }
        try db.execute(
            "INSERT OR REPLACE INTO binding(slot, account_key, unit, message_id, sent_at_ms) VALUES(1,?,?,?,?)",
            [.text(message.accountKey), .text(unit), .text(message.messageId.lowercased()), .int(sentAtMs)])
    }

    /// The stored binding with the id and send time of the message it came
    /// from (0 for a row written before version 4).
    public func bindingState() throws -> (accountKey: String, messageId: String, sentAtMs: Int64)? {
        let rows = try db.query("SELECT account_key, message_id, sent_at_ms FROM binding WHERE slot = 1")
        guard let row = rows.first, case .text(let key) = row[0], case .text(let id) = row[1],
            case .int(let ms) = row[2]
        else { return nil }
        return (key, id, ms)
    }

    /// When the phone last told the watch `key` was cleared, if ever. A
    /// binding sent before that is stale and must not be applied.
    public func clearedAt(_ key: String) throws -> Int64? {
        let rows = try db.query("SELECT sent_at_ms FROM cleared WHERE account_key = ?", [.text(key)])
        guard case .int(let ms)? = rows.first?.first else { return nil }
        return ms
    }

    /// Remembers a clear, keeping the newest time seen for the key.
    public func recordCleared(_ key: String, sentAtMs: Int64) throws {
        try db.execute(
            "INSERT INTO cleared(account_key, sent_at_ms) VALUES(?,?) "
                + "ON CONFLICT(account_key) DO UPDATE SET sent_at_ms = MAX(sent_at_ms, excluded.sent_at_ms)",
            [.text(key), .int(sentAtMs)])
    }

    /// Remembers when the watch last stored phone data. Only the time is
    /// kept; it drives the "Synced 10:43" line and holds no health values.
    public func recordReceived(atMs: Int64) throws {
        try db.execute(
            "INSERT OR REPLACE INTO link_state(slot, last_received_ms) VALUES(1,?)", [.int(atMs)])
    }

    public func lastReceivedMs() throws -> Int64? {
        let rows = try db.query("SELECT last_received_ms FROM link_state WHERE slot = 1")
        guard case .int(let ms)? = rows.first?.first else { return nil }
        return ms
    }

    /// Deletes every health snapshot that is not for `localDate`.
    public func purgeHealth(exceptLocalDate localDate: String) throws {
        try db.execute("DELETE FROM health WHERE local_date != ?", [.text(localDate)])
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
        try purgeHealth(exceptLocalDate: localDate)
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
            // The received time belongs to the bound account, so it goes with it.
            try db.execute(
                "DELETE FROM link_state WHERE EXISTS (SELECT 1 FROM binding WHERE account_key = ?)", [.text(key)])
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

    /// Drops a binding the phone has not refreshed for `maxSilenceDays`, and
    /// keeps only the newest `maxTombstones` clear tombstones. Returns true
    /// when the binding was dropped. Nothing is dropped while a workout is
    /// active or paused, and unsent workouts are never dropped. The binding's
    /// send time becomes the account's tombstone, so a replay of the old
    /// application context is ignored and is never removed by the cap of
    /// the same call. Tombstones are capped by count, never by age, because the watch replays the last application context on launch.
    @discardableResult
    public func pruneStale(nowMs: Int64, maxSilenceDays: Int = 90, maxTombstones: Int = 20) throws -> Bool {
        try db.transaction { () throws -> Bool in
            var dropped = false
            var droppedKey = ""
            if let binding = try bindingState(), let received = try lastReceivedMs(),
                received < nowMs - Int64(maxSilenceDays) * 86_400_000
            {
                let busy = try db.query(
                    "SELECT 1 FROM sessions WHERE account_key = ? AND status IN ('active','paused') LIMIT 1",
                    [.text(binding.accountKey)])
                if busy.isEmpty {
                    try recordCleared(binding.accountKey, sentAtMs: binding.sentAtMs)
                    try clearAccount(binding.accountKey, wipeUnsent: false)
                    dropped = true
                    droppedKey = binding.accountKey
                }
            }
            // The tombstone just written may be older than the others (it
            // carries the binding's send time), so it is kept and the newest
            // others fill the rest of the cap.
            try db.execute(
                "DELETE FROM cleared WHERE account_key != ? AND account_key NOT IN "
                    + "(SELECT account_key FROM cleared WHERE account_key != ? "
                    + "ORDER BY sent_at_ms DESC, account_key LIMIT ?)",
                [.text(droppedKey), .text(droppedKey), .int(Int64(dropped ? maxTombstones - 1 : maxTombstones))])
            return dropped
        }
    }

    /// `accountKey`'s newest active or paused session with its events, replayed
    /// state and the phone command ids already applied. Another account's
    /// session is never returned.
    public func activeSession(
        accountKey: String
    ) throws -> (sessionId: String, events: [WorkoutEventV2], state: ReplayedWorkout, commandIds: Set<String>)? {
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
        return (sessionId, events, replay(events), Set(commands))
    }
}

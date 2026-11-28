package `in`.beyondrep.wear.core.store

import `in`.beyondrep.wear.core.contracts.ContractException
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import `in`.beyondrep.wear.core.session.ReplayedSet
import `in`.beyondrep.wear.core.session.ReplayedWorkout
import `in`.beyondrep.wear.core.session.WorkoutReplay
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

/** What an applied `ack` did to a session. (Swift also has `linked`; Wear sends no `workout_link`.) */
sealed interface AckEffect {
    data class Delivered(val sessionId: String) : AckEffect
    data class Rejected(val sessionId: String) : AckEffect
}

/**
 * The workout the watch follows on the phone, so a relaunch mid-workout recovers it. `phase` is
 * `following`, or `finishing` once the phone said it finished.
 */
data class FollowerRow(val sessionId: String, val accountKey: String, val joinedAtMs: Long, val phase: String)

data class BindingState(val accountKey: String, val messageId: String, val sentAtMs: Long)
data class Binding(val accountKey: String, val unit: String)
data class CommandResult(val result: String, val reason: String?)
data class CommandLogEntry(val commandId: String, val result: String, val reason: String?)
data class WaitingCounts(val thisAccount: Int, val otherAccounts: Int)
data class SessionAccount(val sessionId: String, val accountKey: String)
data class ActiveSession(
    val sessionId: String,
    val events: List<WorkoutEventV2>,
    val state: ReplayedWorkout,
    val commandIds: Set<String>,
)

class JournalException(message: String) : Exception(message)

/**
 * The watch's durable store: event journal, outbound message queue (outbox), session state, and the
 * phone's plans and today's health snapshot (port of WatchJournal.swift). One transaction per user
 * action writes state and the outbound message together, so after a crash both exist or neither
 * does. The schema is Swift's journal version 8 without the `links` table (Wear sends no
 * `workout_link`), plus `session_health` (stage 3b: the heart rate and calories of a finished
 * workout, kept only until the phone's ack or 7 days); `user_version` 2. Every table is created
 * with IF NOT EXISTS, so a stage 3a database (`user_version` 1) gains the new table and keeps its rows.
 */
class WatchJournal(
    private val db: SqlDatabase,
    private val clock: () -> Instant = Instant::now,
    private val makeId: () -> String = { java.util.UUID.randomUUID().toString().lowercase() },
) {
    init {
        db.transaction {
            db.execute("CREATE TABLE IF NOT EXISTS events(event_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, sequence INTEGER NOT NULL, json TEXT NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS outbox(message_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, json TEXT NOT NULL, created_at TEXT NOT NULL, type TEXT NOT NULL DEFAULT '', session_id TEXT NOT NULL DEFAULT '')")
            db.execute("CREATE TABLE IF NOT EXISTS sessions(session_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, status TEXT NOT NULL, state_json TEXT NOT NULL, delivery TEXT, template_json TEXT)")
            db.execute("CREATE TABLE IF NOT EXISTS plans(account_key TEXT PRIMARY KEY, json TEXT NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS applied_commands(session_id TEXT NOT NULL, command_id TEXT NOT NULL, result TEXT NOT NULL DEFAULT 'applied', reason TEXT, applied_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(session_id, command_id))")
            db.execute("CREATE TABLE IF NOT EXISTS health(account_key TEXT PRIMARY KEY, local_date TEXT NOT NULL, json TEXT NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS binding(slot INTEGER PRIMARY KEY CHECK(slot = 1), account_key TEXT NOT NULL, unit TEXT NOT NULL, message_id TEXT NOT NULL DEFAULT '', sent_at_ms INTEGER NOT NULL DEFAULT 0)")
            db.execute("CREATE TABLE IF NOT EXISTS cleared(account_key TEXT PRIMARY KEY, sent_at_ms INTEGER NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS link_state(slot INTEGER PRIMARY KEY CHECK(slot = 1), last_received_ms INTEGER NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS follower(slot INTEGER PRIMARY KEY CHECK(slot = 1), session_id TEXT NOT NULL, account_key TEXT NOT NULL, joined_at_ms INTEGER NOT NULL, phase TEXT NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS session_health(session_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, message_id TEXT NOT NULL, message_json TEXT NOT NULL, ended_at_ms INTEGER NOT NULL)")
            db.execute("PRAGMA user_version = 2")
        }
    }

    private fun text(v: String) = SqlValue.Text(v)
    private fun int(v: Long) = SqlValue.Int64(v)
    private fun int(v: Int) = SqlValue.Int64(v.toLong())

    private fun textAt(row: List<SqlValue>, index: Int): String? = (row.getOrNull(index) as? SqlValue.Text)?.v
    private fun intAt(row: List<SqlValue>, index: Int): Long? = (row.getOrNull(index) as? SqlValue.Int64)?.v

    private fun now(): String = WatchTimestamp.format(clock())

    private fun enqueue(message: WatchMessage, sessionId: String = "") {
        var owner = sessionId
        val body = message.body
        if (owner.isEmpty() && body is WatchMessageBody.WorkoutEvent) owner = body.event.header.sessionId
        db.execute(
            "INSERT OR IGNORE INTO outbox(message_id, account_key, json, created_at, type, session_id) VALUES(?,?,?,?,?,?)",
            listOf(text(message.messageId.lowercase()), text(message.accountKey), text(message.encode()), text(now()), text(message.type), text(owner)))
    }

    /** `ReplayedWorkout` as JSON, with the keys Swift's `Codable` writes (absent values omitted). */
    private fun stateJson(state: ReplayedWorkout): String {
        fun set(s: ReplayedSet): JsonElement {
            val out = linkedMapOf<String, JsonElement>(
                "setId" to JsonPrimitive(s.setId), "status" to JsonPrimitive(s.status), "kind" to JsonPrimitive(s.kind))
            s.reps?.let { out["reps"] = JsonPrimitive(it) }
            s.durationSeconds?.let { out["durationSeconds"] = JsonPrimitive(it) }
            s.loadGrams?.let { out["loadGrams"] = JsonPrimitive(it) }
            s.rpe?.let { out["rpe"] = JsonPrimitive(it) }
            out["history"] = JsonArray(s.history.map { JsonPrimitive(it) })
            return JsonObject(out)
        }
        return JsonObject(
            mapOf(
                "status" to JsonPrimitive(state.status), "sets" to JsonArray(state.sets.map(::set)),
                "volumeGrams" to JsonPrimitive(state.volumeGrams), "completedSets" to JsonPrimitive(state.completedSets),
                "gaps" to JsonArray(state.gaps.map { JsonPrimitive(it) }),
            ),
        ).toString()
    }

    /**
     * Stores the events (one session, in order), queues each for the phone and saves the session
     * state in one transaction: if anything throws, nothing is written. An event id already stored
     * is skipped; if every event is a repeat nothing changes. `commandId` (a phone command these
     * events answer) is stored in the same transaction so a late duplicate is ignored after a
     * restart. A `completed` message (the final workout) is queued in the same transaction.
     */
    fun record(
        events: List<WorkoutEventV2>,
        sessionState: ReplayedWorkout,
        completed: WatchMessage? = null,
        commandId: String? = null,
        template: String? = null,
    ) {
        val sessionId = events.firstOrNull()?.header?.sessionId ?: return
        db.transaction {
            var accountKey: String? = null
            for (event in events) if (event is WorkoutEventV2.WorkoutStarted) accountKey = event.payload.accountKey
            if (accountKey == null) {
                val rows = db.query("SELECT account_key FROM sessions WHERE session_id = ?", listOf(text(sessionId)))
                accountKey = rows.firstOrNull()?.let { textAt(it, 0) } ?: throw JournalException("unknown_session")
            }
            var inserted = 0
            for (event in events) {
                val header = event.header
                if (header.sessionId != sessionId) throw JournalException("unknown_session")
                val changed = db.execute(
                    "INSERT OR IGNORE INTO events(event_id, session_id, sequence, json) VALUES(?,?,?,?)",
                    listOf(text(header.eventId), text(header.sessionId), int(header.sequence), text(event.encode())))
                if (changed == 0) continue
                inserted += 1
                enqueue(WatchMessage(makeId(), now(), accountKey, WatchMessageBody.WorkoutEvent(event)))
            }
            if (inserted == 0) return@transaction
            if (completed != null) enqueue(completed, sessionId)
            db.execute(
                "INSERT INTO sessions(session_id, account_key, status, state_json) VALUES(?,?,?,?) " +
                    "ON CONFLICT(session_id) DO UPDATE SET status = excluded.status, state_json = excluded.state_json",
                listOf(text(sessionId), text(accountKey), text(sessionState.status), text(stateJson(sessionState))))
            if (template != null) {
                db.execute("UPDATE sessions SET template_json = ? WHERE session_id = ?", listOf(text(template), text(sessionId)))
            }
            // A discarded workout sends nothing: drop whatever was queued for it.
            if (sessionState.status == "abandoned") {
                db.execute("DELETE FROM outbox WHERE session_id = ?", listOf(text(sessionId)))
            }
            if (commandId != null) insertCommand(sessionId, commandId, "applied", null)
            // A discarded session leaves nothing to resend against; a completed one keeps its rows
            // until the phone's ack, so a resent `finish` stays a duplicate.
            if (sessionState.status == "abandoned") {
                db.execute("DELETE FROM applied_commands WHERE session_id = ?", listOf(text(sessionId)))
            }
        }
    }

    fun record(
        event: WorkoutEventV2,
        sessionState: ReplayedWorkout,
        completed: WatchMessage? = null,
        commandId: String? = null,
        template: String? = null,
    ) = record(listOf(event), sessionState, completed, commandId, template)

    private fun insertCommand(sessionId: String, commandId: String, result: String, reason: String?) {
        db.execute(
            "INSERT OR IGNORE INTO applied_commands(session_id, command_id, result, reason, applied_at_ms) VALUES(?,?,?,?,?)",
            listOf(
                text(sessionId), text(commandId.lowercase()), text(result),
                reason?.let { text(it) } ?: SqlValue.Null, int(clock().toEpochMilli())))
    }

    /** Remembers a phone command that changed no event: a rejected one, or one that had nothing to do. The first result for an id stands. */
    fun recordCommand(sessionId: String, commandId: String, result: String, reason: String?) =
        insertCommand(sessionId, commandId, result, reason)

    /** What the watch did with a phone command, null when it never saw the id. */
    fun commandResult(sessionId: String, commandId: String): CommandResult? {
        val rows = db.query(
            "SELECT result, reason FROM applied_commands WHERE session_id = ? AND command_id = ?",
            listOf(text(sessionId), text(commandId.lowercase())))
        val row = rows.firstOrNull() ?: return null
        val result = textAt(row, 0) ?: return null
        return CommandResult(result, textAt(row, 1))
    }

    /** Every command the session handled, oldest first. */
    fun commandLog(sessionId: String): List<CommandLogEntry> =
        db.query(
            "SELECT command_id, result, reason FROM applied_commands WHERE session_id = ? ORDER BY rowid",
            listOf(text(sessionId)),
        ).mapNotNull { row ->
            val id = textAt(row, 0) ?: return@mapNotNull null
            val result = textAt(row, 1) ?: return@mapNotNull null
            CommandLogEntry(id, result, textAt(row, 2))
        }

    private fun decodeAll(rows: List<List<SqlValue>>): List<WatchMessage> =
        rows.mapNotNull { row -> textAt(row, 0)?.let { WatchMessage.decode(it) } }

    fun pendingOutbox(limit: Int): List<WatchMessage> =
        decodeAll(db.query("SELECT json FROM outbox ORDER BY rowid LIMIT ?", listOf(int(limit))))

    /** Completed workouts waiting for the phone, oldest first. Event messages in the outbox are not returned. */
    fun pendingCompleted(limit: Int): List<WatchMessage> =
        decodeAll(db.query("SELECT json FROM outbox WHERE type = 'completed_workout' ORDER BY rowid LIMIT ?", listOf(int(limit))))

    /** Completed workouts of one account waiting for the phone, oldest first; the account is filtered in SQL, before [limit]. */
    fun pendingCompleted(accountKey: String, limit: Int): List<WatchMessage> =
        decodeAll(
            db.query(
                "SELECT json FROM outbox WHERE type = 'completed_workout' AND account_key = ? ORDER BY rowid LIMIT ?",
                listOf(text(accountKey), int(limit))))

    /**
     * Queues the finished workout and marks the session `queued` in one transaction. A second call
     * for the same message changes nothing, and a session already delivered or rejected stays that way.
     */
    fun queueCompleted(message: WatchMessage, sessionId: String) {
        db.transaction {
            enqueue(message, sessionId)
            db.execute("UPDATE sessions SET delivery = 'queued' WHERE session_id = ? AND delivery IS NULL", listOf(text(sessionId)))
        }
    }

    // Following a workout the phone owns

    /** Remembers the workout this watch follows (one at a time). */
    fun saveFollower(sessionId: String, accountKey: String, joinedAtMs: Long, phase: String) {
        db.execute(
            "INSERT OR REPLACE INTO follower(slot, session_id, account_key, joined_at_ms, phase) VALUES(1,?,?,?,?)",
            listOf(text(sessionId.lowercase()), text(accountKey), int(joinedAtMs), text(phase)))
    }

    fun follower(): FollowerRow? {
        val row = db.query("SELECT session_id, account_key, joined_at_ms, phase FROM follower WHERE slot = 1").firstOrNull() ?: return null
        return FollowerRow(textAt(row, 0) ?: return null, textAt(row, 1) ?: return null, intAt(row, 2) ?: return null, textAt(row, 3) ?: return null)
    }

    fun clearFollower() {
        db.execute("DELETE FROM follower")
    }

    /**
     * Applies the phone's `ack` for a completed workout: the message, the session's other queued
     * messages, its events and applied commands are deleted and the session is marked `delivered`
     * (`stored`, `duplicate`) or `rejected`. An unknown or already applied id returns null.
     */
    fun applyAck(ackedMessageId: String, result: String): AckEffect? =
        db.transaction {
            val id = ackedMessageId.lowercase()
            val rows = db.query(
                "SELECT session_id FROM outbox WHERE message_id = ? AND type = 'completed_workout'", listOf(text(id)))
            val sessionId = rows.firstOrNull()?.let { textAt(it, 0) }
            if (sessionId == null) {
                // The phone's answer to a workout_health, whatever it says: the series is done.
                db.execute("DELETE FROM session_health WHERE message_id = ?", listOf(text(id)))
                return@transaction null
            }
            if (sessionId.isEmpty()) {
                db.execute("DELETE FROM outbox WHERE message_id = ?", listOf(text(id)))
                return@transaction null
            }
            val rejected = result == "rejected"
            // A rejected workout is never written to the phone, so its series would only wait for the
            // 7-day prune (the phone ignores a workout_health for a workout it does not hold).
            if (rejected) db.execute("DELETE FROM session_health WHERE session_id = ?", listOf(text(sessionId)))
            db.execute("DELETE FROM outbox WHERE session_id = ?", listOf(text(sessionId)))
            db.execute("DELETE FROM events WHERE session_id = ?", listOf(text(sessionId)))
            db.execute("DELETE FROM applied_commands WHERE session_id = ?", listOf(text(sessionId)))
            db.execute(
                "UPDATE sessions SET delivery = ? WHERE session_id = ?",
                listOf(text(if (rejected) "rejected" else "delivered"), text(sessionId)))
            if (rejected) AckEffect.Rejected(sessionId) else AckEffect.Delivered(sessionId)
        }

    /**
     * Keeps the heart rate and calories of a finished workout next to its session (stage 3b).
     * `message` must be a `workout_health`; a second save for the session replaces the first.
     * [endedAtMs] starts the 7-day retention.
     */
    fun saveWorkoutHealth(sessionId: String, accountKey: String, message: WatchMessage, endedAtMs: Long) {
        if (message.body !is WatchMessageBody.WorkoutHealth) throw ContractException("invalid_value")
        db.execute(
            "INSERT OR REPLACE INTO session_health(session_id, account_key, message_id, message_json, ended_at_ms) VALUES(?,?,?,?,?)",
            listOf(text(sessionId), text(accountKey), text(message.messageId.lowercase()), text(message.encode()), int(endedAtMs)))
    }

    /** `accountKey`'s series whose completed workout the phone has acked as stored or duplicate, oldest first. */
    fun pendingWorkoutHealth(accountKey: String, limit: Int): List<WatchMessage> =
        decodeAll(
            db.query(
                "SELECT h.message_json FROM session_health h JOIN sessions s ON s.session_id = h.session_id " +
                    "WHERE h.account_key = ? AND s.delivery = 'delivered' ORDER BY h.rowid LIMIT ?",
                listOf(text(accountKey), int(limit))))

    /** The account a stored series belongs to, null when no series has that message id. */
    fun queuedWorkoutHealthAccountKey(messageId: String): String? =
        db.query("SELECT account_key FROM session_health WHERE message_id = ?", listOf(text(messageId.lowercase())))
            .firstOrNull()?.let { textAt(it, 0) }

    /** `queued`, `delivered` or `rejected`; null before the workout is queued. */
    fun delivery(sessionId: String): String? =
        db.query("SELECT delivery FROM sessions WHERE session_id = ?", listOf(text(sessionId))).firstOrNull()?.let { textAt(it, 0) }

    /** Every stored event of a session in sequence order, whatever its status. */
    fun events(sessionId: String): List<WorkoutEventV2> =
        db.query("SELECT json FROM events WHERE session_id = ? ORDER BY sequence", listOf(text(sessionId))).mapNotNull { row ->
            textAt(row, 0)?.let { runCatching { WorkoutEventV2.decode(it) }.getOrNull() }
        }

    /** The account key of a queued completed workout, null when it is not queued. */
    fun queuedCompletedAccountKey(messageId: String): String? =
        db.query(
            "SELECT account_key FROM outbox WHERE message_id = ? AND type = 'completed_workout'",
            listOf(text(messageId.lowercase())),
        ).firstOrNull()?.let { textAt(it, 0) }

    /** Sessions of `accountKey` that were completed but whose workout was never queued (the app stopped between the two steps of finishing). */
    fun sessionsAwaitingQueue(accountKey: String): List<String> =
        db.query(
            "SELECT session_id FROM sessions WHERE account_key = ? AND status = 'completed' AND delivery IS NULL ORDER BY rowid",
            listOf(text(accountKey)),
        ).mapNotNull { textAt(it, 0) }

    /** The same, for every account. Queueing needs no binding; only sending does. */
    fun allSessionsAwaitingQueue(): List<SessionAccount> =
        db.query(
            "SELECT session_id, account_key FROM sessions WHERE status = 'completed' AND delivery IS NULL ORDER BY rowid",
        ).mapNotNull { row -> SessionAccount(textAt(row, 0) ?: return@mapNotNull null, textAt(row, 1) ?: return@mapNotNull null) }

    /** Active or paused sessions of every account, oldest first: a launch abandons the ones no bound account owns. */
    fun activeSessionAccounts(): List<SessionAccount> =
        db.query(
            "SELECT session_id, account_key FROM sessions WHERE status IN ('active','paused') ORDER BY rowid",
        ).mapNotNull { row -> SessionAccount(textAt(row, 0) ?: return@mapNotNull null, textAt(row, 1) ?: return@mapNotNull null) }

    /** Queued completed workouts, split by whether they belong to `boundKey`. */
    fun waitingCounts(boundKey: String?): WaitingCounts {
        var mine = 0
        var other = 0
        for (row in db.query("SELECT account_key FROM outbox WHERE type = 'completed_workout'")) {
            val key = textAt(row, 0) ?: continue
            if (boundKey != null && key == boundKey) mine += 1 else other += 1
        }
        return WaitingCounts(mine, other)
    }

    /** Saves the template. With `commandId` the phone command that asked for it is recorded in the same transaction. */
    fun saveTemplate(sessionId: String, json: String, commandId: String? = null) {
        db.transaction {
            db.execute("UPDATE sessions SET template_json = ? WHERE session_id = ?", listOf(text(json), text(sessionId)))
            if (commandId != null) insertCommand(sessionId, commandId, "applied", null)
        }
    }

    fun template(sessionId: String): String? =
        db.query("SELECT template_json FROM sessions WHERE session_id = ?", listOf(text(sessionId))).firstOrNull()?.let { textAt(it, 0) }

    /** Removes the acknowledged message; acknowledging twice does nothing. */
    fun acknowledge(messageId: String) {
        db.execute("DELETE FROM outbox WHERE message_id = ?", listOf(text(messageId.lowercase())))
    }

    /** Queues a completed workout for the phone. */
    fun saveCompleted(message: WatchMessage) {
        db.transaction { enqueue(message) }
    }

    /** Remembers which account the phone is signed in as (one row). The caller clears the previous account first when the key changes. */
    fun saveBinding(message: WatchMessage) {
        val body = message.body as? WatchMessageBody.AccountBinding ?: throw ContractException("invalid_value")
        val sentAtMs = WatchTimestamp.milliseconds(message.sentAtUtc) ?: throw ContractException("invalid_value")
        db.execute(
            "INSERT OR REPLACE INTO binding(slot, account_key, unit, message_id, sent_at_ms) VALUES(1,?,?,?,?)",
            listOf(text(message.accountKey), text(body.unit), text(message.messageId.lowercase()), int(sentAtMs)))
    }

    /** The stored binding with the id and send time of the message it came from. */
    fun bindingState(): BindingState? {
        val row = db.query("SELECT account_key, message_id, sent_at_ms FROM binding WHERE slot = 1").firstOrNull() ?: return null
        return BindingState(textAt(row, 0) ?: return null, textAt(row, 1) ?: return null, intAt(row, 2) ?: return null)
    }

    /** When the phone last told the watch `key` was cleared, if ever. A binding sent before that is stale and must not be applied. */
    fun clearedAt(key: String): Long? =
        db.query("SELECT sent_at_ms FROM cleared WHERE account_key = ?", listOf(text(key))).firstOrNull()?.let { intAt(it, 0) }

    /** Remembers a clear, keeping the newest time seen for the key. */
    fun recordCleared(key: String, sentAtMs: Long) {
        db.execute(
            "INSERT INTO cleared(account_key, sent_at_ms) VALUES(?,?) " +
                "ON CONFLICT(account_key) DO UPDATE SET sent_at_ms = MAX(sent_at_ms, excluded.sent_at_ms)",
            listOf(text(key), int(sentAtMs)))
    }

    /** Remembers when the watch last stored phone data. Only the time is kept; it holds no health values. */
    fun recordReceived(atMs: Long) {
        db.execute("INSERT OR REPLACE INTO link_state(slot, last_received_ms) VALUES(1,?)", listOf(int(atMs)))
    }

    fun lastReceivedMs(): Long? =
        db.query("SELECT last_received_ms FROM link_state WHERE slot = 1").firstOrNull()?.let { intAt(it, 0) }

    /** Deletes every health snapshot that is not for `localDate`. */
    fun purgeHealth(exceptLocalDate: String) {
        db.execute("DELETE FROM health WHERE local_date != ?", listOf(text(exceptLocalDate)))
    }

    fun binding(): Binding? {
        val row = db.query("SELECT account_key, unit FROM binding WHERE slot = 1").firstOrNull() ?: return null
        return Binding(textAt(row, 0) ?: return null, textAt(row, 1) ?: return null)
    }

    fun savePlans(message: WatchMessage) {
        if (message.body !is WatchMessageBody.PlansSnapshot) throw ContractException("invalid_value")
        db.execute(
            "INSERT OR REPLACE INTO plans(account_key, json) VALUES(?,?)", listOf(text(message.accountKey), text(message.encode())))
    }

    fun plans(accountKey: String): WatchMessage? =
        db.query("SELECT json FROM plans WHERE account_key = ?", listOf(text(accountKey))).firstOrNull()
            ?.let { textAt(it, 0) }?.let { WatchMessage.decode(it) }

    fun saveHealth(message: WatchMessage) {
        val body = message.body as? WatchMessageBody.HealthSnapshot ?: throw ContractException("invalid_value")
        db.transaction {
            db.execute("DELETE FROM health WHERE local_date != ?", listOf(text(body.localDate)))
            db.execute(
                "INSERT OR REPLACE INTO health(account_key, local_date, json) VALUES(?,?,?)",
                listOf(text(message.accountKey), text(body.localDate), text(message.encode())))
        }
    }

    /**
     * Today's snapshot only. Health values are cleared at local midnight (ADR-0012), so rows for any
     * other date are deleted here, on read and on save, and are never returned.
     */
    fun health(accountKey: String, forLocalDate: String): WatchMessage? {
        purgeHealth(forLocalDate)
        return db.query(
            "SELECT json FROM health WHERE account_key = ? AND local_date = ?",
            listOf(text(accountKey), text(forLocalDate)),
        ).firstOrNull()?.let { textAt(it, 0) }?.let { WatchMessage.decode(it) }
    }

    /**
     * Drops the plans, health snapshot and binding for `key`. With `wipeUnsent` (account deletion
     * only) it also drops that key's sessions, events and queue.
     */
    fun clearAccount(key: String, wipeUnsent: Boolean) {
        db.transaction {
            db.execute("DELETE FROM plans WHERE account_key = ?", listOf(text(key)))
            db.execute("DELETE FROM health WHERE account_key = ?", listOf(text(key)))
            db.execute("DELETE FROM session_health WHERE account_key = ?", listOf(text(key)))
            // The received time belongs to the bound account, so it goes with it.
            db.execute("DELETE FROM link_state WHERE EXISTS (SELECT 1 FROM binding WHERE account_key = ?)", listOf(text(key)))
            db.execute("DELETE FROM binding WHERE account_key = ?", listOf(text(key)))
            if (!wipeUnsent) return@transaction
            db.execute("DELETE FROM events WHERE session_id IN (SELECT session_id FROM sessions WHERE account_key = ?)", listOf(text(key)))
            db.execute("DELETE FROM applied_commands WHERE session_id IN (SELECT session_id FROM sessions WHERE account_key = ?)", listOf(text(key)))
            db.execute("DELETE FROM sessions WHERE account_key = ?", listOf(text(key)))
            db.execute("DELETE FROM follower WHERE account_key = ?", listOf(text(key)))
            db.execute("DELETE FROM outbox WHERE account_key = ?", listOf(text(key)))
        }
    }

    /**
     * Drops a binding the phone has not refreshed for `maxSilenceDays`, deletes heart rate series
     * of workouts that ended more than [maxSeriesDays] ago, and keeps only the newest
     * `maxTombstones` clear tombstones. Returns true when the binding was dropped. Nothing is
     * dropped while a workout is active or paused, and unsent workouts are never dropped. The
     * binding's send time becomes the account's tombstone, so a replay of the old application
     * context is ignored and is never removed by the cap of the same call. Tombstones are capped
     * by count, never by age, because the watch replays the last application context on launch.
     */
    fun pruneStale(nowMs: Long, maxSilenceDays: Int = 90, maxTombstones: Int = 20, maxSeriesDays: Int = 7): Boolean =
        db.transaction {
            db.execute(
                "DELETE FROM session_health WHERE ended_at_ms < ?",
                listOf(int(nowMs - maxSeriesDays.toLong() * 86_400_000L)))
            var dropped = false
            var droppedKey = ""
            val binding = bindingState()
            val received = lastReceivedMs()
            if (binding != null && received != null && received < nowMs - maxSilenceDays.toLong() * 86_400_000L) {
                val busy = db.query(
                    "SELECT 1 FROM sessions WHERE account_key = ? AND status IN ('active','paused') " +
                        "UNION SELECT 1 FROM follower WHERE account_key = ? LIMIT 1",
                    listOf(text(binding.accountKey), text(binding.accountKey)))
                if (busy.isEmpty()) {
                    recordCleared(binding.accountKey, binding.sentAtMs)
                    clearAccount(binding.accountKey, wipeUnsent = false)
                    dropped = true
                    droppedKey = binding.accountKey
                }
            }
            // The tombstone just written may be older than the others (it carries the binding's
            // send time), so it is kept and the newest others fill the rest of the cap.
            db.execute(
                "DELETE FROM cleared WHERE account_key != ? AND account_key NOT IN " +
                    "(SELECT account_key FROM cleared WHERE account_key != ? ORDER BY sent_at_ms DESC, account_key LIMIT ?)",
                listOf(text(droppedKey), text(droppedKey), int(if (dropped) maxTombstones - 1 else maxTombstones)))
            dropped
        }

    /**
     * `accountKey`'s newest active or paused session with its events, replayed state and the phone
     * command ids already applied. Another account's session is never returned.
     */
    fun activeSession(accountKey: String): ActiveSession? {
        val rows = db.query(
            "SELECT session_id FROM sessions WHERE account_key = ? AND status IN ('active','paused') ORDER BY rowid DESC LIMIT 1",
            listOf(text(accountKey)))
        val sessionId = rows.firstOrNull()?.let { textAt(it, 0) } ?: return null
        val events = events(sessionId)
        val commands = db.query("SELECT command_id FROM applied_commands WHERE session_id = ?", listOf(text(sessionId)))
            .mapNotNull { textAt(it, 0) }.toSet()
        return ActiveSession(sessionId, events, WorkoutReplay.replay(events), commands)
    }
}

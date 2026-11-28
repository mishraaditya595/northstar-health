package `in`.beyondrep.wear.core.store

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.ContractException
import `in`.beyondrep.wear.core.contracts.ExerciseAddedPayload
import `in`.beyondrep.wear.core.contracts.HeartRatePoint
import `in`.beyondrep.wear.core.contracts.SessionCommand
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import `in`.beyondrep.wear.core.session.SessionMachine
import `in`.beyondrep.wear.core.session.WorkoutReplay
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/*
 * Port of WatchJournalTests.swift.
 *
 * Swift tests not ported here:
 *  - upgrades from older Swift schema versions (Wear has no old databases): testJournalMigratesUserVersion2To8KeepingOutboxRows,
 *    testJournalMigratesAVersion3BindingTableKeepingItsRow, testMigrationFromVersion4KeepsData,
 *    testVersion6AddsColumnsAndKeepsRows, testVersion7AddsCommandResultColumnsAndKeepsAppliedCommands,
 *    testVersion8AddsFollowerAndLinkTablesAndKeepsRows;
 *  - the workout_link outbox (not sent by Wear, spec 4.5): testWorkoutLinkIsQueuedOncePerWorkoutIdAndSurvivesReopen,
 *    testLinkAckRemovesItAndItIsNotQueuedAgain, testRejectedAndDuplicateLinkAcksAlsoSettleIt,
 *    testPendingCompletedAndPendingOutboxKeepLinksApart (the link half of testClearAccountWithWipeRemovesItsFollowerAndLinks);
 *  - tests that drive PhoneInbox, ported with PhoneInboxTest: testReplayAfterPruneIsIgnored,
 *    testCapKeepsTheTombstoneJustWrittenEvenWhenItIsTheOldest.
 * The Swift `failAt` hook is replaced by FailingSqlDatabase, which makes a chosen statement throw.
 */
class WatchJournalTest {
    private val key = "0123456789abcdef".repeat(4)
    private val session = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private lateinit var dir: Path
    private val opened = mutableListOf<JdbcSqlDatabase>()

    @BeforeEach
    fun setUp() {
        dir = Files.createTempDirectory("journal")
    }

    @AfterEach
    fun tearDown() {
        opened.forEach { runCatching { it.close() } }
        dir.toFile().deleteRecursively()
    }

    private val path get() = dir.resolve("journal.sqlite")

    private fun db(): JdbcSqlDatabase = JdbcSqlDatabase(path).also { opened.add(it) }

    private fun open(clock: () -> Instant = Instant::now) = WatchJournal(db(), clock)

    private fun openFailing(): Pair<WatchJournal, FailingSqlDatabase> {
        val failing = FailingSqlDatabase(db())
        return WatchJournal(failing) to failing
    }

    private fun machine(): SessionMachine {
        var tick = 0L
        val base = Instant.ofEpochSecond(1_792_000_000)
        return SessionMachine(
            sessionId = session, owner = "watch", accountKey = key, deviceId = "watch-installation-a",
            clock = { tick += 1; base.plusSeconds(tick) }, timeZone = "Asia/Kolkata")
    }

    private fun set(n: Int) = SetValues(
        "dddddddd-dddd-4ddd-8ddd-00000000000$n", "builtin.v1.synthetic-move-1", n, reps = 8, loadGrams = 60000)

    /** Records a started session with `sets` logged sets; returns the events. */
    private fun recordSession(journal: WatchJournal, sets: Int): List<WorkoutEventV2> {
        val m = machine()
        val events = m.start("Synthetic push day").toMutableList()
        journal.record(events, WorkoutReplay.replay(events))
        for (n in 1..sets) {
            val event = m.log(set(n))
            events.add(event)
            journal.record(event, WorkoutReplay.replay(events))
        }
        return events
    }

    private fun fixture(name: String): WatchMessage =
        WatchMessage.decode(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/$name.json"))

    private fun completedMessage(key: String? = null, id: String = UUID.randomUUID().toString().lowercase()): WatchMessage {
        val base = fixture("completed_workout")
        return WatchMessage(id, base.sentAtUtc, key ?: this.key, base.body)
    }

    private fun count(table: String, session: String? = null): Int {
        val check = db()
        val rows = if (session != null) {
            check.query("SELECT COUNT(*) FROM $table WHERE session_id = ?", listOf(SqlValue.Text(session)))
        } else {
            check.query("SELECT COUNT(*) FROM $table")
        }
        return ((rows.first().first()) as SqlValue.Int64).v.toInt()
    }

    private fun delivery(sessionId: String): String? =
        (db().query("SELECT delivery FROM sessions WHERE session_id = ?", listOf(SqlValue.Text(sessionId)))
            .firstOrNull()?.first() as? SqlValue.Text)?.v

    /** A finished session (completed, not queued) with one logged set. */
    private fun recordFinishedSession(journal: WatchJournal) {
        val m = machine()
        val events = m.start("Synthetic push day").toMutableList()
        events.add(m.log(set(1)))
        events.add(m.complete())
        journal.record(events, WorkoutReplay.replay(events))
    }

    // Atomic writes

    @Test
    fun recordIsAtomic() {
        val (journal, failing) = openFailing()
        recordSession(journal, 0)
        val before = journal.pendingOutbox(100).size
        val m = machine()
        m.start("x")
        val event = m.log(set(1))
        failing.failBefore = { sql, _ -> sql.startsWith("INSERT OR IGNORE INTO outbox") }
        assertFailsWith<IllegalStateException> { journal.record(event, m.state) }
        val reopened = open()
        assertEquals(before, reopened.pendingOutbox(100).size)
        assertEquals(1, reopened.activeSession(key)?.events?.size)
    }

    @Test
    fun recordRollsBackWhenOutboxInsertFails() {
        val (journal, failing) = openFailing()
        val m = machine()
        val events = m.start("Synthetic push day", exercises = listOf(ExerciseAddedPayload("builtin.v1.synthetic-move-1", "Move", "reps", 0)))
        failing.failBefore = { sql, _ -> sql.startsWith("INSERT OR IGNORE INTO outbox") }
        assertFailsWith<IllegalStateException> { journal.record(events, m.state) }
        // Neither the event nor its outbox row survived, in this journal or after reopening it.
        for (j in listOf(journal, open())) {
            assertTrue(j.events(session).isEmpty())
            assertTrue(j.pendingOutbox(10).isEmpty())
        }
        assertNull(open().activeSession(key))
    }

    @Test
    fun recordRollsBackWhenItFailsAfterTheStateUpsertOrTheCompletedInsert() {
        val points = mapOf<String, (String, List<SqlValue>) -> Boolean>(
            "afterSessionUpsert" to { sql, _ -> sql.startsWith("INSERT INTO sessions") },
            "afterCompletedEnqueue" to { sql, args ->
                sql.startsWith("INSERT OR IGNORE INTO outbox") && SqlValue.Text("completed_workout") in args
            },
        )
        for ((name, match) in points) {
            val (journal, failing) = openFailing()
            recordSession(journal, 0)
            val before = journal.pendingOutbox(100).size
            val m = machine()
            m.start("x")
            val event = m.log(set(1))
            failing.failAfter = match
            assertFailsWith<IllegalStateException>(name) {
                journal.record(event, m.state, completed = fixture("completed_workout"), commandId = "88888888-4444-4444-8444-00000000000c")
            }
            val reopened = open()
            assertEquals(before, reopened.pendingOutbox(100).size, name)
            val active = assertNotNull(reopened.activeSession(key), name)
            assertEquals(1, active.events.size, name)
            assertEquals(0, active.state.completedSets, name)
            assertTrue(active.commandIds.isEmpty(), name)
            dir.toFile().deleteRecursively()
            dir = Files.createTempDirectory("journal")
        }
    }

    @Test
    fun multiEventRecordIsAtomic() {
        val (journal, failing) = openFailing()
        val m = machine()
        val events = m.start("x", exercises = listOf(ExerciseAddedPayload("builtin.v1.synthetic-move-1", "Move", "reps", 0)))
        assertEquals(2, events.size)
        failing.failBefore = { sql, _ -> sql.startsWith("INSERT OR IGNORE INTO outbox") }
        assertFailsWith<IllegalStateException> { journal.record(events, m.state) }
        failing.failBefore = null
        val reopened = open()
        assertNull(reopened.activeSession(key))
        assertTrue(reopened.pendingOutbox(100).isEmpty())
        reopened.record(events, m.state)
        assertEquals(2, reopened.activeSession(key)?.events?.size)
        assertEquals(2, reopened.pendingOutbox(100).size)
    }

    @Test
    fun activeSessionIsPerAccount() {
        val journal = open()
        recordSession(journal, 1)
        assertNull(journal.activeSession("f".repeat(64)))
        assertNotNull(journal.activeSession(key))
    }

    @Test
    fun activeSessionsOfEveryAccountAreListedUntilTheyEnd() {
        val journal = open()
        assertTrue(journal.activeSessionAccounts().isEmpty())
        val m = machine()
        val events = m.start("Synthetic push day").toMutableList()
        journal.record(events, WorkoutReplay.replay(events))
        assertEquals(listOf(SessionAccount(session, key)), journal.activeSessionAccounts())
        journal.record(listOf(m.abandon()), m.state)
        assertTrue(journal.activeSessionAccounts().isEmpty())
    }

    @Test
    fun restoredMachineContinuesTheSequenceWithoutReuse() {
        recordSession(open(), 1)
        val reopened = open()
        val active = assertNotNull(reopened.activeSession(key))
        var tick = 100L
        val m = SessionMachine.restoring(
            active.events, "watch", key, "watch-installation-a",
            { tick += 1; Instant.ofEpochSecond(1_792_100_000 + tick) }, "Asia/Kolkata", appliedCommandIds = active.commandIds)
        assertEquals("active", m.status)
        val next = m.log(set(2))
        assertEquals(2, next.header.sequence)
        assertEquals(3, m.events.map { it.header.sequence }.toSet().size)
        assertEquals(session, next.header.sessionId)
        reopened.record(next, m.state)
        assertEquals(2, reopened.activeSession(key)?.state?.completedSets)
    }

    @Test
    fun duplicateLogAfterCorrectIsIgnoredAcrossReopen() {
        val journal = open()
        val m = machine()
        journal.record(m.start("x"), m.state)
        val logId = "88888888-4444-4444-8444-00000000000a"
        val log = SessionCommand(session, logId, "log_set", set(1))
        val e1 = assertNotNull(m.apply(log))
        journal.record(e1, m.state, commandId = logId)
        val fixId = "88888888-4444-4444-8444-00000000000b"
        val e2 = assertNotNull(
            m.apply(
                SessionCommand(
                    session, fixId, "correct_set",
                    SetValues(set(1).setId, "builtin.v1.synthetic-move-1", 1, reps = 9, loadGrams = 60000))))
        journal.record(e2, m.state, commandId = fixId)

        val active = assertNotNull(open().activeSession(key))
        assertEquals(setOf(logId, fixId), active.commandIds)
        val restored = SessionMachine.restoring(
            active.events, "watch", key, "watch-installation-a", { Instant.ofEpochSecond(1_792_100_000) }, "Asia/Kolkata",
            appliedCommandIds = active.commandIds)
        assertNull(restored.apply(log))
        assertEquals(9, restored.state.sets.first().reps)
        assertEquals(3, restored.events.size)
    }

    @Test
    fun reopenRestoresTheActiveSessionAndItsReplayedState() {
        val events = recordSession(open(), 2)
        val restored = assertNotNull(open().activeSession(key))
        assertEquals(events, restored.events)
        assertEquals(WorkoutReplay.replay(events), restored.state)
        assertEquals(2, restored.state.completedSets)
    }

    @Test
    fun duplicateEventIdIsIgnored() {
        val journal = open()
        val events = recordSession(journal, 1)
        val count = journal.pendingOutbox(100).size
        journal.record(events[1], WorkoutReplay.replay(events))
        assertEquals(count, journal.pendingOutbox(100).size)
        assertEquals(events.size, journal.activeSession(key)?.events?.size)
    }

    @Test
    fun acknowledgeRemovesOnlyThatMessageAndIsIdempotent() {
        val journal = open()
        recordSession(journal, 2)
        val pending = journal.pendingOutbox(100)
        assertEquals(3, pending.size)
        journal.acknowledge(pending[0].messageId)
        journal.acknowledge(pending[0].messageId)
        assertEquals(pending.drop(1).map { it.messageId }, journal.pendingOutbox(100).map { it.messageId })
    }

    // Health, plans, binding

    @Test
    fun healthForAnotherDateIsNull() {
        val journal = open()
        journal.saveHealth(fixture("health_snapshot"))
        assertNotNull(journal.health(key, "2026-10-23"))
        assertNull(journal.health(key, "2026-10-24"))
        // Reading another date deleted the stale row (cleared at local midnight).
        assertNull(journal.health(key, "2026-10-23"))
    }

    @Test
    fun savingTodaysHealthDeletesOlderDates() {
        val journal = open()
        val old = fixture("health_snapshot")
        journal.saveHealth(old)
        val raw = (old.body as WatchMessageBody.HealthSnapshot).raw
        val next = JsonObject(raw + ("local_date" to JsonPrimitive("2026-10-24")))
        val newer = WatchMessage(
            UUID.randomUUID().toString().lowercase(), old.sentAtUtc, key, WatchMessageBody.HealthSnapshot("2026-10-24", next))
        journal.saveHealth(newer)
        assertNotNull(journal.health(key, "2026-10-24"))
        assertNull(journal.health(key, "2026-10-23"))
    }

    @Test
    fun clearAccountWithoutWipeKeepsUnsentOutbox() {
        val journal = open()
        recordSession(journal, 1)
        journal.savePlans(fixture("plans_snapshot"))
        journal.saveHealth(fixture("health_snapshot"))
        journal.clearAccount(key, wipeUnsent = false)
        assertNull(journal.plans(key))
        assertNull(journal.health(key, "2026-10-23"))
        assertEquals(2, journal.pendingOutbox(100).size)
        assertNotNull(journal.activeSession(key))
    }

    @Test
    fun clearAccountWithWipeRemovesIt() {
        val journal = open()
        recordSession(journal, 1)
        journal.clearAccount(key, wipeUnsent = true)
        assertTrue(journal.pendingOutbox(100).isEmpty())
        assertNull(journal.activeSession(key))
    }

    @Test
    fun outboxSurvivesReopen() {
        val journal = open()
        recordSession(journal, 1)
        journal.saveCompleted(fixture("completed_workout"))
        assertEquals(3, open().pendingOutbox(100).size)
    }

    @Test
    fun bindingRoundTripsAndClearAccountRemovesItOnlyForItsKey() {
        val journal = open()
        assertNull(journal.binding())
        journal.saveBinding(TestMessages.binding(TestMessages.keyA, unit = "lb"))
        assertEquals(TestMessages.keyA, journal.binding()?.accountKey)
        assertEquals("lb", journal.binding()?.unit)
        journal.clearAccount(TestMessages.keyB, wipeUnsent = false)
        assertNotNull(journal.binding())
        journal.clearAccount(TestMessages.keyA, wipeUnsent = false)
        assertNull(journal.binding())
    }

    @Test
    fun bindingStateKeepsIdAndSendTime() {
        val journal = open()
        journal.saveBinding(TestMessages.binding(TestMessages.keyA, "kg", "2026-10-23T01:00:00.250Z"))
        assertEquals(1_792_717_200_250, journal.bindingState()?.sentAtMs)
    }

    @Test
    fun clearedTombstoneKeepsTheNewestTimeAndSurvivesReopen() {
        val journal = open()
        assertNull(journal.clearedAt(TestMessages.keyA))
        journal.recordCleared(TestMessages.keyA, 2_000)
        journal.recordCleared(TestMessages.keyA, 1_000)
        val reopened = open()
        assertEquals(2_000L, reopened.clearedAt(TestMessages.keyA))
        assertNull(reopened.clearedAt(TestMessages.keyB))
    }

    @Test
    fun recordedReceivedTimeKeepsTheLatestAndSurvivesReopen() {
        val journal = open()
        journal.recordReceived(1_000)
        journal.recordReceived(2_000)
        assertEquals(2_000L, open().lastReceivedMs())
    }

    @Test
    fun clearAccountDeletesTheReceivedTimeOnlyForTheBoundKey() {
        val journal = open()
        journal.saveBinding(TestMessages.binding(TestMessages.keyA))
        journal.recordReceived(1_000)
        journal.clearAccount(TestMessages.keyB, wipeUnsent = false)
        assertEquals(1_000L, journal.lastReceivedMs())
        journal.clearAccount(TestMessages.keyA, wipeUnsent = false)
        assertNull(journal.lastReceivedMs())
    }

    @Test
    fun schemaVersionIsTwoAndReopeningKeepsRows() {
        val journal = open()
        journal.saveBinding(TestMessages.binding())
        val reopened = open()
        assertEquals(TestMessages.keyA, reopened.binding()?.accountKey)
        assertEquals(SqlValue.Int64(2), db().query("PRAGMA user_version").first().first())
    }

    // Heart rate and calories of a finished workout (stage 3b)

    private val endedMs = 1_792_000_000_000

    private fun healthMessage(
        key: String = this.key,
        workoutId: String = session,
        id: String = UUID.randomUUID().toString().lowercase(),
    ) = WatchMessage(
        id, "2026-10-23T11:41:00Z", key,
        WatchMessageBody.WorkoutHealth(
            workoutId, "2026-10-23T11:00:00Z", "2026-10-23T11:40:00Z",
            listOf(HeartRatePoint("2026-10-23T11:00:00Z", 173)), 987.0))

    /** A finished session whose completed workout is queued; returns the completed message id. */
    private fun queueFinished(journal: WatchJournal): String {
        recordFinishedSession(journal)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        return message.messageId
    }

    @Test
    fun workoutHealthWaitsForTheCompletedWorkoutAck() {
        val journal = open()
        val completedId = queueFinished(journal)
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        assertTrue(journal.pendingWorkoutHealth(key, 10).isEmpty())
        journal.applyAck(completedId, "stored")
        val pending = journal.pendingWorkoutHealth(key, 10)
        assertEquals(1, pending.size)
        assertIs<WatchMessageBody.WorkoutHealth>(pending.single().body)
    }

    @Test
    fun aRejectedCompletedAckNeverReleasesTheSeries() {
        val journal = open()
        val completedId = queueFinished(journal)
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        journal.applyAck(completedId, "rejected")
        assertTrue(journal.pendingWorkoutHealth(key, 10).isEmpty())
    }

    @Test
    fun anyAckDeletesTheSeries() {
        for (result in listOf("stored", "duplicate", "rejected")) {
            val journal = WatchJournal(JdbcSqlDatabase(dir.resolve("$result.sqlite")).also { opened.add(it) })
            val completedId = queueFinished(journal)
            journal.applyAck(completedId, "stored")
            val health = healthMessage()
            journal.saveWorkoutHealth(session, key, health, endedMs)
            journal.applyAck(health.messageId, result)
            assertTrue(journal.pendingWorkoutHealth(key, 10).isEmpty(), result)
            assertEquals(0, JdbcSqlDatabase(dir.resolve("$result.sqlite")).also { opened.add(it) }
                .query("SELECT COUNT(*) FROM session_health").first().first().let { (it as SqlValue.Int64).v.toInt() }, result)
        }
    }

    @Test
    fun aRejectedWorkoutDeletesItsSeries() {
        val journal = WatchJournal(JdbcSqlDatabase(dir.resolve("rejected-workout.sqlite")).also { opened.add(it) })
        val completedId = queueFinished(journal)
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        journal.applyAck(completedId, "rejected")
        assertEquals(0, JdbcSqlDatabase(dir.resolve("rejected-workout.sqlite")).also { opened.add(it) }
            .query("SELECT COUNT(*) FROM session_health").first().first().let { (it as SqlValue.Int64).v.toInt() })
    }

    @Test
    fun clearAccountDeletesTheSeries() {
        for (wipe in listOf(false, true)) {
            val journal = WatchJournal(JdbcSqlDatabase(dir.resolve("wipe$wipe.sqlite")).also { opened.add(it) })
            journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
            journal.saveWorkoutHealth(
                "cccccccc-cccc-4ccc-8ccc-cccccccccccc", TestMessages.keyB,
                healthMessage(TestMessages.keyB, "cccccccc-cccc-4ccc-8ccc-cccccccccccc"), endedMs)
            journal.clearAccount(key, wipe)
            val rows = JdbcSqlDatabase(dir.resolve("wipe$wipe.sqlite")).also { opened.add(it) }
                .query("SELECT account_key FROM session_health")
            assertEquals(listOf(SqlValue.Text(TestMessages.keyB)), rows.map { it.first() }, "wipe=$wipe")
        }
    }

    @Test
    fun droppingAStaleBindingDeletesTheSeries() {
        val journal = open()
        bindWithData(journal)
        journal.recordReceived(receivedMs)
        journal.saveWorkoutHealth(session, key, healthMessage(), receivedMs + 90 * dayMs)
        assertTrue(journal.pruneStale(receivedMs + 91 * dayMs))
        assertEquals(0, count("session_health"))
    }

    @Test
    fun pruneStaleDropsSeriesAfterSevenDays() {
        val journal = open()
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        journal.pruneStale(endedMs + 6 * dayMs + 23 * 3_600_000L)
        assertEquals(1, count("session_health"))
        journal.pruneStale(endedMs + 7 * dayMs + 3_600_000L)
        assertEquals(0, count("session_health"))
    }

    @Test
    fun aSeriesOfAnotherAccountIsNeverPending() {
        val journal = open()
        val completedId = queueFinished(journal)
        journal.applyAck(completedId, "stored")
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        assertTrue(journal.pendingWorkoutHealth(TestMessages.keyB, 10).isEmpty())
        assertEquals(1, journal.pendingWorkoutHealth(key, 10).size)
    }

    @Test
    fun savingTheSameSeriesTwiceKeepsOneRow() {
        val journal = open()
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        assertEquals(1, count("session_health"))
    }

    @Test
    fun onlyAWorkoutHealthMessageCanBeSavedAsASeries() {
        val journal = open()
        assertFailsWith<ContractException> { journal.saveWorkoutHealth(session, key, completedMessage(), endedMs) }
    }

    @Test
    fun migrationFromStage3aKeepsRows() {
        val old = db()
        old.execute("CREATE TABLE outbox(message_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, json TEXT NOT NULL, created_at TEXT NOT NULL, type TEXT NOT NULL DEFAULT '', session_id TEXT NOT NULL DEFAULT '')")
        old.execute("CREATE TABLE sessions(session_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, status TEXT NOT NULL, state_json TEXT NOT NULL, delivery TEXT, template_json TEXT)")
        old.execute("CREATE TABLE binding(slot INTEGER PRIMARY KEY CHECK(slot = 1), account_key TEXT NOT NULL, unit TEXT NOT NULL, message_id TEXT NOT NULL DEFAULT '', sent_at_ms INTEGER NOT NULL DEFAULT 0)")
        old.execute("INSERT INTO binding(slot, account_key, unit, message_id, sent_at_ms) VALUES(1,?,?,?,?)",
            listOf(SqlValue.Text(key), SqlValue.Text("kg"), SqlValue.Text("m"), SqlValue.Int64(5)))
        old.execute("INSERT INTO sessions(session_id, account_key, status, state_json, delivery) VALUES(?,?,?,?,?)",
            listOf(SqlValue.Text(session), SqlValue.Text(key), SqlValue.Text("completed"), SqlValue.Text("{}"), SqlValue.Text("delivered")))
        old.execute("PRAGMA user_version = 1")
        old.close()
        opened.remove(old)

        val journal = open()
        assertEquals(key, journal.binding()?.accountKey)
        assertEquals("delivered", journal.delivery(session))
        assertEquals(SqlValue.Int64(2), db().query("PRAGMA user_version").first().first())
        journal.saveWorkoutHealth(session, key, healthMessage(), endedMs)
        assertEquals(1, journal.pendingWorkoutHealth(key, 10).size)
    }

    // Pruning a binding the phone stopped refreshing

    private val dayMs = 86_400_000L
    private val receivedMs = 1_792_000_000_000

    /** A bound account with plans, health and a received time. */
    private fun bindWithData(journal: WatchJournal) {
        journal.saveBinding(TestMessages.binding(key))
        journal.savePlans(fixture("plans_snapshot"))
        journal.saveHealth(fixture("health_snapshot"))
        journal.recordReceived(receivedMs)
    }

    @Test
    fun bindingSilentFor91DaysIsDropped() {
        val journal = open()
        bindWithData(journal)
        assertTrue(journal.pruneStale(receivedMs + 91 * dayMs))
        assertNull(journal.binding())
        assertNull(journal.plans(key))
        assertNull(journal.health(key, "2026-10-23"))
        assertNull(journal.lastReceivedMs())
    }

    @Test
    fun bindingSilentFor89DaysIsKept() {
        val journal = open()
        bindWithData(journal)
        assertFalse(journal.pruneStale(receivedMs + 89 * dayMs))
        assertNotNull(journal.binding())
        assertNotNull(journal.plans(key))
        assertNull(journal.clearedAt(key))
        assertNotNull(journal.health(key, "2026-10-23"))
    }

    @Test
    fun noPruneWithoutLastReceived() {
        val journal = open()
        journal.saveBinding(TestMessages.binding(key))
        assertFalse(journal.pruneStale(receivedMs + 400 * dayMs))
        assertNotNull(journal.binding())
    }

    @Test
    fun noPruneWithoutABinding() {
        val journal = open()
        journal.recordReceived(receivedMs)
        assertFalse(journal.pruneStale(receivedMs + 400 * dayMs))
        assertEquals(receivedMs, journal.lastReceivedMs())
    }

    @Test
    fun noPruneDuringActiveSession() {
        val journal = open()
        bindWithData(journal)
        recordSession(journal, 1)
        assertFalse(journal.pruneStale(receivedMs + 91 * dayMs))
        assertNotNull(journal.binding())
        assertNotNull(journal.plans(key))
        assertNotNull(journal.activeSession(key))
    }

    @Test
    fun unsentWorkoutSurvivesPrune() {
        val journal = open()
        bindWithData(journal)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        assertTrue(journal.pruneStale(receivedMs + 91 * dayMs))
        assertEquals(listOf(message.messageId), journal.pendingCompleted(10).map { it.messageId })
        val counts = journal.waitingCounts(null)
        assertEquals(0, counts.thisAccount)
        assertEquals(1, counts.otherAccounts)
    }

    @Test
    fun tombstonesCappedAtTwenty() {
        val journal = open()
        for (n in 1..25) journal.recordCleared("account-$n", n.toLong())
        assertFalse(journal.pruneStale(receivedMs))
        for (n in 1..5) assertNull(journal.clearedAt("account-$n"), "account-$n")
        for (n in 6..25) assertEquals(n.toLong(), journal.clearedAt("account-$n"))
    }

    @Test
    fun pruneRecordsTheBindingsSendTimeAsTheTombstone() {
        val journal = open()
        bindWithData(journal)
        val sentAt = assertNotNull(journal.bindingState()).sentAtMs
        assertTrue(journal.pruneStale(receivedMs + 91 * dayMs))
        assertEquals(sentAt, journal.clearedAt(key))
    }

    @Test
    fun theTombstoneJustWrittenSurvivesTheCapEvenWhenItIsTheOldest() {
        val journal = open()
        journal.saveBinding(TestMessages.binding(key))
        journal.recordReceived(receivedMs)
        val sentAt = assertNotNull(journal.bindingState()).sentAtMs
        for (n in 1..20) journal.recordCleared("other-$n", sentAt + n)
        assertTrue(journal.pruneStale(receivedMs + 91 * dayMs))
        assertEquals(sentAt, journal.clearedAt(key))
        assertNull(journal.clearedAt("other-1"))
        for (n in 2..20) assertEquals(sentAt + n, journal.clearedAt("other-$n"))
    }

    // Commands, delivery and acks

    @Test
    fun rejectedCommandIsStoredOnceAndListedInOrder() {
        val journal = open()
        recordSession(journal, 0)
        val a = "88888888-4444-4444-8444-00000000000a"
        val b = "88888888-4444-4444-8444-00000000000b"
        journal.recordCommand(session, a, "rejected", "unknown_set")
        journal.recordCommand(session, b, "applied", null)
        journal.recordCommand(session, a.uppercase(), "applied", null)
        val log = journal.commandLog(session)
        assertEquals(listOf(a, b), log.map { it.commandId })
        assertEquals(listOf("rejected", "applied"), log.map { it.result })
        assertEquals("unknown_set", log.first().reason)
        assertEquals("rejected", journal.commandResult(session, a.uppercase())?.result)
        assertNull(journal.commandResult(session, "88888888-4444-4444-8444-0000000000ff"))
    }

    @Test
    fun abandonedSessionDropsItsCommandRows() {
        val journal = open()
        val m = machine()
        journal.record(m.start("Synthetic push day"), m.state)
        journal.recordCommand(session, "88888888-4444-4444-8444-00000000000a", "applied", null)
        journal.record(listOf(m.abandon()), m.state, commandId = "88888888-4444-4444-8444-00000000000c")
        assertTrue(journal.commandLog(session).isEmpty())
    }

    @Test
    fun completedSessionKeepsItsCommandRowsUntilTheAck() {
        val journal = open()
        val m = machine()
        val events = m.start("Synthetic push day").toMutableList()
        events.add(m.log(set(1)))
        journal.record(events, WorkoutReplay.replay(events))
        val finish = "88888888-4444-4444-8444-00000000000c"
        journal.record(listOf(m.complete()), m.state, commandId = finish)
        assertEquals(listOf(finish), journal.commandLog(session).map { it.commandId })
        val message = completedMessage()
        journal.queueCompleted(message, session)
        journal.applyAck(message.messageId, "stored")
        assertTrue(journal.commandLog(session).isEmpty())
    }

    @Test
    fun saveTemplateWithCommandIdIsOneTransaction() {
        val journal = open()
        recordSession(journal, 0)
        val id = "88888888-4444-4444-8444-00000000000d"
        journal.saveTemplate(session, "{\"name\":\"x\"}", id)
        assertEquals("{\"name\":\"x\"}", journal.template(session))
        assertEquals("applied", journal.commandResult(session, id)?.result)
    }

    @Test
    fun pendingCompletedSkipsEventMessages() {
        val journal = open()
        recordSession(journal, 1)
        assertEquals(2, journal.pendingOutbox(10).size)
        journal.queueCompleted(completedMessage(), session)
        assertEquals(listOf("completed_workout"), journal.pendingCompleted(10).map { it.type })
    }

    @Test
    fun pendingCompletedForOneAccountFiltersInSqlBeforeTheLimit() {
        val journal = open()
        val other = "b".repeat(64)
        // Three workouts of another account first: a limit applied before the filter would hide ours.
        repeat(3) { journal.queueCompleted(completedMessage(other), "other-session-$it") }
        val mine = completedMessage()
        journal.queueCompleted(mine, session)
        assertEquals(listOf(mine.messageId), journal.pendingCompleted(key, 1).map { it.messageId })
        assertEquals(3, journal.pendingCompleted(other, 10).size)
        assertTrue(journal.pendingCompleted("c".repeat(64), 10).isEmpty())
    }

    @Test
    fun storedAckClearsSessionOutboxAndEvents() {
        val journal = open()
        recordSession(journal, 1)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        val effect = journal.applyAck(message.messageId.uppercase(), "stored")
        assertEquals(AckEffect.Delivered(session), effect)
        assertTrue(journal.pendingOutbox(50).isEmpty())
        assertEquals(0, count("events", session))
        assertEquals("delivered", delivery(session))
    }

    @Test
    fun duplicateAckCountsAsDelivered() {
        val journal = open()
        recordSession(journal, 1)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        assertEquals(AckEffect.Delivered(session), journal.applyAck(message.messageId, "duplicate"))
        assertEquals("delivered", delivery(session))
    }

    @Test
    fun rejectedAckMarksRejected() {
        val journal = open()
        recordSession(journal, 1)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        assertEquals(AckEffect.Rejected(session), journal.applyAck(message.messageId, "rejected"))
        assertEquals("rejected", delivery(session))
        assertTrue(journal.pendingOutbox(50).isEmpty())
        assertEquals(0, count("events", session))
    }

    @Test
    fun ackForUnknownMessageIsIgnored() {
        val journal = open()
        recordSession(journal, 1)
        val outboxBefore = count("outbox")
        val eventsBefore = count("events")
        assertNull(journal.applyAck("77777777-3333-4333-8333-0000000000ff", "stored"))
        assertEquals(outboxBefore, count("outbox"))
        assertEquals(eventsBefore, count("events"))
    }

    @Test
    fun applyAckIgnoresUnknownAndRepeated() {
        val journal = open()
        recordFinishedSession(journal)
        val first = completedMessage()
        val other = completedMessage(id = "77777777-3333-4333-8333-0000000000a2")
        journal.queueCompleted(first, session)
        journal.queueCompleted(other, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")
        assertEquals(AckEffect.Delivered(session), journal.applyAck(first.messageId, "stored"))
        // Already acked, never sent, and an id of another account's message: no throw, nothing else deleted.
        assertNull(journal.applyAck(first.messageId, "stored"))
        assertNull(journal.applyAck("77777777-3333-4333-8333-0000000000ff", "stored"))
        assertNull(journal.applyAck(TestMessages.id(), "rejected"))
        assertEquals(listOf(other.messageId), journal.pendingCompleted(10).map { it.messageId })
        assertEquals("delivered", delivery(session))
    }

    @Test
    fun secondAckChangesNothing() {
        val journal = open()
        recordSession(journal, 1)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        assertNotNull(journal.applyAck(message.messageId, "stored"))
        assertNull(journal.applyAck(message.messageId, "stored"))
        assertEquals("delivered", delivery(session))
    }

    @Test
    fun abandonDropsQueuedEventMessages() {
        val journal = open()
        val m = machine()
        val events = m.start("x").toMutableList()
        journal.record(events, WorkoutReplay.replay(events))
        val log = m.log(set(1))
        events.add(log)
        journal.record(log, WorkoutReplay.replay(events))
        assertTrue(count("outbox", session) > 0)
        val abandon = m.abandon()
        events.add(abandon)
        journal.record(abandon, WorkoutReplay.replay(events))
        assertEquals(0, count("outbox", session))
    }

    @Test
    fun queueCompletedIsIdempotent() {
        val journal = open()
        recordFinishedSession(journal)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        journal.queueCompleted(message, session)
        assertEquals(1, journal.pendingCompleted(10).size)
        assertEquals("queued", delivery(session))
    }

    @Test
    fun queueCompletedAfterDeliveryDoesNotRequeueTheState() {
        val journal = open()
        recordFinishedSession(journal)
        val message = completedMessage()
        journal.queueCompleted(message, session)
        journal.applyAck(message.messageId, "stored")
        journal.queueCompleted(message, session)
        assertEquals("delivered", delivery(session))
    }

    @Test
    fun waitingCountsSplitByAccount() {
        val journal = open()
        journal.queueCompleted(completedMessage(key = TestMessages.keyA), session)
        journal.queueCompleted(completedMessage(key = TestMessages.keyB), "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")
        val split = journal.waitingCounts(TestMessages.keyA)
        assertEquals(1, split.thisAccount)
        assertEquals(1, split.otherAccounts)
        val none = journal.waitingCounts(null)
        assertEquals(0, none.thisAccount)
        assertEquals(2, none.otherAccounts)
    }

    @Test
    fun sessionsAwaitingQueue() {
        val journal = open()
        recordFinishedSession(journal)
        assertEquals(listOf(session), journal.sessionsAwaitingQueue(key))
        assertEquals(listOf(session to key), journal.allSessionsAwaitingQueue().map { it.sessionId to it.accountKey })
        assertEquals(emptyList(), journal.sessionsAwaitingQueue(TestMessages.keyB))
        journal.queueCompleted(completedMessage(), session)
        assertEquals(emptyList(), journal.sessionsAwaitingQueue(key))
    }

    @Test
    fun queuedCompletedAccountKeyIsReadByMessageId() {
        val journal = open()
        val message = completedMessage()
        journal.queueCompleted(message, session)
        assertEquals(key, journal.queuedCompletedAccountKey(message.messageId.uppercase()))
        assertNull(journal.queuedCompletedAccountKey(TestMessages.id()))
    }

    @Test
    fun templateIsWrittenWithTheStartEvents() {
        val journal = open()
        val m = machine()
        val events = m.start("x")
        journal.record(events, WorkoutReplay.replay(events), template = "{\"name\":\"x\"}")
        assertEquals("{\"name\":\"x\"}", journal.template(session))
        assertEquals(session, journal.activeSession(key)?.sessionId)

        dir.toFile().deleteRecursively()
        dir = Files.createTempDirectory("journal")
        val (failingJournal, failing) = openFailing()
        failing.failAfter = { sql, _ -> sql.startsWith("UPDATE sessions SET template_json") }
        assertFailsWith<IllegalStateException> {
            failingJournal.record(events, WorkoutReplay.replay(events), template = "{}")
        }
        assertNull(failingJournal.template(session))
    }

    @Test
    fun saveTemplateReplacesTheStoredTemplate() {
        val journal = open()
        val m = machine()
        val events = m.start("x")
        journal.record(events, WorkoutReplay.replay(events), template = "{\"a\":1}")
        journal.saveTemplate(session, "{\"a\":2}")
        assertEquals("{\"a\":2}", journal.template(session))
    }

    // Follower row (the link outbox is not ported, see the header)

    private val phoneWorkout = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    @Test
    fun followerRowSurvivesReopenAndIsReplacedByTheNext() {
        open().saveFollower(phoneWorkout, key, 1_000, "following")
        val reopened = open()
        val row = assertNotNull(reopened.follower())
        assertEquals(phoneWorkout, row.sessionId)
        assertEquals(key, row.accountKey)
        assertEquals(1_000L, row.joinedAtMs)
        assertEquals("following", row.phase)
        reopened.saveFollower(session, key, 2_000, "finishing")
        assertEquals(session, reopened.follower()?.sessionId)
        assertEquals("finishing", reopened.follower()?.phase)
        reopened.clearFollower()
        assertNull(reopened.follower())
    }

    @Test
    fun clearAccountWithWipeRemovesItsFollowerRow() {
        val journal = open()
        journal.saveFollower(phoneWorkout, key, 1, "following")
        journal.clearAccount(key, wipeUnsent = false)
        assertNotNull(journal.follower(), "an unwiped clear keeps unsent work")
        journal.clearAccount(key, wipeUnsent = true)
        assertNull(journal.follower())
    }

    @Test
    fun anotherAccountsFollowerRowSurvivesAWipe() {
        val journal = open()
        journal.saveFollower(phoneWorkout, TestMessages.keyB, 1, "following")
        journal.clearAccount(TestMessages.keyA, wipeUnsent = true)
        assertNotNull(journal.follower())
    }

    @Test
    fun noPruneWhileFollowing() {
        val journal = open()
        journal.saveBinding(TestMessages.binding())
        journal.recordReceived(1_000)
        journal.saveFollower(phoneWorkout, TestMessages.keyA, 1, "following")
        assertFalse(journal.pruneStale(1_000 + 91 * 86_400_000L))
        assertNotNull(journal.binding())
    }
}

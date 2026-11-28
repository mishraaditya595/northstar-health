package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.HeartRatePoint
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.store.AckEffect
import `in`.beyondrep.wear.core.store.JournalFiles
import `in`.beyondrep.wear.core.store.SqlValue
import `in`.beyondrep.wear.core.store.WatchJournal
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/*
 * Port of PhoneInboxTests.swift. Swift feeds `receive(applicationContext:)` and `receive(userInfo:)`;
 * Wear feeds `receiveContext` (one JSON text per message type) and `receiveQueued` (one JSON text).
 * Not ported: the two workout_link ack tests (Wear sends no workout_link), and the non-string
 * context entry (`health_snapshot` = 42), which cannot be expressed as a Map<String, String>.
 * testReplayAfterPruneIsIgnored and testCapKeepsTheTombstoneJustWrittenEvenWhenItIsTheOldest
 * (WatchJournalTests.swift) live here because they drive the inbox.
 */
class PhoneInboxTest {
    private lateinit var files: JournalFiles
    private lateinit var journal: WatchJournal
    private lateinit var inbox: PhoneInbox
    private val m = TestMessages

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        journal = WatchJournal(files.db())
        inbox = PhoneInbox(journal)
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun now(iso: String = m.t0): Instant = Instant.parse(iso)

    private fun context(vararg messages: WatchMessage): Map<String, String> = messages.associate { it.type to it.encode() }

    private fun receive(ctx: Map<String, String>, at: Instant = now()) = inbox.receiveContext(ctx, at)
    private fun receive(vararg messages: WatchMessage, at: Instant = now()) = inbox.receiveContext(context(*messages), at)
    private fun queued(message: WatchMessage, at: Instant = now()) = inbox.receiveQueued(message.encode(), at)

    private fun completedFixture(): WatchMessage =
        WatchMessage.decode(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/completed_workout.json"))

    @Test
    fun bindingReplacesAndClearsThePreviousAccountsPlansAndHealth() {
        receive(m.binding(m.keyA), m.plans(m.keyA), m.health(m.keyA))
        assertNotNull(journal.plans(m.keyA))
        assertNotNull(journal.health(m.keyA, "2026-10-23"))

        receive(m.binding(m.keyB))
        assertNull(journal.plans(m.keyA))
        assertNull(journal.health(m.keyA, "2026-10-23"))
        assertEquals(m.keyB, journal.binding()?.accountKey)
    }

    @Test
    fun bindingWithTheSameKeyKeepsPlansAndUpdatesTheUnit() {
        receive(m.binding(m.keyA), m.plans(m.keyA))
        receive(m.binding(m.keyA, unit = "lb"))
        assertNotNull(journal.plans(m.keyA))
        assertEquals("lb", journal.binding()?.unit)
    }

    @Test
    fun bindingInTheSameContextIsAppliedBeforePlansAndHealth() {
        // Map order is arbitrary; binding must still go first.
        receive(m.plans(m.keyB), m.health(m.keyB), m.binding(m.keyB))
        assertNotNull(journal.plans(m.keyB))
        assertNotNull(journal.health(m.keyB, "2026-10-23"))
    }

    @Test
    fun plansForAnotherAccountAreDropped() {
        receive(m.binding(m.keyA))
        receive(m.plans(m.keyB), m.health(m.keyB))
        assertNull(journal.plans(m.keyB))
        assertNull(journal.plans(m.keyA))
        assertNull(journal.health(m.keyB, "2026-10-23"))
    }

    @Test
    fun plansWithoutAnyBindingAreDropped() {
        receive(m.plans(m.keyA))
        assertNull(journal.plans(m.keyA))
    }

    @Test
    fun accountClearedWithoutWipeKeepsTheOutbox() {
        receive(m.binding(m.keyA), m.plans(m.keyA))
        val completed = completedFixture()
        assertEquals(m.keyA, completed.accountKey)
        journal.saveCompleted(completed)

        queued(m.cleared(m.keyA, wipe = false))
        assertNull(journal.binding())
        assertNull(journal.plans(m.keyA))
        assertEquals(1, journal.pendingOutbox(10).size)
    }

    @Test
    fun accountClearedWithWipeRemovesTheOutbox() {
        receive(m.binding(m.keyA))
        journal.saveCompleted(completedFixture())
        queued(m.cleared(m.keyA, wipe = true))
        assertTrue(journal.pendingOutbox(10).isEmpty())
    }

    @Test
    fun accountClearedForAnotherKeyKeepsTheCurrentBinding() {
        receive(m.binding(m.keyB), m.plans(m.keyB))
        queued(m.cleared(m.keyA, wipe = false))
        assertEquals(m.keyB, journal.binding()?.accountKey)
        assertNotNull(journal.plans(m.keyB))
    }

    @Test
    fun badJsonEntryIsSkippedAndCounted() {
        val ctx = context(m.binding(m.keyA)) + mapOf("plans_snapshot" to "{not json", "health_snapshot" to "42")
        receive(ctx)
        assertEquals(m.keyA, journal.binding()?.accountKey)
        assertEquals(2, inbox.rejectedCount)

        inbox.receiveQueued("nope", now())
        inbox.receiveQueued("", now())
        assertEquals(4, inbox.rejectedCount)
    }

    @Test
    fun entryWhoseTypeDoesNotMatchItsKeyIsRejected() {
        receive(mapOf("plans_snapshot" to m.binding(m.keyA).encode()))
        assertNull(journal.binding())
        assertEquals(1, inbox.rejectedCount)
    }

    @Test
    fun clearedThenAReplayedOlderBindingIsRejected() {
        val old = m.binding(m.keyA, at = "2026-10-23T01:00:00Z")
        receive(old, m.plans(m.keyA))
        queued(m.cleared(m.keyA, at = "2026-10-23T02:00:00Z"))
        assertNull(journal.binding())

        // The watch relaunches and replays the context it received before the clear.
        receive(old, m.plans(m.keyA))
        assertNull(journal.binding())
        assertNull(journal.plans(m.keyA))
        assertEquals(0, inbox.rejectedCount, "a stale replay is ignored, not malformed")
    }

    @Test
    fun bindingNewerThanTheClearIsAppliedAfterIt() {
        queued(m.cleared(m.keyA, at = "2026-10-23T02:00:00Z"))
        receive(m.binding(m.keyA, at = "2026-10-23T03:00:00Z"))
        assertEquals(m.keyA, journal.binding()?.accountKey)
    }

    @Test
    fun aNewerBindingThenALateOlderClearIsIgnored() {
        receive(m.binding(m.keyA, at = "2026-10-23T01:00:00Z"))
        receive(m.binding(m.keyA, at = "2026-10-23T03:00:00Z"), m.plans(m.keyA))
        queued(m.cleared(m.keyA, at = "2026-10-23T02:00:00Z"))
        assertEquals(m.keyA, journal.binding()?.accountKey)
        assertNotNull(journal.plans(m.keyA))
    }

    @Test
    fun anOlderBindingDoesNotReplaceANewerOne() {
        receive(m.binding(m.keyA, unit = "lb", at = "2026-10-23T03:00:00Z"))
        receive(m.binding(m.keyA, unit = "kg", at = "2026-10-23T01:00:00Z"))
        assertEquals("lb", journal.binding()?.unit)
    }

    @Test
    fun replayingTheSameBindingMessageChangesNothing() {
        val binding = m.binding(m.keyA, unit = "lb")
        receive(binding, m.plans(m.keyA))
        receive(binding)
        assertEquals("lb", journal.binding()?.unit)
        assertNotNull(journal.plans(m.keyA))
        assertEquals(0, inbox.rejectedCount)
    }

    @Test
    fun clearedInTheContextIsAppliedLikeOneSentAsAQueuedItem() {
        receive(m.binding(m.keyA, at = "2026-10-23T01:00:00Z"))
        receive(m.cleared(m.keyA, at = "2026-10-23T02:00:00Z"))
        assertNull(journal.binding())
    }

    @Test
    fun accountDeletionWipesEvenWhenANewerBindingIsStored() {
        receive(m.binding(m.keyA, at = "2026-10-23T03:00:00Z"))
        journal.saveCompleted(completedFixture())
        queued(m.cleared(m.keyA, wipe = true, at = "2026-10-23T02:00:00Z"))
        assertNull(journal.binding())
        assertTrue(journal.pendingOutbox(10).isEmpty())
    }

    // Ack outcomes

    private fun id(message: WatchMessage) = message.messageId.lowercase()

    @Test
    fun storedAckForEachAppliedContextMessage() {
        val binding = m.binding(m.keyA)
        val plans = m.plans(m.keyA)
        val health = m.health(m.keyA)
        val outcomes = receive(health, plans, binding)
        assertEquals(
            listOf(
                AckOutcome(id(binding), m.keyA, "stored", null),
                AckOutcome(id(plans), m.keyA, "stored", null),
                AckOutcome(id(health), m.keyA, "stored", null),
            ),
            outcomes)
    }

    @Test
    fun sameHealthTwiceIsDuplicate() {
        val binding = m.binding(m.keyA)
        val health = m.health(m.keyA)
        receive(binding, health)
        val again = receive(binding, health)
        assertEquals(
            listOf(AckOutcome(id(binding), m.keyA, "duplicate", null), AckOutcome(id(health), m.keyA, "duplicate", null)),
            again)
        val plans = m.plans(m.keyA)
        assertEquals("stored", receive(plans).first().result)
        assertEquals("duplicate", receive(plans).first().result)
    }

    @Test
    fun plansForAnotherBoundAccountAreRejectedWrongAccount() {
        receive(m.binding(m.keyA))
        val plans = m.plans(m.keyB)
        val health = m.health(m.keyB)
        assertEquals(
            listOf(
                AckOutcome(id(plans), m.keyB, "rejected", "wrong_account"),
                AckOutcome(id(health), m.keyB, "rejected", "wrong_account"),
            ),
            receive(plans, health))
        assertNull(journal.plans(m.keyB))
    }

    @Test
    fun noAckWithoutBinding() {
        assertEquals(emptyList(), receive(m.plans(m.keyA), m.health(m.keyA)))
        assertEquals(emptyList(), inbox.receiveQueued("not json", now()))
        assertEquals(emptyList(), inbox.receiveQueued("", now()))
    }

    @Test
    fun clearedGivesAStoredAckAndDropsTheReceivedTime() {
        receive(m.binding(m.keyA))
        val cleared = m.cleared(m.keyA)
        assertEquals(listOf(AckOutcome(id(cleared), m.keyA, "stored", null)), queued(cleared))
        assertNull(journal.lastReceivedMs())
    }

    @Test
    fun receivedTimeRecordedAndClearedWithAccount() {
        assertNull(journal.lastReceivedMs())
        receive(m.binding(m.keyA), m.health(m.keyA), at = now("2026-10-23T05:00:00Z"))
        assertEquals(1_792_731_600_000, journal.lastReceivedMs())

        // A rejected message does not count as received.
        val later = now("2026-10-23T06:00:00Z")
        receive(m.plans(m.keyB), at = later)
        assertEquals(1_792_731_600_000, journal.lastReceivedMs())

        queued(m.cleared(m.keyA), at = later)
        assertNull(journal.lastReceivedMs())
    }

    @Test
    fun replayedDuplicatesDoNotMoveTheReceivedTime() {
        val ctx = context(m.binding(m.keyA), m.plans(m.keyA), m.health(m.keyA))
        receive(ctx, at = now("2026-10-23T05:00:00Z"))
        assertEquals(1_792_731_600_000, journal.lastReceivedMs())

        // The same context again at launch, days later: all duplicates.
        val outcomes = receive(ctx, at = now("2026-10-26T09:00:00Z"))
        assertEquals(listOf("duplicate", "duplicate", "duplicate"), outcomes.map { it.result })
        assertEquals(1_792_731_600_000, journal.lastReceivedMs())
    }

    // Acks for completed workouts

    private val ackSession = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    private fun queuedCompleted(key: String = m.keyA): WatchMessage {
        val base = completedFixture()
        val message = WatchMessage(m.id(), base.sentAtUtc, key, base.body)
        journal.queueCompleted(message, ackSession)
        return message
    }

    private fun ack(message: WatchMessage, result: String, key: String? = null): WatchMessage {
        val reason = if (result == "rejected") "invalid" else null
        return WatchMessage(
            m.id(), "2026-10-23T11:41:00Z", key ?: message.accountKey,
            WatchMessageBody.Ack(message.messageId, result, reason))
    }

    @Test
    fun storedAckMarksDelivered() {
        val q = queuedCompleted()
        queued(ack(q, "stored"))
        assertTrue(journal.pendingCompleted(10).isEmpty())
        assertEquals(listOf<AckEffect>(AckEffect.Delivered(ackSession)), inbox.lastAckEffects)
    }

    @Test
    fun rejectedAckMarksRejected() {
        val q = queuedCompleted()
        queued(ack(q, "rejected"))
        assertTrue(journal.pendingCompleted(10).isEmpty())
        assertEquals(listOf<AckEffect>(AckEffect.Rejected(ackSession)), inbox.lastAckEffects)
    }

    @Test
    fun ackWithOtherAccountKeyIsIgnored() {
        val q = queuedCompleted()
        queued(ack(q, "stored", key = m.keyB))
        assertEquals(1, journal.pendingCompleted(10).size)
        assertTrue(inbox.lastAckEffects.isEmpty())
        assertEquals(1, inbox.ignoredCount)
    }

    @Test
    fun ackProducesNoOutcome() {
        val q = queuedCompleted()
        assertTrue(queued(ack(q, "stored")).isEmpty())
        assertEquals(0, inbox.rejectedCount)
    }

    @Test
    fun ackForUnknownMessageChangesNothingAndThrowsNothing() {
        val unknown = WatchMessage(
            m.id(), "2026-10-23T11:41:00Z", m.keyA,
            WatchMessageBody.CompletedWorkout("x", 0, null, JsonObject(emptyMap())))
        assertTrue(queued(ack(unknown, "stored")).isEmpty())
        assertTrue(inbox.lastAckEffects.isEmpty())
    }

    /** A completed workout the phone has already acked: its session row says `delivered`. */
    private fun deliveredWorkout() {
        files.db().execute(
            "INSERT OR IGNORE INTO sessions(session_id, account_key, status, state_json) VALUES(?,?,?,?)",
            listOf(SqlValue.Text(ackSession), SqlValue.Text(m.keyA), SqlValue.Text("completed"), SqlValue.Text("{}")))
        queued(ack(queuedCompleted(), "stored"))
    }

    private fun queuedSeries(key: String = m.keyA): WatchMessage {
        val message = WatchMessage(
            m.id(), "2026-10-23T11:41:00Z", key,
            WatchMessageBody.WorkoutHealth(
                ackSession, "2026-10-23T11:00:00Z", "2026-10-23T11:40:00Z",
                listOf(HeartRatePoint("2026-10-23T11:00:00Z", 173)), 987.0))
        journal.saveWorkoutHealth(ackSession, key, message, 1_792_000_000_000)
        return message
    }

    @Test
    fun anyAckOfTheSeriesDeletesIt() {
        for (result in listOf("stored", "duplicate", "rejected")) {
            deliveredWorkout()
            val series = queuedSeries()
            assertEquals(1, journal.pendingWorkoutHealth(m.keyA, 10).size, result)
            assertTrue(queued(ack(series, result)).isEmpty())
            assertTrue(journal.pendingWorkoutHealth(m.keyA, 10).isEmpty(), result)
        }
    }

    @Test
    fun anAckOfTheSeriesFromAnotherAccountIsIgnored() {
        deliveredWorkout()
        val series = queuedSeries()
        queued(ack(series, "stored", key = m.keyB))
        assertEquals(1, journal.pendingWorkoutHealth(m.keyA, 10).size)
        assertEquals(1, inbox.ignoredCount)
    }

    // From WatchJournalTests.swift: pruning drives the inbox

    private val dayMs = 86_400_000L
    private val receivedMs = 1_792_000_000_000

    @Test
    fun replayAfterPruneIsIgnored() {
        val key = m.keyA
        val ctx = context(m.binding(key))
        val received = Instant.ofEpochMilli(receivedMs)
        receive(ctx, at = received)
        assertNotNull(journal.binding())
        assertTrue(journal.pruneStale(receivedMs + 91 * dayMs))
        assertNull(journal.binding())
        val ignoredBefore = inbox.ignoredCount
        receive(ctx, at = received.plusSeconds(91 * 86_400))
        assertNull(journal.binding())
        assertEquals(ignoredBefore + 1, inbox.ignoredCount)
    }

    @Test
    fun capKeepsTheTombstoneJustWrittenEvenWhenItIsTheOldest() {
        val key = m.keyA
        val ctx = context(m.binding(key))
        val received = Instant.ofEpochMilli(receivedMs)
        receive(ctx, at = received)
        val sentAt = assertNotNull(journal.bindingState()).sentAtMs
        for (n in 1..20) journal.recordCleared("other-$n", sentAt + n)
        assertTrue(journal.pruneStale(receivedMs + 91 * dayMs))
        assertEquals(sentAt, journal.clearedAt(key))
        assertNull(journal.clearedAt("other-1"))
        for (n in 2..20) assertEquals(sentAt + n, journal.clearedAt("other-$n"))
        val ignoredBefore = inbox.ignoredCount
        receive(ctx, at = received.plusSeconds(91 * 86_400))
        assertNull(journal.binding())
        assertEquals(ignoredBefore + 1, inbox.ignoredCount)
    }
}

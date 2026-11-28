package `in`.beyondrep.wear.core.glance

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.store.JournalFiles
import `in`.beyondrep.wear.core.store.WatchJournal
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/* Port of SyncLineTests.swift; waiting lines say "phone" where iOS says "iPhone". */
class SyncLineTest {
    private lateinit var files: JournalFiles
    private lateinit var journal: WatchJournal
    private val m = TestMessages
    private val kolkata = ZoneId.of("Asia/Kolkata")

    /** 10:43 on 2026-10-23 in Asia/Kolkata. */
    private val receivedMs = 1_792_732_380_000L

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        journal = WatchJournal(files.db())
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun line(reachable: Boolean): SyncLine =
        SyncLine.make(journal, reachable, Instant.parse("2026-10-23T06:00:00Z"), kolkata, Locale.US)

    @Test
    fun syncLineStates() {
        assertEquals(SyncLine.NotPaired, line(true))
        assertEquals(SyncLine.NotPaired, line(false))
        journal.saveBinding(m.binding())
        journal.recordReceived(receivedMs)
        val synced = line(true) as? SyncLine.Synced ?: fail("expected synced")
        assertTrue(synced.time.contains("10:43"), synced.time)
        val away = line(false) as? SyncLine.PhoneAway ?: fail("expected phoneAway")
        assertTrue(away.time.contains("10:43"), away.time)
    }

    private fun timeText(daysAgo: Long): String {
        journal.saveBinding(m.binding())
        journal.recordReceived(receivedMs - daysAgo * 86_400_000)
        return (line(true) as? SyncLine.Synced ?: fail("not synced")).time
    }

    @Test
    fun theDayComesBeforeTheTime() {
        val today = timeText(0)
        assertTrue(today.startsWith("Today "), today)
        assertTrue(today.contains("10:43"), today)
    }

    @Test
    fun yesterdayWeekdayAndDate() {
        assertTrue(timeText(1).startsWith("Yesterday "))
        assertTrue(timeText(3).startsWith("Tue ")) // 2026-10-20
        assertTrue(timeText(6).startsWith("Sat ")) // 2026-10-17
        val old = timeText(13) // 2026-10-10
        assertTrue(old.startsWith("10 Oct "), old)
        assertTrue(old.contains("10:43"), old)
    }

    @Test
    fun boundButNothingReceivedYetIsNotPaired() {
        journal.saveBinding(m.binding())
        assertEquals(SyncLine.NotPaired, line(true))
    }

    @Test
    fun clearingTheAccountDropsTheLine() {
        journal.saveBinding(m.binding())
        journal.recordReceived(receivedMs)
        journal.clearAccount(m.keyA, wipeUnsent = false)
        assertEquals(SyncLine.NotPaired, line(true))
    }

    private fun queue(key: String, session: String) {
        val base = WatchMessage.decode(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/completed_workout.json"))
        journal.queueCompleted(WatchMessage(m.id(), base.sentAtUtc, key, base.body), session)
    }

    @Test
    fun syncLineCountsWaitingWorkouts() {
        journal.saveBinding(m.binding(m.keyA))
        assertEquals(WaitingWorkouts(0, 0), WaitingWorkouts.make(journal))
        assertTrue(WaitingWorkouts.make(journal).lines.isEmpty())
        queue(m.keyA, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")
        assertEquals(listOf("1 workout waiting for phone"), WaitingWorkouts.make(journal).lines)
        queue(m.keyA, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")
        assertEquals(listOf("2 workouts waiting for phone"), WaitingWorkouts.make(journal).lines)
    }

    @Test
    fun syncLineShowsOtherAccountWaiting() {
        journal.saveBinding(m.binding(m.keyA))
        queue(m.keyB, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3")
        val waiting = WaitingWorkouts.make(journal)
        assertEquals(0, waiting.waiting)
        assertEquals(1, waiting.waitingOtherAccount)
        assertEquals(listOf("1 from another account waiting"), waiting.lines)
    }
}

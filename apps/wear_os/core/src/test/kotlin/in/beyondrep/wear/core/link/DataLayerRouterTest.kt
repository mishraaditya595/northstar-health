package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.store.JournalFiles
import `in`.beyondrep.wear.core.store.WatchJournal
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DataLayerRouterTest {
    private lateinit var files: JournalFiles
    private lateinit var journal: WatchJournal
    private lateinit var inbox: PhoneInbox
    private lateinit var router: DataLayerRouter
    private val m = TestMessages
    private val now = Instant.parse("2026-10-23T02:00:00Z")

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        journal = WatchJournal(files.db())
        inbox = PhoneInbox(journal)
        router = DataLayerRouter(inbox)
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun context(type: String, json: String) = DataChange(DataLayerPaths.context(type), json, deleted = false)

    @Test
    fun contextItemsAreAppliedAndAcked() {
        val binding = m.binding()
        val outcomes = router.apply(listOf(context("account_binding", binding.encode())), now)
        assertEquals(listOf("stored"), outcomes.map { it.result })
        assertEquals(binding.messageId, outcomes.single().messageId)
        assertNotNull(journal.binding())
    }

    @Test
    fun queuedPhoneItemsAreAppliedLikeUserInfo() {
        val binding = m.binding()
        val outcomes = router.apply(
            listOf(DataChange(DataLayerPaths.phoneQueue(binding.messageId), binding.encode(), deleted = false)), now)
        assertEquals(listOf("stored"), outcomes.map { it.result })
        assertNotNull(journal.binding())
    }

    @Test
    fun batchAppliesBindingBeforePlans() {
        val binding = m.binding(at = "2026-10-23T01:00:00Z")
        val plans = m.plans(names = listOf("Push"))
        // Plans first in the batch, binding first by send time.
        val outcomes = router.apply(
            listOf(context("plans_snapshot", plans.encode()), context("account_binding", binding.encode())), now)
        assertEquals(listOf("stored", "stored"), outcomes.map { it.result })
        assertEquals(binding.messageId, outcomes[0].messageId)
        assertNotNull(journal.plans(m.keyA), "plans are stored for the new key")
    }

    @Test
    fun healthSentBeforeTheBindingIsStillApplied() {
        // health sent 01:45, binding 01:50: type rank decides first, like Swift's receive loop.
        val binding = m.binding(at = "2026-10-23T01:50:00Z")
        val health = m.health()
        val outcomes = router.apply(
            listOf(context("health_snapshot", health.encode()), context("account_binding", binding.encode())), now)
        assertEquals(listOf(binding.messageId, health.messageId), outcomes.map { it.messageId })
        assertEquals(listOf("stored", "stored"), outcomes.map { it.result })
        assertNotNull(journal.health(m.keyA, "2026-10-23"))
    }

    @Test
    fun equalSendTimesStillApplyBindingFirst() {
        val binding = m.binding(at = "2026-10-23T01:00:00Z")
        val plans = m.plans(names = listOf("Push")) // sent 2026-10-23T01:00:00Z too
        router.apply(
            listOf(context("plans_snapshot", plans.encode()), context("account_binding", binding.encode())), now)
        assertNotNull(journal.plans(m.keyA))
    }

    @Test
    fun emptyContextMeansAccountCleared() {
        // PhoneInbox.swift ignores an empty application context: the phone clears the watch with
        // a queued account_cleared, and deletes its context items so a stale copy never replays.
        // The router pins both halves: deleted context items change nothing, the queued clear does.
        val binding = m.binding(at = "2026-10-23T00:00:00Z")
        router.apply(
            listOf(
                context("account_binding", binding.encode()),
                context("plans_snapshot", m.plans().encode()),
                context("health_snapshot", m.health().encode()),
            ),
            now,
        )
        assertNotNull(journal.plans(m.keyA))
        val deletions = listOf("account_binding", "plans_snapshot", "health_snapshot")
            .map { DataChange(DataLayerPaths.context(it), null, deleted = true) }
        assertTrue(router.apply(deletions, now).isEmpty())
        assertNotNull(journal.plans(m.keyA), "a deletion alone changes nothing, like an empty context on iOS")

        val cleared = m.cleared(at = "2026-10-23T01:30:00Z")
        val outcomes = router.apply(
            listOf(DataChange(DataLayerPaths.phoneQueue(cleared.messageId), cleared.encode(), deleted = false)), now)
        assertEquals(listOf("stored"), outcomes.map { it.result })
        assertNull(journal.binding())
        assertNull(journal.plans(m.keyA))
        assertNull(journal.health(m.keyA, "2026-10-23"))
    }

    @Test
    fun deletedQueuedItemsAndWatchQueuedPathsAreIgnored() {
        val binding = m.binding()
        val outcomes = router.apply(
            listOf(
                DataChange(DataLayerPaths.phoneQueue(binding.messageId), null, deleted = true),
                DataChange(DataLayerPaths.watchQueue("x"), binding.encode(), deleted = false),
                DataChange("/somewhere/else", binding.encode(), deleted = false),
            ),
            now,
        )
        assertTrue(outcomes.isEmpty())
        assertNull(journal.binding())
    }

    @Test
    fun aMalformedQueuedItemHasNoOutcomeAndIsCounted() {
        val outcomes = router.apply(listOf(DataChange(DataLayerPaths.phoneQueue("bad"), "{nope", deleted = false)), now)
        assertTrue(outcomes.isEmpty())
        assertEquals(1, inbox.rejectedCount)
    }

    @Test
    fun aContextItemWhoseTypeDoesNotMatchItsPathIsRejected() {
        val outcomes = router.apply(listOf(context("plans_snapshot", m.binding().encode())), now)
        assertTrue(outcomes.isEmpty())
        assertEquals(1, inbox.rejectedCount)
    }
}

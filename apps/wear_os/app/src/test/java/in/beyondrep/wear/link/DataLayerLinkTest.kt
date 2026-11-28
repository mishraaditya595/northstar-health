package `in`.beyondrep.wear.link

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.link.DataChange
import `in`.beyondrep.wear.core.link.DataLayerPaths
import `in`.beyondrep.wear.core.link.DataLayerRouter
import `in`.beyondrep.wear.core.link.PhoneInbox
import `in`.beyondrep.wear.core.store.WatchJournal
import `in`.beyondrep.wear.store.AndroidSqlDatabase
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A fake Data Layer: the items the phone left and the items the watch put or deleted. */
private class FakeItems : DataItems {
    val store = linkedMapOf<String, String>()
    val puts = mutableListOf<Pair<String, String>>()
    val deletes = mutableListOf<String>()

    override suspend fun put(path: String, json: String) {
        store[path] = json
        puts += path to json
    }

    override suspend fun delete(path: String) {
        store.remove(path)
        deletes += path
    }

    override suspend fun all(prefix: String): List<DataChange> =
        store.filterKeys { it.startsWith(prefix) }.map { (path, json) -> DataChange(path, json, deleted = false) }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DataLayerLinkTest {
    private val keyA = "0123456789abcdef".repeat(4)
    private val now = Instant.parse("2026-10-23T02:00:00Z")
    private lateinit var journal: WatchJournal
    private lateinit var inbox: PhoneInbox
    private lateinit var items: FakeItems
    private lateinit var link: DataLayerLink
    private var applied = 0

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        journal = WatchJournal(AndroidSqlDatabase(context, "link-test-${UUID.randomUUID()}.db"))
        inbox = PhoneInbox(journal)
        items = FakeItems()
        link = DataLayerLink(items, DataLayerRouter(inbox), { now }, { applied += 1 })
    }

    private fun binding(): WatchMessage = WatchMessage(
        UUID.randomUUID().toString(), "2026-10-23T01:00:00Z", keyA, WatchMessageBody.AccountBinding("kg"))

    private fun ack(json: String): WatchMessageBody.Ack =
        WatchMessage.decode(json).body as WatchMessageBody.Ack

    @Test
    fun aQueuedBindingIsAckedAndTheItemDeleted() = runBlocking<Unit> {
        val message = binding()
        val path = DataLayerPaths.phoneQueue(message.messageId)
        items.store[path] = message.encode()
        link.onChanges(listOf(DataChange(path, message.encode(), deleted = false)))

        assertNotNull(journal.binding())
        val put = items.puts.single()
        assertTrue(put.first.startsWith(DataLayerPaths.WATCH_QUEUE_PREFIX), put.first)
        val body = ack(put.second)
        assertEquals(message.messageId, body.ackedMessageId)
        assertEquals("stored", body.result)
        assertEquals(listOf(path), items.deletes)
        assertNull(items.store[path])
        assertEquals(1, applied)
    }

    @Test
    fun aContextItemIsAckedButNotDeleted() = runBlocking<Unit> {
        val message = binding()
        val path = DataLayerPaths.context("account_binding")
        link.onChanges(listOf(DataChange(path, message.encode(), deleted = false)))
        assertNotNull(journal.binding())
        assertEquals(1, items.puts.size)
        assertTrue(items.deletes.isEmpty(), "context items are the phone's, replaced by it")
    }

    @Test
    fun catchUpAppliesItemsPresentBeforeTheAppStarted() = runBlocking<Unit> {
        val message = binding()
        items.store[DataLayerPaths.context("account_binding")] = message.encode()
        link.catchUp()
        assertNotNull(journal.binding())
        assertEquals(1, items.puts.size)
        // A second resume finds only duplicates and sends no new ack.
        link.catchUp()
        assertEquals(1, items.puts.size)
    }

    @Test
    fun aMalformedQueuedItemIsDeletedWithoutAnAck() = runBlocking<Unit> {
        val path = DataLayerPaths.phoneQueue("bad")
        items.store[path] = "{nope"
        link.onChanges(listOf(DataChange(path, "{nope", deleted = false)))
        assertTrue(items.puts.isEmpty(), "PhoneInbox gives a rejected entry no outcome, so no ack")
        assertEquals(listOf(path), items.deletes)
        assertEquals(1, inbox.rejectedCount)
    }

    @Test
    fun deletionsAloneChangeNothing() = runBlocking<Unit> {
        link.onChanges(listOf(DataChange(DataLayerPaths.context("plans_snapshot"), null, deleted = true)))
        assertTrue(items.puts.isEmpty())
        assertTrue(items.deletes.isEmpty())
        assertEquals(0, applied)
    }

    @Test
    fun aFailedAckKeepsThePhoneItemForTheNextTry() = runBlocking<Unit> {
        val message = binding()
        val path = DataLayerPaths.phoneQueue(message.messageId)
        items.store[path] = message.encode()
        val failing = object : DataItems by items {
            override suspend fun put(path: String, json: String) {
                throw IllegalStateException("offline")
            }
        }
        val flaky = DataLayerLink(failing, DataLayerRouter(inbox), { now }, { applied += 1 })
        runCatching { flaky.onChanges(listOf(DataChange(path, message.encode(), deleted = false))) }
        assertNotNull(items.store[path], "not deleted, so it is applied again as a duplicate and acked")
        assertNotNull(journal.binding(), "the journal write happened before the ack")
        assertEquals(1, applied, "screens refresh because the journal changed, even though the ack failed")
    }

    @Test
    fun oldWatchAcksAreDeletedAfterANewOneIsPut() = runBlocking<Unit> {
        // 25 acks left by earlier runs, the oldest first.
        for (i in 1..25) {
            val minute = i.toString().padStart(2, '0')
            val id = "old-$minute"
            items.store[DataLayerPaths.watchQueue(id)] =
                """{"type":"ack","sent_at_utc":"2026-10-23T01:$minute:00Z"}"""
        }
        val message = binding()
        val path = DataLayerPaths.phoneQueue(message.messageId)
        items.store[path] = message.encode()
        link.onChanges(listOf(DataChange(path, message.encode(), deleted = false)))

        val watchItems = items.store.keys.filter { it.startsWith(DataLayerPaths.WATCH_QUEUE_PREFIX) }
        assertEquals(20, watchItems.size)
        assertTrue(DataLayerPaths.watchQueue("old-01") !in watchItems, "the oldest acks go first")
        assertTrue(items.puts.single().first in watchItems, "the new ack is kept")
    }
}

package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class OutboxSenderTest {
    private fun message(id: String) = WatchMessage(id, TestMessages.t0, TestMessages.keyA, WatchMessageBody.AccountCleared(false))

    @Test
    fun putsOnlyWhatIsMissing() {
        val a = message("00000000-0000-4000-8000-000000000001")
        val b = message("00000000-0000-4000-8000-000000000002")
        val puts = OutboxSender.toPut(listOf(a, b), setOf(DataLayerPaths.watchQueue(a.messageId)))
        assertEquals(listOf(DataLayerPaths.watchQueue(b.messageId) to b.encode()), puts)
    }

    @Test
    fun keepsJournalOrder() {
        val ids = (3 downTo 1).map { "00000000-0000-4000-8000-00000000000$it" }
        val puts = OutboxSender.toPut(ids.map(::message), emptySet())
        assertEquals(ids.map(DataLayerPaths::watchQueue), puts.map { it.first })
    }

    @Test
    fun emptyWhenAllPresent() {
        val a = message("00000000-0000-4000-8000-000000000001")
        assertTrue(OutboxSender.toPut(listOf(a), setOf(DataLayerPaths.watchQueue(a.messageId))).isEmpty())
    }
}

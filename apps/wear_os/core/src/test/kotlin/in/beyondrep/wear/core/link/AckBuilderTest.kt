package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull

/** Port of AckBuilderTests.swift. */
class AckBuilderTest {
    private val m = TestMessages

    @Test
    fun ackJsonDecodesAsContractAck() {
        val acked = "77777777-3333-4333-8333-0000000000aa"
        val own = UUID.randomUUID().toString()
        val json = AckBuilder.json(
            AckOutcome(acked, m.keyA, "stored", null), own, Instant.parse("2026-10-23T05:00:00Z"))
        val message = WatchMessage.decode(json)
        assertEquals("ack", message.type)
        assertEquals(m.keyA, message.accountKey)
        assertEquals(own, message.messageId)
        assertEquals("2026-10-23T05:00:00Z", message.sentAtUtc)
        val body = assertIs<WatchMessageBody.Ack>(message.body)
        assertEquals(acked, body.ackedMessageId)
        assertEquals("stored", body.result)
        assertNull(body.reason)
    }

    @Test
    fun rejectedAckKeepsItsReason() {
        val json = AckBuilder.json(
            AckOutcome("77777777-3333-4333-8333-0000000000bb", m.keyB, "rejected", "wrong_account"),
            UUID.randomUUID().toString(), Instant.parse("2026-10-23T05:00:00Z"))
        val body = assertIs<WatchMessageBody.Ack>(WatchMessage.decode(json).body)
        assertEquals("rejected", body.result)
        assertEquals("wrong_account", body.reason)
    }

    @Test
    fun ackCarriesNoHealthValues() {
        val json = AckBuilder.json(
            AckOutcome(m.id(), m.keyA, "duplicate", null), UUID.randomUUID().toString(), Instant.now())
        for (word in listOf("sleep", "hrv", "steps", "resting")) assertFalse(json.lowercase().contains(word), word)
    }
}

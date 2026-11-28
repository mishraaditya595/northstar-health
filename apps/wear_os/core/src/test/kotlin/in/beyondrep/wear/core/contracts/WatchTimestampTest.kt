package `in`.beyondrep.wear.core.contracts

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Port of WatchTimestampTests.swift. */
class WatchTimestampTest {
    @Test
    fun wholeSecondsAndMillisecondsFromDart() {
        assertEquals(1_795_487_401_000, WatchTimestamp.milliseconds("2026-11-24T02:30:01Z"))
        assertEquals(1_795_487_401_123, WatchTimestamp.milliseconds("2026-11-24T02:30:01.123Z"))
        assertEquals(1_795_487_401_000, WatchTimestamp.milliseconds("2026-11-24T02:30:01.000Z"))
    }

    @Test
    fun moreFractionalDigitsAreTruncatedNotRejected() {
        assertEquals(1_795_487_401_123, WatchTimestamp.milliseconds("2026-11-24T02:30:01.123456Z"))
    }

    @Test
    fun offsetsAreHonoured() {
        assertEquals(1_795_487_401_500, WatchTimestamp.milliseconds("2026-11-24T08:00:01.500+05:30"))
    }

    @Test
    fun garbageIsNull() {
        assertNull(WatchTimestamp.milliseconds("yesterday"))
        assertNull(WatchTimestamp.milliseconds("2026-11-24T02:30:01."))
    }

    @Test
    fun timestampVariantsMatchSwift() {
        // Same strings and values as the Swift expectations for whole seconds, fraction and offset.
        assertEquals(1_795_773_600_000, WatchTimestamp.milliseconds("2026-11-27T10:00:00Z"))
        assertEquals(1_795_773_600_250, WatchTimestamp.milliseconds("2026-11-27T10:00:00.250Z"))
        assertEquals(1_795_773_600_000, WatchTimestamp.milliseconds("2026-11-27T15:30:00+05:30"))
        assertNull(WatchTimestamp.milliseconds("not a time"))
        assertEquals(1_795_773_600_250, WatchTimestamp.instant("2026-11-27T10:00:00.250Z")?.toEpochMilli())
    }

    @Test
    fun aMessageWithMillisecondsDecodesAndRoundTrips() {
        val key = "0123456789abcdef".repeat(4)
        val message = WatchMessage(
            messageId = "11111111-2222-4333-8444-555555555555", sentAtUtc = "2026-11-24T02:30:01.123Z",
            accountKey = key, body = WatchMessageBody.AccountBinding(unit = "kg"))
        assertEquals("2026-11-24T02:30:01.123Z", WatchMessage.decode(message.encode()).sentAtUtc)
    }
}

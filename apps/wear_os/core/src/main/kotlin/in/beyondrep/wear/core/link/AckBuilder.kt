package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import java.time.Instant

/**
 * What the watch did with one phone message, to send back as an `ack`. It holds ids and a
 * result only, never a health value. [result] is `stored`, `duplicate` or `rejected`;
 * [reason] is `wrong_account` for a rejected message, otherwise null.
 */
data class AckOutcome(val messageId: String, val accountKey: String, val result: String, val reason: String?)

object AckBuilder {
    /** A valid watch_link `ack` message as JSON text. */
    fun json(outcome: AckOutcome, messageId: String, now: Instant): String =
        WatchMessage(
            messageId.lowercase(), WatchTimestamp.format(now), outcome.accountKey,
            WatchMessageBody.Ack(outcome.messageId, outcome.result, outcome.reason),
        ).encode()
}

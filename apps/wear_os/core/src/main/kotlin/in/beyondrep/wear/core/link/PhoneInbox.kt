package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.store.AckEffect
import `in`.beyondrep.wear.core.store.WatchJournal
import java.time.Instant

/**
 * Decodes what the phone sends (data items and messages) and stores it in the journal.
 * Nothing here throws for a bad entry: it is skipped and counted. Plans and health for any
 * account other than the stored binding are dropped, so one account's data never shows under
 * another.
 */
class PhoneInbox(private val journal: WatchJournal) {
    /** Entries that could not be decoded or did not match their key (for tests). */
    var rejectedCount = 0
        private set

    /** Well-formed entries not applied because a newer binding or a later clear is stored. */
    var ignoredCount = 0
        private set

    /** One entry per applied `ack` for a completed workout, so the app can refresh. */
    val lastAckEffects: MutableList<AckEffect> = mutableListOf()

    /**
     * Context keys are message types and each value is a JSON string. The binding is applied
     * first because map order is arbitrary. Returns one outcome per message handled, in that
     * order. Undecodable entries have no outcome.
     */
    fun receiveContext(latestByType: Map<String, String>, now: Instant): List<AckOutcome> {
        val outcomes = mutableListOf<AckOutcome>()
        for (type in listOf("account_binding", "account_cleared", "plans_snapshot", "health_snapshot")) {
            val text = latestByType[type] ?: continue
            val message = decode(text)
            if (message == null || message.type != type) {
                rejectedCount += 1
                continue
            }
            apply(message, now)?.let(outcomes::add)
        }
        return outcomes
    }

    /** One-off messages arrive as a single JSON text. */
    fun receiveQueued(json: String, now: Instant): List<AckOutcome> {
        val message = decode(json)
        if (message == null) {
            rejectedCount += 1
            return emptyList()
        }
        return listOfNotNull(apply(message, now))
    }

    private fun decode(text: String): WatchMessage? = try {
        WatchMessage.decode(text)
    } catch (_: Exception) {
        null
    }

    private fun apply(message: WatchMessage, now: Instant): AckOutcome? {
        val id = message.messageId.lowercase()
        fun outcome(result: String, reason: String? = null) = AckOutcome(id, message.accountKey, result, reason)
        // Only newly stored data counts as received: the launch replay is all duplicates.
        fun received() = journal.recordReceived(now.toEpochMilli())

        when (val body = message.body) {
            is WatchMessageBody.AccountBinding -> {
                val sentAt = WatchTimestamp.milliseconds(message.sentAtUtc)
                if (sentAt == null) {
                    rejectedCount += 1
                    return null
                }
                val clearedAt = journal.clearedAt(message.accountKey)
                if (clearedAt != null && sentAt <= clearedAt) {
                    ignoredCount += 1
                    return null
                }
                val current = journal.bindingState()
                if (current != null) {
                    if (current.messageId == id) return outcome("duplicate")
                    if (sentAt < current.sentAtMs) {
                        ignoredCount += 1
                        return null
                    }
                    if (current.accountKey != message.accountKey) {
                        journal.clearAccount(current.accountKey, wipeUnsent = false)
                    }
                }
                journal.saveBinding(message)
                received()
                return outcome("stored")
            }
            is WatchMessageBody.AccountCleared -> {
                val sentAt = WatchTimestamp.milliseconds(message.sentAtUtc)
                if (sentAt == null) {
                    rejectedCount += 1
                    return null
                }
                journal.recordCleared(message.accountKey, sentAt)
                // A clear older than the binding in place is late; deletion always applies.
                val current = journal.bindingState()
                if (!body.wipeUnsent && current != null && current.accountKey == message.accountKey &&
                    sentAt < current.sentAtMs
                ) {
                    ignoredCount += 1
                    return outcome("stored")
                }
                journal.clearAccount(message.accountKey, body.wipeUnsent)
                return outcome("stored")
            }
            is WatchMessageBody.PlansSnapshot -> {
                val bound = journal.binding() ?: return null
                if (bound.accountKey != message.accountKey) return outcome("rejected", "wrong_account")
                if (journal.plans(bound.accountKey)?.messageId?.lowercase() == id) return outcome("duplicate")
                journal.savePlans(message)
                received()
                return outcome("stored")
            }
            is WatchMessageBody.HealthSnapshot -> {
                val bound = journal.binding() ?: return null
                if (bound.accountKey != message.accountKey) return outcome("rejected", "wrong_account")
                if (journal.health(bound.accountKey, body.localDate)?.messageId?.lowercase() == id) {
                    return outcome("duplicate")
                }
                journal.saveHealth(message)
                received()
                return outcome("stored")
            }
            is WatchMessageBody.Ack -> {
                // An ack is never acked. It counts only for the account the workout (or its heart rate series) was queued under.
                val queuedKey = journal.queuedCompletedAccountKey(body.ackedMessageId)
                    ?: journal.queuedWorkoutHealthAccountKey(body.ackedMessageId) ?: return null
                if (queuedKey != message.accountKey) {
                    ignoredCount += 1
                    return null
                }
                journal.applyAck(body.ackedMessageId, body.result)?.let(lastAckEffects::add)
                return null
            }
            else -> {
                rejectedCount += 1
                return null
            }
        }
    }
}

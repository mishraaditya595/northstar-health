package `in`.beyondrep.wear.core.glance

import `in`.beyondrep.wear.core.store.WatchJournal
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * The status line at the top of the watch Home. The watch only knows when it last stored phone
 * data; "synced" never claims more than that.
 */
sealed interface SyncLine {
    /** Nothing bound, or nothing received yet. */
    data object NotPaired : SyncLine

    /** Phone reachable; [time] is the day and short local time of the last data. */
    data class Synced(val time: String) : SyncLine

    /** Phone not reachable; data stays and is dated. */
    data class PhoneAway(val time: String) : SyncLine

    companion object {
        fun make(journal: WatchJournal, isPhoneReachable: Boolean, now: Instant, zone: ZoneId, locale: Locale): SyncLine {
            if (journal.binding() == null) return NotPaired
            val ms = journal.lastReceivedMs() ?: return NotPaired
            val received = Instant.ofEpochMilli(ms)
            val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).withZone(zone)
            val text = "${dayLabel(received, now, zone, locale)} ${time.format(received)}"
            return if (isPhoneReachable) Synced(text) else PhoneAway(text)
        }

        /** "Today", "Yesterday", a weekday for the last 6 days, then "10 Oct". */
        private fun dayLabel(date: Instant, now: Instant, zone: ZoneId, locale: Locale): String {
            val days = ChronoUnit.DAYS.between(date.atZone(zone).toLocalDate(), now.atZone(zone).toLocalDate())
            if (days <= 0) return "Today"
            if (days == 1L) return "Yesterday"
            return DateTimeFormatter.ofPattern(if (days <= 6) "EEE" else "d MMM", locale).withZone(zone).format(date)
        }
    }
}

/**
 * Completed workouts still on the watch because the phone has not acknowledged them, counted
 * separately for the bound account and others.
 */
data class WaitingWorkouts(val waiting: Int, val waitingOtherAccount: Int) {
    /** Status lines for the sync screen; empty when nothing waits. */
    val lines: List<String>
        get() = buildList {
            if (waiting > 0) add(if (waiting == 1) "1 workout waiting for phone" else "$waiting workouts waiting for phone")
            if (waitingOtherAccount > 0) add("$waitingOtherAccount from another account waiting")
        }

    companion object {
        fun make(journal: WatchJournal): WaitingWorkouts {
            val counts = journal.waitingCounts(journal.binding()?.accountKey)
            return WaitingWorkouts(counts.thisAccount, counts.otherAccounts)
        }
    }
}

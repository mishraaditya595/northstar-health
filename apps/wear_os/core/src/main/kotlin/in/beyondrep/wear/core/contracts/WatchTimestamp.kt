package `in`.beyondrep.wear.core.contracts

import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

/**
 * Reads the date-times of watch_link messages as epoch milliseconds (port of WatchTimestamp.swift).
 * Any number of fractional digits is accepted; digits beyond three are cut.
 */
object WatchTimestamp {
    fun milliseconds(text: String): Long? {
        var base = text.uppercase()
        var fractionMs = 0L
        val dot = base.indexOf('.')
        if (dot >= 0) {
            var end = dot + 1
            while (end < base.length && base[end] in '0'..'9') end++
            val digits = base.substring(dot + 1, end)
            if (digits.isEmpty()) return null
            fractionMs = digits.take(3).padEnd(3, '0').toLong()
            base = base.substring(0, dot) + base.substring(end)
        }
        val date = try {
            OffsetDateTime.parse(base)
        } catch (_: DateTimeParseException) {
            return null
        }
        return Math.floorDiv(date.toInstant().toEpochMilli(), 1000L) * 1000 + fractionMs
    }

    fun instant(text: String): Instant? = milliseconds(text)?.let { Instant.ofEpochMilli(it) }
}

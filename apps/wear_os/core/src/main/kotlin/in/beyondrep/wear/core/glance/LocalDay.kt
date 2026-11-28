package `in`.beyondrep.wear.core.glance

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Local calendar days as the contract writes them (`yyyy-MM-dd`). */
object LocalDay {
    fun date(now: Instant, zone: ZoneId): LocalDate = now.atZone(zone).toLocalDate()

    fun string(date: LocalDate): String = date.toString()
}

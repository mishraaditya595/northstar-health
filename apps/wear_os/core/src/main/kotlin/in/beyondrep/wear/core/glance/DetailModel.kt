package `in`.beyondrep.wear.core.glance

import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.store.WatchJournal
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

data class DayPoint(
    val date: LocalDate,
    /** One-letter weekday ("M"). */
    val label: String,
    /** Null for a day the phone sent no value for; never 0 for missing. */
    val value: Int?,
    val isToday: Boolean,
)

data class SleepStages(val deep: Int, val core: Int, val rem: Int, val awake: Int)

/**
 * One metric's detail screen: today, the phone's usual and the 7 days ending today, from today's
 * `health_snapshot`. Nothing is computed beyond the week average; the phone wrote every other number.
 */
data class DetailModel(
    val title: String,
    val value: String,
    val unit: String?,
    val caption: String?,
    val usual: Int?,
    /** Always 7 days ending today, oldest first. */
    val week: List<DayPoint>,
    /** Only when the snapshot has all four stage keys. */
    val stages: SleepStages?,
    /** Mean of the days with a value, rounded; null when none has one. */
    val weekAverage: Int?,
) {
    companion object {
        /**
         * Null when nothing is bound or there is no snapshot for today's local date, so
         * yesterday's week is never shown.
         */
        fun make(metric: Metric, journal: WatchJournal, now: Instant, zone: ZoneId, locale: Locale): DetailModel? {
            val todayDate = LocalDay.date(now, zone)
            val today = LocalDay.string(todayDate)
            journal.purgeHealth(today)
            val binding = journal.binding() ?: return null
            val raw: JsonObject = (journal.health(binding.accountKey, today)?.body as? WatchMessageBody.HealthSnapshot)?.raw
                ?: return null

            val sleep = HealthJson.obj(raw["sleep"])
            val title: String
            val unit: String?
            val weekKey: String
            val top: Int?
            val usual: Int?
            when (metric) {
                Metric.SLEEP -> {
                    title = "Sleep"; unit = null; weekKey = "asleep_minutes"
                    top = HealthJson.int(sleep?.get("asleep_minutes")); usual = null
                }
                Metric.RESTING_HR -> {
                    title = "Resting HR"; unit = "bpm"; weekKey = "resting_hr_bpm"
                    top = HealthJson.int(raw["resting_hr_bpm"]); usual = HealthJson.int(raw["resting_hr_usual_bpm"])
                }
                Metric.HRV -> {
                    title = "HRV"; unit = "ms"; weekKey = "hrv_ms"
                    top = HealthJson.int(raw["hrv_ms"]); usual = HealthJson.int(raw["hrv_usual_ms"])
                }
                Metric.STEPS -> {
                    title = "Steps"; unit = null; weekKey = "steps"
                    top = HealthJson.int(raw["steps"]); usual = null
                }
            }

            val days = HealthJson.objects(raw["week"])
                .mapNotNull { day -> HealthJson.string(day["local_date"])?.let { it to day } }.toMap()
            val labeler = DateTimeFormatter.ofPattern("EEEEE", locale)
            val week = (6 downTo 0).map { back ->
                val date = todayDate.minusDays(back.toLong())
                var value = HealthJson.int(days[LocalDay.string(date)]?.get(weekKey))
                // Today's point is the number the tile shows.
                if (back == 0 && top != null) value = top
                DayPoint(date, labeler.format(date), value, back == 0)
            }
            val present = week.mapNotNull { it.value }
            val average = if (present.isEmpty()) null else Math.round(present.sum().toDouble() / present.size).toInt()

            val shown = top ?: week.last().value
            val value = when {
                shown == null -> GlanceState.MISSING
                metric == Metric.SLEEP -> GlanceState.sleepText(shown)
                metric == Metric.STEPS -> GlanceState.count(shown, locale)
                else -> shown.toString()
            }
            val caption = when (metric) {
                Metric.SLEEP -> HealthJson.int(sleep?.get("score"))?.let { "Score $it" }
                Metric.RESTING_HR, Metric.HRV -> usual?.let { "Usual $it ${unit ?: ""}" }
                Metric.STEPS -> "So far today"
            }
            var stages: SleepStages? = null
            if (sleep != null && metric == Metric.SLEEP) {
                val deep = HealthJson.int(sleep["deep_minutes"])
                val core = HealthJson.int(sleep["core_minutes"])
                val rem = HealthJson.int(sleep["rem_minutes"])
                val awake = HealthJson.int(sleep["awake_minutes"])
                if (deep != null && core != null && rem != null && awake != null) stages = SleepStages(deep, core, rem, awake)
            }
            return DetailModel(title, value, unit, caption, usual, week, stages, average)
        }
    }
}

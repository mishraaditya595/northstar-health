package `in`.beyondrep.wear.core.glance

import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.store.WatchJournal
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

data class ReadinessLine(val score: Int, val band: String, val headline: String)

/** How a status line is coloured. The phone decides it for readiness factors, the watch for tile lines. */
enum class Tone(val wire: String) {
    GOOD("good"), NEUTRAL("neutral"), CAUTION("caution");

    companion object {
        fun fromWire(text: String?): Tone? = entries.firstOrNull { it.wire == text }
    }
}

/** The four health tiles; also the key for a detail screen. */
enum class Metric { SLEEP, RESTING_HR, HRV, STEPS }

data class GlanceTile(
    val label: String,
    val value: String,
    val unit: String?,
    /** One coloured line under the value ("Score 90", "−2 vs usual"); null when nothing to compare. */
    val status: String?,
    val tone: Tone,
    val metric: Metric,
)

data class PlanRow(
    val id: String,
    val name: String,
    /** "6 exercises" for today's program workout, null when the count is unknown or zero. */
    val subtitle: String? = null,
    val exerciseCount: Int = 0,
)

data class Glance(
    val readiness: ReadinessLine?,
    /** The phone's one-line reason under the readiness headline. */
    val readinessReason: String?,
    val factors: List<Factor>,
    val tiles: List<GlanceTile>,
    val caption: String,
    val today: PlanRow?,
    val plans: List<PlanRow>,
) {
    /** One readiness input with the phone's wording. */
    data class Factor(val input: String, val status: String, val tone: Tone)
}

/** Reads numbers the way the Swift core does: any JSON number, truncated to an Int. */
internal object HealthJson {
    fun int(value: JsonElement?): Int? {
        val p = value as? JsonPrimitive ?: return null
        if (p.isString) return null
        return p.content.toLongOrNull()?.toInt() ?: p.content.toDoubleOrNull()?.toInt()
    }

    fun string(value: JsonElement?): String? = (value as? JsonPrimitive)?.takeIf { it.isString }?.content

    fun obj(value: JsonElement?): JsonObject? = value as? JsonObject

    fun objects(value: JsonElement?): List<JsonObject> = (value as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
}

/**
 * What the Home screen shows, computed from the journal. Only values the phone sent are shown;
 * missing is "—", never 0, and health from another local date is never shown. Readiness and
 * every score come from the phone only. (The watch reads no health itself before Wear stage 5.)
 */
sealed interface GlanceState {
    data object NotPaired : GlanceState

    data class Ready(val glance: Glance) : GlanceState

    companion object {
        const val MISSING = "—"
        const val REFRESH_CAPTION = "Open BeyondRep on your phone to refresh"

        fun make(journal: WatchJournal, now: Instant, zone: ZoneId, locale: Locale): GlanceState {
            val today = LocalDay.string(LocalDay.date(now, zone))
            // Health values end at local midnight (ADR-0012), also when nothing is paired.
            journal.purgeHealth(today)
            val binding = journal.binding() ?: return NotPaired
            val key = binding.accountKey

            val plans = mutableListOf<PlanRow>()
            var todayRow: PlanRow? = null
            val plansBody = journal.plans(key)?.body as? WatchMessageBody.PlansSnapshot
            if (plansBody != null) {
                val raw = plansBody.raw
                val items = (raw["plans"] as? JsonArray) ?: JsonArray(emptyList())
                for (plan in items.mapNotNull { it as? JsonObject }) {
                    val id = HealthJson.string(plan["plan_id"])
                    val name = HealthJson.string(plan["name"])
                    if (id != null && name != null) {
                        plans += PlanRow(id, name, exerciseCount = (plan["exercises"] as? JsonArray)?.size ?: 0)
                    }
                }
                val t = HealthJson.obj(raw["today"])
                val todayId = HealthJson.string(t?.get("plan_id"))
                val label = HealthJson.string(t?.get("label"))
                if (t != null && HealthJson.string(t["local_date"]) == today && todayId != null && label != null) {
                    // The snapshot carries no week or day of the program, so the subtitle is the
                    // exercise count of the plan, when known.
                    val count = plans.firstOrNull { it.id == todayId }?.exerciseCount ?: 0
                    todayRow = PlanRow(
                        todayId, label,
                        if (count == 0) null else if (count == 1) "1 exercise" else "$count exercises", count,
                    )
                    // Shown as Today, so not listed again below.
                    plans.removeAll { it.id == todayId }
                }
            }

            val healthBody = journal.health(key, today)?.body as? WatchMessageBody.HealthSnapshot
                ?: return Ready(Glance(null, null, emptyList(), tiles(null, locale), REFRESH_CAPTION, todayRow, plans))
            val raw = healthBody.raw

            var readiness: ReadinessLine? = null
            var reason: String? = null
            val factors = mutableListOf<Glance.Factor>()
            val r = HealthJson.obj(raw["readiness"])
            val score = HealthJson.int(r?.get("score"))
            val band = HealthJson.string(r?.get("band"))
            val headline = HealthJson.string(r?.get("headline"))
            if (r != null && score != null && band != null && headline != null) {
                readiness = ReadinessLine(score, band, headline)
                reason = HealthJson.string(r["reason"])
                for (f in HealthJson.objects(r["factors"])) {
                    val input = HealthJson.string(f["input"])
                    val status = HealthJson.string(f["status"])
                    val tone = Tone.fromWire(HealthJson.string(f["tone"]))
                    if (input != null && status != null && tone != null) factors += Glance.Factor(input, status, tone)
                }
            }

            var caption = REFRESH_CAPTION
            val asOf = HealthJson.string(raw["as_of_utc"])?.let(WatchTimestamp::instant)
            if (asOf != null) {
                val format = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).withZone(zone)
                caption = "as of " + format.format(asOf)
            }
            return Ready(Glance(readiness, reason, factors, tiles(raw, locale), caption, todayRow, plans))
        }

        /** "7h 12m", or "45m" under an hour. */
        fun sleepText(minutes: Int): String = if (minutes >= 60) "${minutes / 60}h ${minutes % 60}m" else "${minutes}m"

        /** "−2 vs usual" (U+2212 minus) or "+2 vs usual", and whether it is better. */
        private fun versusUsual(value: Int?, usual: Int?, betterWhenHigher: Boolean): Pair<String?, Tone> {
            if (value == null || usual == null) return null to Tone.NEUTRAL
            val diff = value - usual
            if (diff == 0) return "same as usual" to Tone.NEUTRAL
            val text = (if (diff < 0) "−" else "+") + "${kotlin.math.abs(diff)} vs usual"
            return text to if (if (betterWhenHigher) diff > 0 else diff < 0) Tone.GOOD else Tone.NEUTRAL
        }

        internal fun count(value: Int, locale: Locale): String = NumberFormat.getIntegerInstance(locale).format(value)

        private fun tiles(raw: JsonObject?, locale: Locale): List<GlanceTile> {
            val sleep = HealthJson.obj(raw?.get("sleep"))
            val sleepMinutes = HealthJson.int(sleep?.get("asleep_minutes"))
            // The score is the phone's; the watch never computes one.
            val sleepStatus = HealthJson.int(sleep?.get("score"))?.let { "Score $it" }
            val rhr = HealthJson.int(raw?.get("resting_hr_bpm"))
            val hrv = HealthJson.int(raw?.get("hrv_ms"))
            val steps = HealthJson.int(raw?.get("steps"))
            val rhrLine = versusUsual(rhr, HealthJson.int(raw?.get("resting_hr_usual_bpm")), betterWhenHigher = false)
            val hrvLine = versusUsual(hrv, HealthJson.int(raw?.get("hrv_usual_ms")), betterWhenHigher = true)
            return listOf(
                GlanceTile("Sleep", sleepMinutes?.let(::sleepText) ?: MISSING, null, sleepStatus, Tone.NEUTRAL, Metric.SLEEP),
                GlanceTile(
                    "Resting HR", rhr?.toString() ?: MISSING, if (rhr == null) null else "bpm",
                    rhrLine.first, rhrLine.second, Metric.RESTING_HR,
                ),
                GlanceTile(
                    "HRV", hrv?.toString() ?: MISSING, if (hrv == null) null else "ms",
                    hrvLine.first, hrvLine.second, Metric.HRV,
                ),
                GlanceTile(
                    "Steps", steps?.let { count(it, locale) } ?: MISSING, null,
                    if (steps == null) null else "today", Tone.NEUTRAL, Metric.STEPS,
                ),
            )
        }
    }
}

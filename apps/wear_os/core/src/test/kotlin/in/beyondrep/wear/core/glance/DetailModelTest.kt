package `in`.beyondrep.wear.core.glance

import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.store.JournalFiles
import `in`.beyondrep.wear.core.store.WatchJournal
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/* Port of DetailModelTests.swift without the "values the watch read itself" tests (Wear stage 5). */
class DetailModelTest {
    private lateinit var files: JournalFiles
    private lateinit var journal: WatchJournal
    private val m = TestMessages
    private val kolkata = ZoneId.of("Asia/Kolkata")
    private val now = "2026-10-23T05:00:00Z" // 10:30 on 2026-10-23 in Asia/Kolkata

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        journal = WatchJournal(files.db())
        journal.saveBinding(m.binding())
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun detail(metric: Metric, at: String = now): DetailModel? =
        DetailModel.make(metric, journal, Instant.parse(at), kolkata, Locale.US)

    private fun json(text: String): JsonElement = Json.parseToJsonElement(text)

    @Test
    fun detailWeekHasSevenDaysEndingTodayWithGaps() {
        val week = json(
            """[{"local_date":"2026-10-19","hrv_ms":40},{"local_date":"2026-10-20","hrv_ms":44},
            {"local_date":"2026-10-21","steps":5000},{"local_date":"2026-10-22","hrv_ms":50},
            {"local_date":"2026-10-23","hrv_ms":62}]""")
        journal.saveHealth(m.health(extra = mapOf("week" to week, "hrv_usual_ms" to JsonPrimitive(56))))
        val model = assertNotNull(detail(Metric.HRV))
        assertEquals(7, model.week.size)
        assertEquals(
            listOf("2026-10-17", "2026-10-18", "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"),
            model.week.map { it.date.toString() })
        assertEquals(listOf(null, null, 40, 44, null, 50, 62), model.week.map { it.value })
        assertEquals(listOf(false, false, false, false, false, false, true), model.week.map { it.isToday })
        assertEquals(listOf("S", "S", "M", "T", "W", "T", "F"), model.week.map { it.label })
        assertEquals("HRV", model.title)
        assertEquals("62", model.value)
        assertEquals("ms", model.unit)
        assertEquals(56, model.usual)
        assertEquals(49, model.weekAverage) // (40 + 44 + 50 + 62) / 4: the gap is not a zero
        assertNull(model.stages)
    }

    @Test
    fun todayComesFromTheSnapshotWhenThePhoneSentNoWeek() {
        journal.saveHealth(m.health())
        val model = assertNotNull(detail(Metric.STEPS))
        assertEquals(7, model.week.size)
        assertEquals(listOf(null, null, null, null, null, null, 1200), model.week.map { it.value })
        assertEquals("1,200", model.value)
        assertEquals("Steps", model.title)
        assertEquals(1200, model.weekAverage)
        assertNull(model.usual)
    }

    @Test
    fun missingValueIsDashNeverZero() {
        journal.saveHealth(
            WatchMessage(
                m.id(), "2026-10-23T01:45:00Z", m.keyA,
                WatchMessageBody.HealthSnapshot(
                    "2026-10-23",
                    JsonObject(mapOf("local_date" to JsonPrimitive("2026-10-23"), "as_of_utc" to JsonPrimitive("2026-10-23T01:40:00Z"))),
                ),
            ))
        for (metric in Metric.entries) {
            val model = assertNotNull(detail(metric), "$metric")
            assertEquals("—", model.value, "$metric")
            assertEquals(List(7) { null }, model.week.map { it.value }, "$metric")
            assertNull(model.weekAverage, "$metric")
        }
    }

    @Test
    fun stagesOnlyWhenAllFourPresent() {
        val full = json(
            """{"score":81,"asleep_minutes":432,"deep_minutes":80,"core_minutes":220,"rem_minutes":95,"awake_minutes":18}""")
        journal.saveHealth(m.health(extra = mapOf("sleep" to full)))
        val withStages = assertNotNull(detail(Metric.SLEEP))
        assertEquals(SleepStages(80, 220, 95, 18), withStages.stages)
        assertEquals("7h 12m", withStages.value)
        assertEquals("Score 81", withStages.caption)

        val partial = json("""{"asleep_minutes":432,"deep_minutes":80,"rem_minutes":95}""")
        journal.saveHealth(m.health(extra = mapOf("sleep" to partial)))
        val without = assertNotNull(detail(Metric.SLEEP))
        assertNull(without.stages)
        assertNull(without.caption)
    }

    @Test
    fun sleepWeekIsMinutesAndAverageIsInMinutes() {
        val week = json(
            """[{"local_date":"2026-10-22","asleep_minutes":400},{"local_date":"2026-10-23","asleep_minutes":432}]""")
        journal.saveHealth(m.health(extra = mapOf("week" to week)))
        val model = assertNotNull(detail(Metric.SLEEP))
        assertEquals(listOf(400, 432), model.week.takeLast(2).map { it.value })
        assertEquals(416, model.weekAverage)
    }

    @Test
    fun usualCaptionForRestingHeartRate() {
        journal.saveHealth(m.health(extra = mapOf("resting_hr_usual_bpm" to JsonPrimitive(56))))
        val model = assertNotNull(detail(Metric.RESTING_HR))
        assertEquals("Usual 56 bpm", model.caption)
        assertEquals("54", model.value)
    }

    @Test
    fun yesterdaysSnapshotGivesNoDetail() {
        val week = json("""[{"local_date":"2026-10-22","hrv_ms":50}]""")
        journal.saveHealth(m.health(localDate = "2026-10-22", asOf = "2026-10-22T18:20:00Z", extra = mapOf("week" to week)))
        // 00:05 on 2026-10-23 local.
        assertNull(detail(Metric.HRV, "2026-10-22T18:35:00Z"))
        assertNull(detail(Metric.STEPS, "2026-10-22T18:35:00Z"))
    }

    @Test
    fun noDetailWithoutABindingOrHealth() {
        assertNull(detail(Metric.HRV))
        journal.clearAccount(m.keyA, wipeUnsent = false)
        journal.saveHealth(m.health())
        assertNull(detail(Metric.HRV))
    }
}

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
import kotlin.test.assertNull
import kotlin.test.assertTrue

/*
 * Port of GlanceStateTests.swift. Not ported: the "values the watch read itself" tests (the watch
 * reads no health in Wear stage 2; stage 5 adds them).
 */
class GlanceStateTest {
    private lateinit var files: JournalFiles
    private lateinit var journal: WatchJournal
    private val m = TestMessages
    private val kolkata = ZoneId.of("Asia/Kolkata")
    private val locale = Locale.US

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        journal = WatchJournal(files.db())
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun make(now: String): GlanceState = GlanceState.make(journal, Instant.parse(now), kolkata, locale)

    private fun ready(state: GlanceState): Glance = (state as GlanceState.Ready).glance

    private fun rawHealth(vararg pairs: Pair<String, JsonElement>) =
        WatchMessage(
            m.id(), "2026-10-23T01:45:00Z", m.keyA,
            WatchMessageBody.HealthSnapshot("2026-10-23", JsonObject(mapOf(*pairs))),
        )

    private fun num(n: Int) = JsonPrimitive(n)

    @Test
    fun glanceNotPairedWithoutBinding() {
        assertEquals(GlanceState.NotPaired, make("2026-10-23T05:00:00Z"))
    }

    @Test
    fun glanceShowsReadinessAndTilesForToday() {
        journal.saveBinding(m.binding())
        journal.saveHealth(m.health())
        journal.savePlans(m.plans(names = listOf("Push", "Pull"), today = Triple("plan-1", "Pull day", "2026-10-23")))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertEquals(ReadinessLine(72, "good", "Ready to train"), g.readiness)
        assertEquals(listOf("Sleep", "Resting HR", "HRV", "Steps"), g.tiles.map { it.label })
        assertEquals(GlanceTile("Sleep", "7h 12m", null, "Score 81", Tone.NEUTRAL, Metric.SLEEP), g.tiles[0])
        assertEquals(GlanceTile("Resting HR", "54", "bpm", null, Tone.NEUTRAL, Metric.RESTING_HR), g.tiles[1])
        assertEquals(GlanceTile("HRV", "62", "ms", null, Tone.NEUTRAL, Metric.HRV), g.tiles[2])
        assertEquals(GlanceTile("Steps", "1,200", null, "today", Tone.NEUTRAL, Metric.STEPS), g.tiles[3])
        assertEquals("Synthetic reason.", g.readinessReason)
        assertTrue(g.caption.startsWith("as of "), g.caption)
        assertTrue(g.caption.contains("7:10"), g.caption)
        assertEquals(listOf("Push"), g.plans.map { it.name }, "today's plan is not listed twice")
        assertEquals(PlanRow("plan-1", "Pull day"), g.today)
    }

    @Test
    fun glanceAfterMidnightShowsTheRefreshCaptionAndDashes() {
        journal.saveBinding(m.binding())
        journal.saveHealth(m.health(localDate = "2026-10-22", asOf = "2026-10-22T18:20:00Z"))
        val g = ready(make("2026-10-22T18:35:00Z"))
        assertEquals("Open BeyondRep on your phone to refresh", g.caption)
        assertNull(g.readiness)
        assertEquals(listOf("—", "—", "—", "—"), g.tiles.map { it.value })
    }

    @Test
    fun glanceBeforeAnyHealthArrivesShowsTheRefreshCaption() {
        journal.saveBinding(m.binding())
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertEquals("Open BeyondRep on your phone to refresh", g.caption)
        assertEquals(listOf("—", "—", "—", "—"), g.tiles.map { it.value })
    }

    @Test
    fun missingStepsShowsADashNotZero() {
        journal.saveBinding(m.binding())
        journal.saveHealth(
            rawHealth("local_date" to JsonPrimitive("2026-10-23"), "as_of_utc" to JsonPrimitive("2026-10-23T01:40:00Z"),
                "resting_hr_bpm" to num(54)))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertNull(g.readiness)
        assertEquals(GlanceTile("Sleep", "—", null, null, Tone.NEUTRAL, Metric.SLEEP), g.tiles[0])
        assertEquals("54", g.tiles[1].value)
        assertEquals(GlanceTile("HRV", "—", null, null, Tone.NEUTRAL, Metric.HRV), g.tiles[2])
        assertEquals(GlanceTile("Steps", "—", null, null, Tone.NEUTRAL, Metric.STEPS), g.tiles[3])
    }

    @Test
    fun sleepUnderAnHourAndZeroStepsAreShownAsReported() {
        journal.saveBinding(m.binding())
        journal.saveHealth(
            m.health(extra = mapOf("sleep" to Json.parseToJsonElement("""{"asleep_minutes":45}"""), "steps" to num(0))))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertEquals("45m", g.tiles[0].value)
        assertNull(g.tiles[0].status, "no score, no status")
        assertEquals("0", g.tiles[3].value) // a reported zero is real; only missing is a dash
    }

    @Test
    fun todaysProgramIsHiddenWhenItsDateIsNotToday() {
        journal.saveBinding(m.binding())
        journal.savePlans(m.plans(today = Triple("plan-0", "Old day", "2026-10-22")))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertNull(g.today)
        assertEquals(1, g.plans.size)
    }

    @Test
    fun anotherAccountsHealthIsNeverShown() {
        journal.saveBinding(m.binding(m.keyB))
        journal.saveHealth(m.health(m.keyA))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertNull(g.readiness)
        assertEquals(listOf("—", "—", "—", "—"), g.tiles.map { it.value })
    }

    @Test
    fun healthRowsFromAnotherDayAreDeletedEvenWithoutABinding() {
        journal.saveHealth(m.health(localDate = "2026-10-22", asOf = "2026-10-22T18:20:00Z"))
        assertEquals(GlanceState.NotPaired, make("2026-10-23T05:00:00Z"))
        assertNull(journal.health(m.keyA, "2026-10-22"))
    }

    @Test
    fun captionParsesTheTimestampFormatDartSends() {
        journal.saveBinding(m.binding())
        journal.saveHealth(m.health(asOf = "2026-10-23T01:40:00.123Z"))
        assertTrue(ready(make("2026-10-23T05:00:00Z")).caption.contains("7:10"))
    }

    private fun tiles(extra: Map<String, JsonElement>): List<GlanceTile> {
        journal.saveBinding(m.binding())
        journal.saveHealth(m.health(extra = extra))
        return ready(make("2026-10-23T05:00:00Z")).tiles
    }

    @Test
    fun tileStatusLinesFromUsual() {
        val better = tiles(mapOf("resting_hr_usual_bpm" to num(56), "hrv_usual_ms" to num(56)))
        assertEquals("−" + "2 vs usual", better[1].status)
        assertEquals(Tone.GOOD, better[1].tone)
        assertEquals("+6 vs usual", better[2].status)
        assertEquals(Tone.GOOD, better[2].tone)
        assertEquals("Score 81", better[0].status)
        assertEquals(Tone.NEUTRAL, better[0].tone) // sleep is never coloured as good or bad
        assertEquals("today", better[3].status)
    }

    @Test
    fun worseThanUsualIsNeutralNotAnAlarm() {
        val worse = tiles(mapOf("resting_hr_usual_bpm" to num(50), "hrv_usual_ms" to num(70)))
        assertEquals("+4 vs usual", worse[1].status)
        assertEquals(Tone.NEUTRAL, worse[1].tone)
        assertEquals("−" + "8 vs usual", worse[2].status)
        assertEquals(Tone.NEUTRAL, worse[2].tone)
    }

    @Test
    fun sameAsUsualAndMissingUsual() {
        val same = tiles(mapOf("resting_hr_usual_bpm" to num(54)))
        assertEquals("same as usual", same[1].status)
    }

    @Test
    fun missingUsualGivesNoStatus() {
        val t = tiles(emptyMap())
        assertNull(t[1].status)
        assertNull(t[2].status)
        assertEquals(Tone.NEUTRAL, t[1].tone)
    }

    @Test
    fun missingValueIsDashNeverZero() {
        journal.saveBinding(m.binding())
        journal.saveHealth(
            rawHealth("local_date" to JsonPrimitive("2026-10-23"), "as_of_utc" to JsonPrimitive("2026-10-23T01:40:00Z"),
                "resting_hr_usual_bpm" to num(56), "hrv_usual_ms" to num(56)))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertEquals(listOf("—", "—", "—", "—"), g.tiles.map { it.value })
        assertEquals(listOf(null, null, null, null), g.tiles.map { it.status }, "a usual without a value gives no status")
        assertEquals(listOf(null, null, null, null), g.tiles.map { it.unit })
    }

    @Test
    fun factorsInPhoneOrder() {
        journal.saveBinding(m.binding())
        val readiness = Json.parseToJsonElement(
            """{"score":72,"band":"good","headline":"Ready to train","reason":"Synthetic reason.","factors":[
            {"input":"resting_hr","status":"Below usual","tone":"good"},
            {"input":"sleep","status":"Slept 7h 12m","tone":"good"},
            {"input":"training_load","status":"Above usual","tone":"caution"}]}""")
        journal.saveHealth(m.health(extra = mapOf("readiness" to readiness)))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertEquals(
            listOf(
                Glance.Factor("resting_hr", "Below usual", Tone.GOOD),
                Glance.Factor("sleep", "Slept 7h 12m", Tone.GOOD),
                Glance.Factor("training_load", "Above usual", Tone.CAUTION),
            ),
            g.factors,
        )
        assertEquals("Synthetic reason.", g.readinessReason)
    }

    @Test
    fun noFactorsWithoutThemInTheSnapshot() {
        journal.saveBinding(m.binding())
        journal.saveHealth(m.health())
        assertEquals(emptyList(), ready(make("2026-10-23T05:00:00Z")).factors)
    }

    @Test
    fun planRowsCarryExerciseCountAndTodaySubtitle() {
        journal.saveBinding(m.binding())
        journal.savePlans(
            m.plans(names = listOf("Push", "Pull"), today = Triple("plan-1", "Pull day", "2026-10-23"), exerciseCount = 6))
        val g = ready(make("2026-10-23T05:00:00Z"))
        assertEquals(PlanRow("plan-1", "Pull day", "6 exercises", 6), g.today)
        assertEquals(listOf(PlanRow("plan-0", "Push", null, 6)), g.plans)
    }

    @Test
    fun todaySubtitleIsSingularForOneExerciseAndAbsentForNone() {
        journal.saveBinding(m.binding())
        journal.savePlans(m.plans(names = listOf("Push"), today = Triple("plan-0", "Push day", "2026-10-23"), exerciseCount = 1))
        assertEquals("1 exercise", ready(make("2026-10-23T05:00:00Z")).today?.subtitle)
        journal.savePlans(m.plans(names = listOf("Push"), today = Triple("plan-0", "Push day", "2026-10-23"), exerciseCount = 0))
        assertNull(ready(make("2026-10-23T05:00:00Z")).today?.subtitle)
    }
}

package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.HeartRatePoint
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class WorkoutHealthBuilderTest {
    private val start = Instant.parse("2026-10-23T11:00:00Z")
    private val end = Instant.parse("2026-10-23T11:40:00Z")
    private val workout = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    private fun build(
        series: List<Pair<Instant, Int>> = emptyList(),
        kcal: Double? = null,
        from: Instant = start,
        to: Instant = end,
    ): WatchMessage? = WorkoutHealthBuilder.message(
        workout, from, to, series, kcal, TestMessages.keyA, "77777777-3333-4333-8333-000000000050", "2026-10-23T11:41:00Z")

    private fun body(message: WatchMessage?) = assertIs<WatchMessageBody.WorkoutHealth>(assertNotNull(message).body)

    @Test
    fun buildsTheSeriesAndTheCalories() {
        val message = build(listOf(start to 71, start.plusSeconds(120) to 80), 987.0)
        val b = body(message)
        assertEquals(workout, b.workoutId)
        assertEquals("2026-10-23T11:00:00Z", b.startUtc)
        assertEquals("2026-10-23T11:40:00Z", b.endUtc)
        assertEquals(listOf(HeartRatePoint("2026-10-23T11:00:00Z", 71), HeartRatePoint("2026-10-23T11:02:00Z", 80)), b.heartRate)
        assertEquals(987.0, b.totalKcal)
        // What the watch sends is what the phone's decoder accepts.
        assertEquals(b, body(WatchMessage.decode(message!!.encode())))
    }

    @Test
    fun noHeartRateAndNoCaloriesStillBuildsTheSession() {
        // The session itself must reach Health Connect even without a reading.
        for (message in listOf(build(), build(kcal = 0.0))) {
            val b = body(message)
            assertEquals(emptyList(), b.heartRate)
            assertNull(b.totalKcal)
        }
    }

    @Test
    fun caloriesAloneAreEnough() {
        val b = body(build(kcal = 300.0))
        assertEquals(emptyList(), b.heartRate)
        assertEquals(300.0, b.totalKcal)
    }

    @Test
    fun heartRateAloneLeavesTheCaloriesOut() {
        assertNull(body(build(listOf(start to 90))).totalKcal)
    }

    @Test
    fun caloriesAboveTheCeilingAreLeftOut() {
        assertNull(body(build(listOf(start to 90), 10_001.0)).totalKcal)
        assertNull(body(build(kcal = 10_001.0)).totalKcal)
    }

    @Test
    fun anEmptyOrBackwardsWorkoutBuildsNothing() {
        assertNull(build(listOf(start to 90), 100.0, from = end, to = start))
        assertNull(build(listOf(start to 90), 100.0, from = start, to = start))
    }

    @Test
    fun minutesAfterTheEndAreDropped() {
        val b = body(build(listOf(start to 70, end.plusSeconds(60) to 90)))
        assertEquals(listOf(70), b.heartRate.map { it.bpm })
    }

    @Test
    fun atMostSixHundredMinutesAreKept() {
        val series = (0 until 700).map { start.plusSeconds(it * 60L) to 80 }
        val b = body(build(series, to = start.plusSeconds(700 * 60L)))
        assertEquals(600, b.heartRate.size)
    }
}

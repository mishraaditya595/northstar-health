package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.session.TemplateFixtures.counterIds
import `in`.beyondrep.wear.core.store.JournalFiles
import `in`.beyondrep.wear.core.store.WatchJournal
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.time.Duration
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class WorkoutSummaryTest {
    private val key = "0123456789abcdef".repeat(4)
    private val base = Instant.ofEpochSecond(1_792_000_000)
    private lateinit var files: JournalFiles
    private lateinit var controller: WorkoutController

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        val journal = WatchJournal(files.db(), makeId = counterIds(5000))
        controller = WorkoutController.start(
            TemplateFixtures.template(), journal, key, "kg", "watch-installation-a", { base }, "Asia/Kolkata", counterIds(1000))
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun logCurrent() {
        val current = assertNotNull(controller.cursor.current)
        controller.log(controller.cursor.prefill(current, "kg"))
    }

    @Test
    fun countsCompletedWorkingSets() {
        logCurrent() // the warm-up, not counted
        logCurrent()
        logCurrent()
        val summary = WorkoutSummary.of(controller, base.plusSeconds(600), 71, 120)
        assertEquals(controller.state.completedSets, summary.sets)
        assertEquals(2, summary.sets)
        assertEquals(Duration.ofSeconds(600), summary.elapsed)
        assertEquals(controller.sessionId, summary.sessionId)
        assertEquals(controller.template.name, summary.name)
        assertEquals(71, summary.averageHeartRate)
        assertEquals(120, summary.totalCalories)
    }

    @Test
    fun keepsMissingHealthNull() {
        val summary = WorkoutSummary.of(controller, base.plusSeconds(60), null, null)
        assertNull(summary.averageHeartRate)
        assertNull(summary.totalCalories)
    }
}

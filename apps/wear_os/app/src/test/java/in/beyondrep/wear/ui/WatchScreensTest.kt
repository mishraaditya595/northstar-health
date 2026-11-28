package `in`.beyondrep.wear.ui

import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.Density
import androidx.test.core.app.ApplicationProvider
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Screens of the watch app on the JVM (Robolectric and Compose UI tests). The journal is real
 * (Android SQLite under Robolectric); the Data Layer is not involved.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WatchScreensTest {
    @get:Rule
    val compose = createComposeRule()

    private val keyA = "0123456789abcdef".repeat(4)
    private val now = Instant.parse("2026-10-23T05:00:00Z") // 10:30 on 2026-10-23 in Asia/Kolkata
    private val kolkata = ZoneId.of("Asia/Kolkata")
    private lateinit var graph: WatchGraph
    private lateinit var viewModel: WatchViewModel

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        graph = WatchGraph(context, "screens-${UUID.randomUUID()}.db")
        viewModel = WatchViewModel(graph, { now }, { kolkata }, { Locale.US })
    }

    // --- Journal helpers (the journal has one owner thread) -----------------------------------

    private fun onJournal(block: () -> Unit) {
        runBlocking { withContext(graph.dispatcher) { block() } }
        graph.bump()
    }

    private fun repoRoot(): Path {
        var dir: Path? = Paths.get(System.getProperty("user.dir")).toAbsolutePath()
        while (dir != null) {
            if (Files.isDirectory(dir.resolve("contracts"))) return dir
            dir = dir.parent
        }
        error("contracts directory not found")
    }

    private fun fixture(name: String): WatchMessage =
        WatchMessage.decode(String(Files.readAllBytes(repoRoot().resolve("contracts/watch_link/v1/fixtures/valid/$name")), Charsets.UTF_8))

    private fun bind() = onJournal {
        graph.journal.saveBinding(WatchMessage(UUID.randomUUID().toString(), "2026-10-23T01:00:00Z", keyA, WatchMessageBody.AccountBinding("kg")))
    }

    private fun saveFullHealth() = onJournal { graph.journal.saveHealth(fixture("health_snapshot_full.json")) }

    private fun exercise(n: Int): JsonElement = Json.parseToJsonElement(
        """{"exercise_id":"ex-$n","name":"Move $n","kind":"reps","sets":[{"position":0,"kind":"working","target_reps":8}]}""")

    private fun savePlans(names: List<String>, today: String?) = onJournal {
        val plans = names.mapIndexed { i, name ->
            JsonObject(
                mapOf(
                    "plan_id" to JsonPrimitive("plan-$i"), "name" to JsonPrimitive(name),
                    "exercises" to JsonArray(listOf(exercise(0), exercise(1))),
                ))
        }
        val raw = linkedMapOf<String, JsonElement>(
            "generated_at_utc" to JsonPrimitive("2026-10-23T01:00:00Z"),
            "plans" to JsonArray(plans),
            "recent_exercises" to JsonArray(emptyList()),
        )
        if (today != null) {
            raw["today"] = JsonObject(
                mapOf(
                    "plan_id" to JsonPrimitive("plan-0"), "program_id" to JsonPrimitive("program-1"),
                    "local_date" to JsonPrimitive("2026-10-23"), "label" to JsonPrimitive(today),
                ))
        }
        graph.journal.savePlans(
            WatchMessage(UUID.randomUUID().toString(), "2026-10-23T01:00:00Z", keyA, WatchMessageBody.PlansSnapshot(JsonObject(raw))))
    }

    private fun showRoot(initialPage: Int = 0, fontScale: Float = 1f) {
        compose.setContent {
            val ui by viewModel.ui.collectAsState()
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                RootContent(ui, initialPage)
            }
        }
    }

    private fun waitForText(text: String) =
        compose.waitUntil(5_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }

    // --- Home ---------------------------------------------------------------------------------

    @Test
    fun homeShowsReadinessAndFourTiles() {
        bind(); saveFullHealth()
        showRoot()
        waitForText("Ready to train")
        compose.onNodeWithText("72").assertIsDisplayed()
        for (label in listOf("Sleep", "Resting HR", "HRV", "Steps")) compose.onNodeWithText(label).assertIsDisplayed()
        compose.onNodeWithText("−" + "2 vs usual").assertIsDisplayed()
        compose.onNodeWithText("+4 vs usual").assertIsDisplayed()
        compose.onNodeWithText("7h 30m").assertIsDisplayed()
    }

    @Test
    fun missingValueShowsDashNeverZero() {
        bind()
        onJournal {
            graph.journal.saveHealth(
                WatchMessage(
                    UUID.randomUUID().toString(), "2026-10-23T01:45:00Z", keyA,
                    WatchMessageBody.HealthSnapshot(
                        "2026-10-23",
                        JsonObject(
                            mapOf(
                                "local_date" to JsonPrimitive("2026-10-23"),
                                "as_of_utc" to JsonPrimitive("2026-10-23T01:40:00Z"),
                                "resting_hr_bpm" to JsonPrimitive(54),
                            )),
                    ),
                ))
        }
        showRoot()
        waitForText("54")
        compose.onAllNodesWithText("—").assertCountEquals(3)
        compose.onAllNodesWithText("0").assertCountEquals(0)
    }

    @Test
    fun homeSwitchesWhenBindingArrives() {
        showRoot()
        waitForText("Open BeyondRep on your phone to sign in.")
        saveFullHealth() // not bound yet: still the onboarding screen
        compose.waitForIdle()
        compose.onNodeWithText("Open BeyondRep on your phone to sign in.").assertIsDisplayed()
        bind()
        waitForText("Ready to train")
        compose.onAllNodesWithText("Open BeyondRep on your phone to sign in.").assertCountEquals(0)
    }

    @Test
    fun descriptionsExistForTheRingAndTheTiles() {
        bind(); saveFullHealth()
        showRoot()
        waitForText("Ready to train")
        compose.onNodeWithContentDescription("Energy 72 of 100, Ready to train", substring = true).assertExists()
        compose.onNodeWithContentDescription("Resting heart rate 54 beats per minute, 2 below your usual").assertExists()
        compose.onNodeWithContentDescription("Heart rate variability 62 milliseconds, 4 above your usual").assertExists()
        compose.onNodeWithContentDescription("Sleep 7h 30m, Score 81").assertExists()
        compose.onNodeWithContentDescription("Steps 1,200, today").assertExists()
    }

    @Test
    fun detailScreensOpenFromTheTiles() {
        bind(); saveFullHealth()
        showRoot()
        waitForText("Ready to train")
        compose.onNodeWithContentDescription("Resting heart rate", substring = true).performClick()
        waitForText("Last 7 days")
        compose.onNodeWithText("Usual 56 bpm").assertIsDisplayed()
    }

    @Test
    fun theSleepTileOpensSleepDetail() {
        bind(); saveFullHealth()
        showRoot()
        waitForText("Ready to train")
        compose.onNodeWithContentDescription("Sleep 7h 30m", substring = true).performClick()
        waitForText("Last 7 nights")
        compose.onNodeWithText("7-night average", substring = true).assertExists()
    }

    @Test
    fun theHeroOpensTheReadinessDetail() {
        bind(); saveFullHealth()
        showRoot()
        waitForText("Ready to train")
        compose.onNodeWithContentDescription("Energy 72 of 100", substring = true).performClick()
        waitForText("Slept 7h 30m")
    }

    // --- Train --------------------------------------------------------------------------------

    @Test
    fun trainListsTodaysProgramWorkoutBeforeThePlans() {
        bind(); saveFullHealth()
        savePlans(listOf("Synthetic push day", "Synthetic pull day"), today = "Week 1 day 1")
        showRoot(initialPage = 1)
        waitForText("Week 1 day 1")
        val todayTop = compose.onNodeWithText("Week 1 day 1").fetchSemanticsNode().boundsInRoot.top
        val planTop = compose.onNodeWithText("Synthetic pull day").fetchSemanticsNode().boundsInRoot.top
        assertTrue(todayTop < planTop, "today $todayTop must be above the plan $planTop")
        compose.onAllNodesWithText("2 exercises").assertCountEquals(2)
    }

    @Test
    fun tappingAPlanOpensItsPreviewWithoutAStartButton() {
        bind(); saveFullHealth()
        savePlans(listOf("Synthetic push day", "Synthetic pull day"), today = "Week 1 day 1")
        showRoot(initialPage = 1)
        waitForText("Synthetic pull day")
        compose.onNodeWithContentDescription("Synthetic pull day", substring = true).performClick()
        waitForText("Move 0")
        compose.onNodeWithText("Move 1").assertIsDisplayed()
        compose.onAllNodesWithText("1 × 8").assertCountEquals(2)
        compose.onAllNodes(hasText("Start", substring = true)).assertCountEquals(0)
    }

    @Test
    fun trainHasNoStartButtonOrQuickWorkout() {
        bind(); saveFullHealth()
        savePlans(listOf("Synthetic push day"), today = null)
        showRoot(initialPage = 1)
        waitForText("Synthetic push day")
        compose.onAllNodes(hasText("Start", substring = true)).assertCountEquals(0)
        compose.onAllNodes(hasText("Quick", substring = true)).assertCountEquals(0)
    }

    @Test
    fun withoutPlansTrainSaysSo() {
        bind(); saveFullHealth()
        showRoot(initialPage = 1)
        waitForText("No plans yet. Create one in BeyondRep on your phone.")
    }

    // --- Layout on small and large round screens ------------------------------------------

    private fun lastTileIsReachable(fontScale: Float) {
        bind(); saveFullHealth()
        showRoot(fontScale = fontScale)
        waitForText("Ready to train")
        // The innermost scrollable is Home's list (the pager is outside it); scrolling to the node
        // does not depend on swipe distances or fling timing.
        compose.onAllNodes(hasScrollToNodeAction()).onLast().performScrollToNode(hasText("Steps"))
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Steps", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Steps").assertIsDisplayed()
    }

    @Test
    @Config(sdk = [34], qualifiers = "w192dp-h192dp-round-xhdpi")
    fun smallRoundScreenWithLargeFontKeepsTheLastTileReachable() = lastTileIsReachable(1.3f)

    @Test
    @Config(sdk = [34], qualifiers = "w240dp-h240dp-round-xhdpi")
    fun largeRoundScreenWithLargeFontKeepsTheLastTileReachable() = lastTileIsReachable(1.3f)

    @Test
    fun anUnboundWatchShowsOnlyTheOnboardingScreen() {
        showRoot()
        waitForText("Open BeyondRep on your phone to sign in.")
        assertEquals(0, compose.onAllNodesWithContentDescription("Train").fetchSemanticsNodes().size)
    }
}

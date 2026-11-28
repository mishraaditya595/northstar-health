package `in`.beyondrep.wear.ui

import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performRotaryScrollInput
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.Density
import androidx.test.core.app.ApplicationProvider
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.exercise.ExerciseOwner
import `in`.beyondrep.wear.exercise.SensorReading
import `in`.beyondrep.wear.exercise.SensorStart
import `in`.beyondrep.wear.link.RecordingItems
import `in`.beyondrep.wear.testing.TEST_KEY
import `in`.beyondrep.wear.testing.bindForTest
import `in`.beyondrep.wear.testing.syntheticTemplate
import `in`.beyondrep.wear.ui.workout.StartTarget
import `in`.beyondrep.wear.ui.workout.WorkoutActions
import `in`.beyondrep.wear.ui.workout.WorkoutUi
import `in`.beyondrep.wear.workout.FakeSensors
import `in`.beyondrep.wear.workout.FakeServiceControl
import `in`.beyondrep.wear.workout.RunnerState
import `in`.beyondrep.wear.workout.WorkoutRunner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Workout screens on the JVM. The runner is real (over a real journal) with fake sensors and a
 * fake service, so what the screens show is what the journal holds.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WorkoutScreensTest {
    @get:Rule
    val compose = createComposeRule()

    private val kolkata = ZoneId.of("Asia/Kolkata")
    private lateinit var graph: WatchGraph
    private lateinit var sensors: FakeSensors
    private lateinit var runner: WorkoutRunner
    private lateinit var viewModel: WatchViewModel

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        graph = WatchGraph(context, "workout-ui-${UUID.randomUUID()}.db", RecordingItems())
        graph.journal.bindForTest()
        newRunner(FakeSensors())
    }

    private fun newRunner(fake: FakeSensors) {
        sensors = fake
        runner = WorkoutRunner(
            graph, sensors, FakeServiceControl(), Instant::now, "watch-test", { "UTC" },
            CoroutineScope(Dispatchers.Unconfined))
        viewModel = WatchViewModel(graph, Instant::now, { kolkata }, { Locale.US }, runner)
    }

    private fun exercise(n: Int): JsonElement = Json.parseToJsonElement(
        """{"exercise_id":"ex-$n","name":"Move $n","kind":"reps","sets":[{"position":0,"kind":"working","target_reps":8,"target_load_grams":40000},{"position":1,"kind":"working","target_reps":8,"target_load_grams":40000}]}""")

    private fun savePlans(names: List<String>, today: String?) = runBlocking {
        withContext(graph.dispatcher) {
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
                WatchMessage(UUID.randomUUID().toString(), "2026-10-23T01:00:00Z", TEST_KEY, WatchMessageBody.PlansSnapshot(JsonObject(raw))))
        }
        graph.bump()
    }

    private fun showRoot(
        initialPage: Int = 0,
        fontScale: Float = 1f,
        actions: WorkoutActions = viewModel,
        workoutPage: Int? = null,
    ) {
        compose.setContent {
            val ui by viewModel.ui.collectAsState()
            val state by viewModel.workout.collectAsState()
            val now by viewModel.now.collectAsState()
            val revision by viewModel.revision.collectAsState()
            val status by viewModel.summaryStatus.collectAsState()
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, fontScale)) {
                RootContent(ui, initialPage, WorkoutUi(state, now, revision, false, status, workoutPage, rpeTimeoutMs = Long.MAX_VALUE / 4), actions)
            }
        }
    }

    private fun waitForText(text: String) =
        compose.waitUntil(10_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }

    private fun startQuickWorkout() = runBlocking { runner.start(syntheticTemplate()) }

    private fun running() = assertIs<RunnerState.Running>(runner.state.value)

    // --- Train and Start ---------------------------------------------------------------------

    @Test
    fun trainShowsStartOnTodayAndPlansAndQuickWorkout() {
        savePlans(listOf("Synthetic push day"), today = "Week 1 day 1")
        showRoot(initialPage = 1)
        waitForText("Synthetic push day")
        assertTrue(compose.onAllNodes(hasText("Start")).fetchSemanticsNodes().isNotEmpty())
        compose.onAllNodes(hasScrollToNodeAction()).onLast().performScrollToNode(hasText("+ Quick workout"))
        compose.onNodeWithText("+ Quick workout").assertExists()
    }

    @Test
    fun tappingStartOnAPlanAsksToStartThatPlan() {
        savePlans(listOf("Synthetic push day"), today = null)
        val targets = mutableListOf<StartTarget>()
        showRoot(
            initialPage = 1,
            actions = object : WorkoutActions by WorkoutActions.None {
                override fun start(target: StartTarget) {
                    targets += target
                }
            })
        waitForText("Synthetic push day")
        compose.onAllNodesWithContentDescription("Start Synthetic push day").onFirst().performClick()
        assertEquals(listOf<StartTarget>(StartTarget.Plan("plan-0")), targets)
    }

    @Test
    fun startOpensTheSetPage() {
        savePlans(listOf("Synthetic push day"), today = null)
        showRoot(initialPage = 1)
        waitForText("Synthetic push day")
        compose.onAllNodesWithContentDescription("Start Synthetic push day").onFirst().performClick()
        waitForText("Log set")
        waitForText("Set 1 of 2")
        compose.onNodeWithText("Log set").assertExists()
    }

    @Test
    fun blockedStartShowsTheOtherAppMessage() {
        newRunner(FakeSensors(owner = ExerciseOwner.OTHER_APP))
        savePlans(listOf("Synthetic push day"), today = null)
        showRoot(initialPage = 1)
        waitForText("Synthetic push day")
        compose.onAllNodesWithContentDescription("Start Synthetic push day").onFirst().performClick()
        waitForText("Another workout app is recording. End it there first.")
    }

    // --- The set, the rest and the overview ----------------------------------------------------

    @Test
    fun rotaryAdjustsTheFocusedValueByTheUnitStep() {
        startQuickWorkout()
        showRoot()
        waitForText("Log set")
        // The first set targets nothing, so it starts at 0 kg; one detent is +2.5 kg.
        compose.onNodeWithText("Turn the crown", substring = true).performRotaryScrollInput {
            rotateToScrollVertically(30f)
        }
        waitForText("2.5")
    }

    @Test
    fun valueBoxesOfferIncreaseAndDecreaseToAccessibilityServices() {
        startQuickWorkout()
        showRoot()
        waitForText("Log set")
        val box = compose.onNode(hasContentDescription("Weight 0 kilograms", substring = true))
        val actions = box.fetchSemanticsNode().config[SemanticsActions.CustomActions]
        assertEquals(listOf("Increase", "Decrease"), actions.map { it.label })
        compose.runOnUiThread { actions.first { it.label == "Increase" }.action() }
        // One step is 2.5 kg, the same as one crown detent.
        waitForText("2.5")
    }

    @Test
    fun aFailedLogAsksNoRpeQuestion() {
        startQuickWorkout()
        showRoot(
            actions = object : WorkoutActions by viewModel {
                override fun log(values: SetValues, onDone: (Boolean) -> Unit) = onDone(false)
            })
        waitForText("Log set")
        compose.onNodeWithText("Log set").performClick()
        compose.waitForIdle()
        assertEquals(0, compose.onAllNodesWithText("How hard was it?").fetchSemanticsNodes().size)
    }

    @Test
    fun ambientUpdateRefreshesTheClock() {
        var time = Instant.parse("2026-10-23T01:00:00Z")
        val model = WatchViewModel(graph, { time }, { kolkata }, { Locale.US }, runner)
        assertEquals(time, model.now.value)
        time = time.plusSeconds(60)
        model.onAmbientUpdate()
        assertEquals(time, model.now.value)
    }

    @Test
    fun logSetShowsRestPageWithCountdown() {
        startQuickWorkout()
        showRoot()
        waitForText("Log set")
        compose.onNodeWithText("Log set").performClick()
        // The RPE question comes first, only after the journal stored the set.
        waitForText("How hard was it?")
        compose.onNodeWithText("Skip").performClick()
        compose.waitUntil(10_000) {
            compose.onAllNodesWithContentDescription("Rest,", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("+30 s").assertExists()
        assertEquals(1, running().controller.state.completedSets)
    }

    @Test
    fun overviewShowsDashWhenHeartRateUnavailable() {
        newRunner(FakeSensors(startResult = SensorStart(heartRate = false, calories = false)))
        startQuickWorkout()
        showRoot(workoutPage = 2)
        waitForText("Exercises")
        // The dash itself is hidden from semantics (clearAndSetSemantics), so its description is what shows.
        compose.onAllNodesWithContentDescription("Heart rate not available").assertCountEquals(1)
        assertEquals(0, compose.onAllNodesWithText("0").fetchSemanticsNodes().size)
    }

    @Test
    fun endWithNoSetsOffersOnlyDiscard() {
        startQuickWorkout()
        showRoot(workoutPage = 2)
        waitForText("Exercises")
        compose.onNodeWithText("End").performClick()
        waitForText("End workout?")
        compose.onNodeWithText("Save workout").assertIsNotEnabled()
        compose.onNodeWithText("No sets logged yet.").assertExists()
        compose.onNodeWithText("Discard").assertExists()
    }

    @Test
    fun summaryShowsHeartRateRowOnlyWhenKnown() {
        newRunner(FakeSensors(scripted = listOf(SensorReading.HeartRate(70.0, Instant.now()), SensorReading.HeartRate(72.0, Instant.now()))))
        startQuickWorkout()
        finishWithOneSet()
        showRoot()
        waitForText("Done")
        compose.onNodeWithText("71 avg").assertExists()
        assertTrue(compose.onAllNodesWithText("Heart rate").fetchSemanticsNodes().isNotEmpty())
    }

    @Test
    fun summaryHasNoHeartRateRowWithoutAMeasurement() {
        newRunner(FakeSensors(startResult = SensorStart(false, false)))
        startQuickWorkout()
        finishWithOneSet()
        showRoot()
        waitForText("Done")
        assertEquals(0, compose.onAllNodesWithText("Heart rate").fetchSemanticsNodes().size)
    }

    @Test
    fun summaryStatusSaysWaitingForPhoneWhenUnreachable() {
        startQuickWorkout()
        finishWithOneSet()
        graph.setPhoneReachable(false)
        showRoot()
        waitForText("Saved on watch · waiting for phone")
    }

    @Test
    fun largeFontScaleKeepsLogSetReachable() {
        startQuickWorkout()
        showRoot(fontScale = 1.3f)
        waitForText("Log set")
        compose.onAllNodes(hasScrollToNodeAction()).onLast().performScrollToNode(hasText("Log set"))
        compose.waitForIdle()
        compose.onNodeWithText("Log set").assertExists()
    }

    // --- Helpers -------------------------------------------------------------------------------

    private fun finishWithOneSet() = runBlocking {
        val template = running().controller.template
        val set = template.exercises[0].sets[0]
        runner.log(
            `in`.beyondrep.wear.core.contracts.SetValues(
                set.setId, template.exercises[0].exerciseId, set.position, reps = 5, loadGrams = 40_000))
        runner.finish()
    }
}

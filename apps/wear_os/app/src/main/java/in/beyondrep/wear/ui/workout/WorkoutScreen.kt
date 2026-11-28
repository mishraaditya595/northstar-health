package `in`.beyondrep.wear.ui.workout

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette
import `in`.beyondrep.wear.workout.RunnerState
import java.time.Duration

private sealed interface Overlay {
    data object None : Overlay

    data class Rpe(val setId: String) : Overlay

    data object Exercises : Overlay

    data object End : Overlay
}

/**
 * The running workout: a pager of Set, Rest and Overview, with RPE, exercises and the end
 * confirmation on top. A new rest brings up the Rest page; it ends back on the set. In ambient
 * mode only a dimmed summary is drawn, updated once a minute.
 */
@Composable
fun WorkoutScreen(
    running: RunnerState.Running,
    ui: WorkoutUi,
    unit: String,
    recent: List<RecentExercise>,
    actions: WorkoutActions,
) {
    val controller = running.controller
    // The pager lives above the overlays, so closing one returns to the page the person was on.
    val deadline = remember(ui.revision) { controller.restDeadline }
    val resting = deadline != null && deadline.isAfter(ui.now)
    val pager = rememberPagerState(initialPage = ui.initialPage ?: if (resting) 1 else 0, pageCount = { 3 })
    var seeded by remember { mutableStateOf(false) }
    LaunchedEffect(deadline, resting) {
        if (!seeded) {
            seeded = true
            return@LaunchedEffect
        }
        pager.animateScrollToPage(if (resting) 1 else 0)
    }
    var overlay by remember { mutableStateOf<Overlay>(Overlay.None) }
    var pendingRpe by remember { mutableStateOf<String?>(null) }
    BackHandler(enabled = overlay != Overlay.None) { overlay = Overlay.None }

    // Offer RPE only once the set is stored: the journal commit came first.
    val stored = pendingRpe?.let { id -> controller.state.sets.any { it.setId == id && it.status == "completed" } } ?: false
    LaunchedEffect(stored) {
        val id = pendingRpe
        if (stored && id != null) {
            overlay = Overlay.Rpe(id)
            pendingRpe = null
        }
    }

    if (ui.ambient) {
        AmbientWorkout(running, ui)
        return
    }
    when (val shown = overlay) {
        is Overlay.Rpe -> RpePicker(
            onChoose = { rpe ->
                actions.setRpe(shown.setId, rpe)
                overlay = Overlay.None
            },
            onSkip = { overlay = Overlay.None },
            timeoutMs = ui.rpeTimeoutMs,
        )
        Overlay.Exercises -> ExercisesScreen(
            controller, recent, ui.revision,
            onFocus = {
                actions.focus(it)
                overlay = Overlay.None
            },
            onAdd = {
                actions.addExercise(it.name, it.kind)
                overlay = Overlay.None
            },
        )
        Overlay.End -> EndConfirmScreen(
            canSave = remember(ui.revision) { controller.canSave },
            onSave = {
                overlay = Overlay.None
                actions.finish()
            },
            onKeepGoing = { overlay = Overlay.None },
            onDiscard = {
                overlay = Overlay.None
                actions.discard()
            },
        )
        Overlay.None -> Pages(
            running, ui, unit, actions, pager,
            onLogged = { pendingRpe = it },
            onExercises = { overlay = Overlay.Exercises },
            onEnd = { overlay = Overlay.End },
        )
    }
}

@Composable
private fun Pages(
    running: RunnerState.Running,
    ui: WorkoutUi,
    unit: String,
    actions: WorkoutActions,
    pager: PagerState,
    onLogged: (String) -> Unit,
    onExercises: () -> Unit,
    onEnd: () -> Unit,
) {
    val controller = running.controller
    HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
        when (page) {
            0 -> SetPage(
                controller, unit, running.heartRate, ui,
                onLog = { values ->
                    // The RPE question only follows a set the journal stored; a failed commit asks nothing.
                    actions.log(values) { stored -> if (stored) onLogged(values.setId) }
                },
                onAddSet = actions::addSet,
                onShowExercises = onExercises,
            )
            1 -> RestPage(controller, ui, onExtend = actions::extendRest, onSkip = actions::skipRest)
            else -> OverviewPage(
                controller, running.heartRate, ui,
                onPauseOrResume = actions::pauseOrResume, onExercises = onExercises, onEnd = onEnd,
            )
        }
    }
}

/** Dimmed and still: the clock, the set count and the rest time, redrawn once a minute. */
@Composable
private fun AmbientWorkout(running: RunnerState.Running, ui: WorkoutUi) {
    val controller = running.controller
    val cursor = remember(ui.revision) { controller.cursor }
    val deadline = remember(ui.revision) { controller.restDeadline }
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BrText(
            formatClock(Duration.between(controller.startedAt, ui.now)),
            color = Palette.secondary, size = 22, weight = FontWeight.Bold,
        )
        BrText("${cursor.completedCount} / ${cursor.plannedCount} sets", color = Palette.secondary, size = 13)
        if (deadline != null && deadline.isAfter(ui.now)) {
            val minutes = maxOf(1L, (Duration.between(ui.now, deadline).seconds + 59) / 60)
            BrText("Rest $minutes min", color = Palette.secondary, size = 13)
        }
    }
}

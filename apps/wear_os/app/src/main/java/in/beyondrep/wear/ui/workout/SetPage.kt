package `in`.beyondrep.wear.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.focusable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.session.SetInput
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.ui.BrButton
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette
import `in`.beyondrep.wear.ui.Surface
import java.time.Duration

/** The heart rate and elapsed time row at the top of the Set and Overview pages. */
@Composable
internal fun HeartRateText(heartRate: Int?, color: androidx.compose.ui.graphics.Color = Palette.heart, size: Int = 11) {
    val description = heartRate?.let { "Heart rate $it beats per minute" } ?: "Heart rate not available"
    BrText(
        heartRate?.toString() ?: "—", color = color, size = size, weight = FontWeight.SemiBold,
        modifier = Modifier.clearAndSetSemantics { contentDescription = description },
    )
}

/**
 * Weight and reps (or seconds) side by side. The bezel or crown changes the box with the accent
 * outline; a tap on the other box moves the outline; one button logs the set.
 */
@Composable
fun SetPage(
    controller: WorkoutController,
    unit: String,
    heartRate: Int?,
    ui: WorkoutUi,
    onLog: (SetValues) -> Unit,
    onAddSet: (String) -> Unit,
    onShowExercises: () -> Unit,
) {
    val position = remember(ui.revision) { controller.cursor.current }
    val setId = position?.set?.setId
    val timed = position?.exercise?.kind == "duration"
    var values by remember(setId) { mutableStateOf(position?.let { controller.cursor.prefill(it, unit) }) }
    var focus by remember(setId) {
        mutableStateOf(if (timed) SetInput.Field.SECONDS else SetInput.Field.WEIGHT)
    }
    fun adjust(field: SetInput.Field, steps: Int) {
        val current = values ?: return
        val next = SetInput.value(field, current) + steps * SetInput.step(field, unit)
        values = SetInput.applying(next, field, current)
    }
    val stepper = remember { RotaryStepper() }
    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focusRequester.requestFocus() } }

    ScalingLazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .onRotaryScrollEvent { event ->
                val steps = stepper.consume(event.verticalScrollPixels)
                if (steps != 0) adjust(focus, steps)
                true
            }
            .focusRequester(focusRequester)
            .focusable(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
        // The bezel changes the value here, so it must not also scroll the list.
        rotaryScrollableBehavior = null,
    ) {
        item {
            Row(Modifier.fillMaxWidth(0.7f), horizontalArrangement = Arrangement.SpaceBetween) {
                HeartRateText(heartRate)
                BrText(
                    formatClock(Duration.between(controller.startedAt, ui.now)),
                    color = Palette.secondary, size = 11,
                )
            }
        }
        val shown = values
        if (position == null || shown == null) {
            item {
                BrText(
                    "All planned sets done", size = 13, weight = FontWeight.SemiBold, align = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(0.85f),
                )
            }
            controller.addSetExerciseId?.let { exerciseId ->
                item { BrButton("Add set", { onAddSet(exerciseId) }, Modifier.fillMaxWidth(0.85f)) }
            }
            item { BrButton("Exercises", onShowExercises, Modifier.fillMaxWidth(0.85f)) }
            return@ScalingLazyColumn
        }
        item {
            BrText(
                position.exercise.name, size = 13, weight = FontWeight.SemiBold, align = TextAlign.Center,
                maxLines = 2, modifier = Modifier.fillMaxWidth(0.85f),
            )
        }
        item {
            BrText("Set ${position.indexInExercise + 1} of ${position.countInExercise}", color = Palette.secondary, size = 11)
        }
        item {
            Row(Modifier.fillMaxWidth(0.85f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (!timed) {
                    val weight = weightText(SetInput.value(SetInput.Field.WEIGHT, shown))
                    ValueBox(
                        weight, unit, focus == SetInput.Field.WEIGHT,
                        "Weight $weight ${if (unit == "lb") "pounds" else "kilograms"}",
                        Modifier.weight(1f), { adjust(SetInput.Field.WEIGHT, it) },
                    ) { focus = SetInput.Field.WEIGHT }
                    val reps = SetInput.value(SetInput.Field.REPS, shown).toInt()
                    ValueBox(
                        "$reps", "reps", focus == SetInput.Field.REPS, "$reps reps", Modifier.weight(1f),
                        { adjust(SetInput.Field.REPS, it) },
                    ) { focus = SetInput.Field.REPS }
                } else {
                    val seconds = SetInput.value(SetInput.Field.SECONDS, shown).toInt()
                    ValueBox(
                        "$seconds", "sec", true, "$seconds seconds", Modifier.weight(1f),
                        { adjust(SetInput.Field.SECONDS, it) },
                    ) { focus = SetInput.Field.SECONDS }
                }
            }
        }
        item {
            BrText(
                "Turn the crown · tap the other box to switch", color = Palette.secondary, size = 11,
                align = TextAlign.Center, modifier = Modifier.fillMaxWidth(0.85f),
            )
        }
        item { BrButton("Log set", { onLog(shown) }, Modifier.fillMaxWidth(0.85f), prominent = true) }
    }
}

@Composable
private fun ValueBox(
    text: String,
    caption: String,
    focused: Boolean,
    description: String,
    modifier: Modifier,
    onAdjust: (Int) -> Unit,
    onClick: () -> Unit,
) {
    // TalkBack and switch users cannot turn the crown: the box offers the same step as actions.
    val adjustable = modifier.semantics {
        customActions = listOf(
            CustomAccessibilityAction("Increase") {
                onAdjust(1)
                true
            },
            CustomAccessibilityAction("Decrease") {
                onAdjust(-1)
                true
            },
        )
    }
    Surface(
        adjustable, description = if (focused) "$description, selected" else description, onClick = onClick,
        borderColor = if (focused) Palette.performance else null,
    ) {
        androidx.compose.foundation.layout.Column(
            Modifier.fillMaxWidth().padding(vertical = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BrText(text, size = 18, weight = FontWeight.Bold, maxLines = 1)
            BrText(caption, color = Palette.secondary, size = 11)
        }
    }
}

internal fun weightText(value: Double): String =
    if (value == Math.rint(value)) value.toInt().toString() else "%.1f".format(value)

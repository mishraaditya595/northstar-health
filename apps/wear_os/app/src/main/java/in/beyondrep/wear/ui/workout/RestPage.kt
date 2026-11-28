package `in`.beyondrep.wear.ui.workout

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.ui.BrButton
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette
import java.time.Duration

/**
 * A ring that counts down to the rest deadline. The deadline comes from the journal, so it is
 * right after a relaunch; the pulse at zero is scheduled by the runner from the same deadline.
 */
@Composable
fun RestPage(controller: WorkoutController, ui: WorkoutUi, onExtend: () -> Unit, onSkip: () -> Unit) {
    val deadline = remember(ui.revision) { controller.restDeadline }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { BrText("Rest", color = Palette.secondary, size = 13, weight = FontWeight.ExtraBold) }
        if (deadline == null) {
            item { BrText("Not resting", color = Palette.secondary, size = 13) }
            return@ScalingLazyColumn
        }
        item {
            // The ring's full length is what remained when this deadline was first seen.
            val total = remember(deadline) { maxOf(1.0, Duration.between(ui.now, deadline).toMillis() / 1000.0) }
            val remaining = maxOf(0.0, Duration.between(ui.now, deadline).toMillis() / 1000.0)
            Ring(remaining, total)
        }
        item {
            Row(Modifier.fillMaxWidth(0.85f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                BrButton("+30 s", onExtend, Modifier.weight(1f))
                BrButton("Skip", onSkip, Modifier.weight(1f))
            }
        }
        controller.cursor.current?.let { next ->
            item {
                BrText(
                    "Next: ${next.exercise.name} · set ${next.indexInExercise + 1} of ${next.countInExercise}",
                    color = Palette.secondary, size = 11, align = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(0.85f),
                )
            }
        }
    }
}

@Composable
private fun Ring(remaining: Double, total: Double) {
    val seconds = Math.ceil(remaining).toInt()
    val fraction = (remaining / total).toFloat().coerceIn(0f, 1f)
    Box(
        Modifier.size(90.dp).clearAndSetSemantics { contentDescription = "Rest, $seconds seconds left" },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(90.dp)) {
            val stroke = 8.dp.toPx()
            val inset = stroke / 2
            val arc = Size(size.width - stroke, size.height - stroke)
            drawArc(
                color = Palette.surface, startAngle = 0f, sweepAngle = 360f, useCenter = false,
                topLeft = Offset(inset, inset), size = arc, style = Stroke(stroke),
            )
            drawArc(
                color = Palette.performance, startAngle = -90f, sweepAngle = 360f * fraction, useCenter = false,
                topLeft = Offset(inset, inset), size = arc, style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
        BrText("%d:%02d".format(seconds / 60, seconds % 60), size = 18, weight = FontWeight.Bold, maxLines = 1)
    }
}

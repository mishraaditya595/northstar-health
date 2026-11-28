package `in`.beyondrep.wear.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.ui.BrButton
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette

/** Jump to an exercise or add one. Adding lists the phone's recent exercises. */
@Composable
fun ExercisesScreen(
    controller: WorkoutController,
    recent: List<RecentExercise>,
    revision: Long,
    onFocus: (String) -> Unit,
    onAdd: (RecentExercise) -> Unit,
) {
    var adding by remember { mutableStateOf(false) }
    // Composable calls cannot sit inside the lazy list's item builder.
    val template = remember(revision) { controller.template }
    val state = remember(revision) { controller.state }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (adding) {
            item { BrText("Add exercise", color = Palette.secondary, size = 13, weight = FontWeight.ExtraBold) }
            if (recent.isEmpty()) {
                item {
                    BrText(
                        "No recent exercises. Add them in BeyondRep on your phone.",
                        color = Palette.secondary, size = 11, modifier = Modifier.fillMaxWidth(0.85f),
                    )
                }
            }
            for (exercise in recent) item { BrButton(exercise.name, { onAdd(exercise) }, Modifier.fillMaxWidth(0.85f)) }
        } else {
            item { BrText("Exercises", color = Palette.secondary, size = 13, weight = FontWeight.ExtraBold) }
            for (exercise in template.exercises) {
                item {
                    val ids = exercise.sets.map { it.setId }.toSet()
                    val done = state.sets.count { it.setId in ids }
                    val total = exercise.sets.size
                    Row(Modifier.fillMaxWidth(0.85f), verticalAlignment = Alignment.CenterVertically) {
                        BrButton(
                            "${exercise.name}  $done/$total", { onFocus(exercise.exerciseId) }, Modifier.weight(1f),
                            description = "${exercise.name}, $done of $total sets done",
                        )
                    }
                }
            }
            item { BrButton("+ Add exercise", { adding = true }, Modifier.fillMaxWidth(0.85f)) }
        }
    }
}

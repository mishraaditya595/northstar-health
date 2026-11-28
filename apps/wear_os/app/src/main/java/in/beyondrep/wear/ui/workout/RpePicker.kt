package `in`.beyondrep.wear.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.ui.BrButton
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette
import kotlinx.coroutines.delay

/** Asked after each logged set. It closes itself after [timeoutMs] with no choice. */
@Composable
fun RpePicker(onChoose: (Double) -> Unit, onSkip: () -> Unit, timeoutMs: Long = 5_000) {
    LaunchedEffect(Unit) {
        delay(timeoutMs)
        onSkip()
    }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { BrText("How hard was it?", size = 13, weight = FontWeight.SemiBold, align = TextAlign.Center) }
        item { BrText("RPE, optional", color = Palette.secondary, size = 11) }
        for (row in listOf(listOf(6, 7, 8), listOf(9, 10))) {
            item {
                Row(Modifier.fillMaxWidth(0.85f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (value in row) {
                        BrButton("$value", { onChoose(value.toDouble()) }, Modifier.weight(1f), description = "RPE $value")
                    }
                    if (row.size == 2) BrButton("Skip", onSkip, Modifier.weight(1f))
                }
            }
        }
    }
}

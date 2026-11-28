package `in`.beyondrep.wear.ui.workout

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.ui.BrButton
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette

/** Save, keep going or discard. Without a logged working set only discard (and keep going) work. */
@Composable
fun EndConfirmScreen(canSave: Boolean, onSave: () -> Unit, onKeepGoing: () -> Unit, onDiscard: () -> Unit) {
    var confirming by remember { mutableStateOf(false) }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (confirming) {
            item {
                BrText(
                    "Discard this workout? It is deleted from your watch.", size = 13, align = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(0.85f),
                )
            }
            item { BrButton("Discard", onDiscard, Modifier.fillMaxWidth(0.85f), destructive = true) }
            item { BrButton("Keep going", { confirming = false }, Modifier.fillMaxWidth(0.85f)) }
        } else {
            item { BrText("End workout?", size = 13, weight = FontWeight.ExtraBold) }
            item { BrButton("Save workout", onSave, Modifier.fillMaxWidth(0.85f), enabled = canSave, prominent = canSave) }
            if (!canSave) item { BrText("No sets logged yet.", color = Palette.secondary, size = 11) }
            item { BrButton("Keep going", onKeepGoing, Modifier.fillMaxWidth(0.85f)) }
            item { BrButton("Discard", { confirming = true }, Modifier.fillMaxWidth(0.85f), destructive = true) }
        }
    }
}

package `in`.beyondrep.wear.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.glance.SyncLine
import `in`.beyondrep.wear.core.glance.WaitingWorkouts

/** What "synced" means on the watch: the time it last stored data from the phone, nothing more. */
@Composable
fun SyncScreen(line: SyncLine, waiting: WaitingWorkouts) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        when (line) {
            is SyncLine.Synced -> {
                item { Heading("Synced ${line.time}", Palette.performance) }
                item { Detail("Your phone sent data.") }
            }
            is SyncLine.PhoneAway -> {
                item { Heading("Phone not nearby", Palette.caution) }
                item { Detail("Showing data from ${line.time}. It updates when your phone is nearby.") }
            }
            SyncLine.NotPaired -> {
                item { Heading("Open BeyondRep on your phone", Palette.secondary) }
                item { Detail("Sign in there to see your data here.") }
            }
        }
        for (text in waiting.lines) item { Heading(text, Palette.caution) }
    }
}

@Composable
private fun Heading(text: String, color: Color) {
    Row(Modifier.fillMaxWidth(0.85f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).background(color, CircleShape))
        BrText(text, size = 13, weight = FontWeight.SemiBold)
    }
}

@Composable
private fun Detail(text: String) {
    BrText(text, color = Palette.secondary, size = 11, modifier = Modifier.fillMaxWidth(0.85f))
}

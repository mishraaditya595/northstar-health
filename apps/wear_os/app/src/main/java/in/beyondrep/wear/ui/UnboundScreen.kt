package `in`.beyondrep.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn

/** Nothing is bound to an account yet: the phone does the sign-in. */
@Composable
fun UnboundScreen() {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { BrText("BeyondRep", color = Palette.performance, size = 13, weight = FontWeight.ExtraBold) }
        item {
            BrText(
                "Open BeyondRep on your phone to sign in.",
                color = Palette.ink, size = 13, align = TextAlign.Center, modifier = Modifier.fillMaxWidth(0.85f),
            )
        }
    }
}

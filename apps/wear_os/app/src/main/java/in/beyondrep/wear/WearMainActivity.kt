package `in`.beyondrep.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.link.PhoneReachability
import `in`.beyondrep.wear.ui.RootScreen
import `in`.beyondrep.wear.ui.WatchViewModel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId

/**
 * Home and Train glance over what the phone sent. Read-only: nothing here records a workout
 * (Wear stage 3) and no health permission is asked.
 */
class WearMainActivity : ComponentActivity() {
    private val graph by lazy { WatchGraph.get(this) }
    private val reachability by lazy { PhoneReachability(this) { graph.setPhoneReachable(it) } }

    private val viewModel: WatchViewModel by viewModels {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                WatchViewModel(graph, Instant::now, ZoneId::systemDefault) as T
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { RootScreen(viewModel) }
    }

    override fun onResume() {
        super.onResume()
        reachability.start()
        lifecycleScope.launch {
            // Items the phone left while the app was not running.
            try {
                withContext(graph.dispatcher) { graph.link.catchUp() }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (_: Exception) {
                // Not user actionable; the next resume reads again.
            }
            reachability.refresh()
        }
    }

    override fun onPause() {
        reachability.stop()
        super.onPause()
    }
}

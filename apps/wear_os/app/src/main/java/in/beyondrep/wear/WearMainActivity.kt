package `in`.beyondrep.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.wear.ambient.AmbientLifecycleObserver
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.link.PhoneReachability
import `in`.beyondrep.wear.ui.RootScreen
import `in`.beyondrep.wear.ui.WatchViewModel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId

/**
 * Home and Train over what the phone sent, and the workout screens. Starting a workout asks for
 * the sensor permissions once; a denial still records.
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

    private val ambientObserver by lazy {
        AmbientLifecycleObserver(
            this,
            object : AmbientLifecycleObserver.AmbientLifecycleCallback {
                override fun onEnterAmbient(ambientDetails: AmbientLifecycleObserver.AmbientDetails) =
                    viewModel.setAmbient(true)

                override fun onExitAmbient() = viewModel.setAmbient(false)

                override fun onUpdateAmbient() = viewModel.onAmbientUpdate()
            },
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycle.addObserver(ambientObserver)
        setContent { RootScreen(viewModel) }
        // Idempotent: the runner follows account changes once per process, not once per activity.
        graph.runner.observe()
        lifecycleScope.launch {
            // The phone coming within reach: put what is waiting for it.
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                graph.phoneReachable.collect { if (it) graph.outbox.flush() }
            }
        }
        lifecycleScope.launch {
            // Old heart rate series and a silent binding go before anything else is read.
            graph.pruneStale()
            // A workout the system interrupted comes back from the journal.
            try {
                graph.runner.restore()
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (_: Exception) {
                // Not user actionable; the next launch tries again.
            }
        }
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
            graph.outbox.flush()
        }
    }

    override fun onPause() {
        reachability.stop()
        super.onPause()
    }
}

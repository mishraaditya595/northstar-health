package `in`.beyondrep.wear.link

import android.content.Context
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

/** Tells the app whether a phone with BeyondRep (capability `beyondrep_phone_app`) is nearby. */
class PhoneReachability(
    private val context: Context,
    private val onChange: (Boolean) -> Unit,
) : CapabilityClient.OnCapabilityChangedListener {
    private companion object {
        const val PHONE_CAPABILITY = "beyondrep_phone_app"
    }

    private val client: CapabilityClient get() = Wearable.getCapabilityClient(context)

    suspend fun refresh() {
        val reachable = try {
            client.getCapability(PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE).await().nodes.isNotEmpty()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            false
        }
        onChange(reachable)
    }

    fun start() {
        try {
            client.addListener(this, PHONE_CAPABILITY)
        } catch (_: Exception) {
            // No Play services: the line just says the phone is not nearby.
        }
    }

    fun stop() {
        try {
            client.removeListener(this)
        } catch (_: Exception) {
            // Nothing was registered.
        }
    }

    override fun onCapabilityChanged(info: CapabilityInfo) {
        onChange(info.nodes.any { it.isNearby })
    }
}

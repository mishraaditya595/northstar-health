package `in`.beyondrep.app

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Mass
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneOffset

/**
 * Writes the weight a user logs to Health Connect (`beyondrep/health_weight`, ADR-0016).
 *
 * The `health` plugin logs every written value at INFO, so the weight goes through here instead:
 * one manual-entry `WeightRecord` with BeyondRep's client record id at version 1, so Undo can
 * delete it by that id through the plugin. Nothing is logged, and error replies carry a code
 * only, never a message, a value or a time.
 *
 * Method `write`: `clientRecordId`, `kg`, `atMs`, `offsetSeconds`; replies the record id.
 * Error codes: `permission_denied`, `unavailable`, `failed`.
 */
class WeightWriter(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "beyondrep/health_weight"
    }

    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun register() = channel.setMethodCallHandler(this)

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "write" -> scope.launch { write(call, result) }
            else -> result.notImplemented()
        }
    }

    private suspend fun write(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (HealthConnectClient.getSdkStatus(context) != HealthConnectClient.SDK_AVAILABLE) {
                result.error("unavailable", null, null)
                return
            }
            val record = WeightRecord(
                time = Instant.ofEpochMilli(call.argument<Number>("atMs")!!.toLong()),
                zoneOffset = ZoneOffset.ofTotalSeconds(call.argument<Number>("offsetSeconds")!!.toInt()),
                weight = Mass.kilograms(call.argument<Number>("kg")!!.toDouble()),
                metadata = Metadata.manualEntry(
                    device = null,
                    clientRecordId = call.argument<String>("clientRecordId")!!,
                    clientRecordVersion = 1L,
                ),
            )
            val id = HealthConnectClient.getOrCreate(context)
                .insertRecords(listOf(record)).recordIdsList.firstOrNull()
            if (id.isNullOrEmpty()) result.error("failed", null, null) else result.success(id)
        } catch (e: CancellationException) {
            throw e
        } catch (_: SecurityException) {
            result.error("permission_denied", null, null)
        } catch (_: Exception) {
            result.error("failed", null, null)
        }
    }
}

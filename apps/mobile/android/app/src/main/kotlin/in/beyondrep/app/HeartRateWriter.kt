package `in`.beyondrep.app

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneOffset

/**
 * The Health Connect heart rate record of a Wear OS workout (`beyondrep/health_heart_rate`).
 *
 * The `health` plugin writes one record per call and logs every bpm value at INFO, so the
 * per-minute series of a watch workout goes through here instead: ONE `HeartRateRecord` with all
 * samples, client record id `<workout uuid>:heart_rate`, so a retry at a greater client record
 * version replaces it. Nothing is logged, and error replies carry a code only, never a message,
 * a value or a time.
 *
 * Methods:
 * - `write`: `clientRecordId`, `version`, `startMs`, `endMs`, `offsetSeconds`, `samples`
 *   (list of `[atMs, bpm]`); replies the record id.
 * - `delete`: `clientRecordId`; replies true (also when no such record exists).
 * Error codes: `permission_denied`, `unavailable`, `failed`.
 */
class HeartRateWriter(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "beyondrep/health_heart_rate"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun register() = channel.setMethodCallHandler(this)

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "write" -> scope.launch { run(result) { write(call) } }
            "delete" -> scope.launch { run(result) { delete(call) } }
            else -> result.notImplemented()
        }
    }

    private suspend fun run(result: MethodChannel.Result, block: suspend () -> Any) {
        try {
            if (HealthConnectClient.getSdkStatus(context) != HealthConnectClient.SDK_AVAILABLE) {
                result.error("unavailable", null, null)
                return
            }
            result.success(block())
        } catch (_: SecurityException) {
            result.error("permission_denied", null, null)
        } catch (_: Exception) {
            result.error("failed", null, null)
        }
    }

    private suspend fun write(call: MethodCall): String {
        val clientRecordId = call.argument<String>("clientRecordId")!!
        val version = call.argument<Number>("version")!!.toLong()
        val start = Instant.ofEpochMilli(call.argument<Number>("startMs")!!.toLong())
        val end = Instant.ofEpochMilli(call.argument<Number>("endMs")!!.toLong())
        val offset = ZoneOffset.ofTotalSeconds(call.argument<Number>("offsetSeconds")!!.toInt())
        val samples = call.argument<List<List<Number>>>("samples")!!
            .map { Instant.ofEpochMilli(it[0].toLong()) to it[1].toLong() }
            // Health Connect wants every sample inside the record.
            .filter { !it.first.isBefore(start) && it.first.isBefore(end) }
            .map { HeartRateRecord.Sample(time = it.first, beatsPerMinute = it.second) }
        val record = HeartRateRecord(
            startTime = start,
            startZoneOffset = offset,
            endTime = end,
            endZoneOffset = offset,
            samples = samples,
            metadata = Metadata.activelyRecorded(
                device = Device(type = Device.TYPE_WATCH),
                clientRecordId = clientRecordId,
                clientRecordVersion = version,
            ),
        )
        val client = HealthConnectClient.getOrCreate(context)
        val id = client.insertRecords(listOf(record)).recordIdsList.firstOrNull()
        if (id.isNullOrEmpty()) throw IllegalStateException()
        return id
    }

    private suspend fun delete(call: MethodCall): Boolean {
        val clientRecordId = call.argument<String>("clientRecordId")!!
        HealthConnectClient.getOrCreate(context).deleteRecords(
            HeartRateRecord::class, emptyList(), listOf(clientRecordId))
        return true
    }
}

package dev.northstar.northstar_health

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingExport: MethodChannel.Result? = null
    private var pendingJson: String? = null
    private val exportRequest = 7411

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "northstar/workout_export",
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveJson") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *>
            val filename = args?.get("name") as? String
            val json = args?.get("json") as? String
            if (pendingExport != null || filename != "northstar-workouts.json" ||
                json == null || !json.startsWith("{") || !json.endsWith("}")) {
                result.error("export_unavailable", "Cannot start document export", null)
                return@setMethodCallHandler
            }
            pendingExport = result
            pendingJson = json
            try {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, filename)
                }
                startActivityForResult(intent, exportRequest)
            } catch (_: Exception) {
                pendingExport = null
                pendingJson = null
                result.error("picker_unavailable", "Document picker unavailable", null)
            }
        }
    }

    @Deprecated("Flutter Activity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportRequest) return
        val callback = pendingExport ?: return
        val json = pendingJson
        pendingExport = null
        pendingJson = null
        if (resultCode != Activity.RESULT_OK || data?.data == null || json == null) {
            callback.success("cancelled")
            return
        }
        try {
            contentResolver.openOutputStream(data.data!!, "w")?.use { stream ->
                stream.writer(Charsets.UTF_8).use { it.write(json) }
            } ?: throw IllegalStateException("Output stream unavailable")
            callback.success("saved")
        } catch (_: Exception) {
            // No JSON, URI, file paths or private errors go to analytics/logs.
            callback.error("write_failed", "Could not write export file", null)
        }
    }

    override fun onDestroy() {
        pendingJson = null
        pendingExport?.error("activity_closed", "Document picker closed", null)
        pendingExport = null
        super.onDestroy()
    }
}

package dev.northstar.northstar_health

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        // Activity recreation shares this lock and count while a SAF writer
        // survives rotation. A new process starts at zero and recovers the
        // last durable marker before another export can begin.
        private val exportStateLock = Any()
        private var activeWrites = 0
        private var cleanupInProgress = false
    }

    private var pendingExport: MethodChannel.Result? = null
    private var writeInProgress = false
    private var pendingJson: String? = null
    private val exportRequest = 7411
    private val exportPrefs by lazy {
        getSharedPreferences("northstar_export_recovery", MODE_PRIVATE)
    }
    private val pendingUriKey = "unfinished_document_uri"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A process may have been killed after CREATE_DOCUMENT and before a
        // finished write. Delete only the exact previously selected export
        // URI. Some providers revoke grants across process death; deletion is
        // best-effort, never an assertion that all providers can clean up.
        synchronized(exportStateLock) {
            // Another Activity may be recreated while its writer is still
            // running. Such a marker is active, not stale; don't delete it.
            if (activeWrites == 0 && !cleanupInProgress) {
                val stale = exportPrefs.getString(pendingUriKey, null)
                if (stale != null) {
                    cleanupInProgress = true
                    Thread {
                        // Marker format is unique-token|URI. Plain URI is
                        // supported for recovery from earlier app builds.
                        val uri = stale.substringAfter('|', stale)
                        try {
                            tryDeleteDocument(Uri.parse(uri))
                        } finally {
                            synchronized(exportStateLock) {
                                // Compare-and-clear: never erase the marker
                                // belonging to a newer file/export.
                                if (exportPrefs.getString(pendingUriKey, null) == stale) {
                                    exportPrefs.edit().remove(pendingUriKey).commit()
                                }
                                cleanupInProgress = false
                            }
                        }
                    }.start()
                }
            }
        }
    }

    private fun tryDeleteDocument(uri: Uri) {
        try {
            DocumentsContract.deleteDocument(contentResolver, uri)
        } catch (_: Exception) {
            // A provider may not support delete or may revoke its grant.
            // Never log a potentially identifying URI or file contents.
        }
    }

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
            val recoveryBusy = synchronized(exportStateLock) {
                activeWrites > 0 || cleanupInProgress
            }
            if (pendingExport != null || recoveryBusy ||
                filename != "northstar-workouts.json" ||
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
        val callback = pendingExport
        val json = pendingJson
        pendingJson = null
        val uri = data?.data

        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingExport = null
            callback?.success("cancelled")
            return
        }
        if (callback == null || json == null) {
            // Picker returned after Activity recreation / process death.
            // CREATE_DOCUMENT may already have created an empty file.
            pendingExport = null
            Thread { tryDeleteDocument(uri) }.start()
            callback?.error("write_unavailable", "Export no longer available", null)
            return
        }

        // Record a recoverable cleanup marker before any byte is written.
        // commit() is intentional: apply() is not durable on process death.
        val marker = "${UUID.randomUUID()}|${uri}"
        val secured = synchronized(exportStateLock) {
            if (activeWrites != 0 || cleanupInProgress ||
                !exportPrefs.edit().putString(pendingUriKey, marker).commit()) {
                false
            } else {
                activeWrites++
                writeInProgress = true
                true
            }
        }
        if (!secured) {
            pendingExport = null
            Thread { tryDeleteDocument(uri) }.start()
            callback.error("write_unavailable", "Could not secure export write", null)
            return
        }

        // SAF providers (including Drive) can block for many seconds.
        // All stream IO and best-effort deletion stay off the UI thread.
        Thread {
            var saved = false
            try {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("Output stream unavailable")
                output.use { stream ->
                    stream.writer(Charsets.UTF_8).use { it.write(json) }
                }
                saved = true
            } catch (_: Exception) {
                tryDeleteDocument(uri)
            } finally {
                // Do not leave the cleanup marker after a successful export.
                // If killed before this point, startup tries deleting the
                // potentially empty/partial file.
                synchronized(exportStateLock) {
                    // Another Activity can never own this marker. Guard its
                    // cleanup even if the Activity has been recreated.
                    if (exportPrefs.getString(pendingUriKey, null) == marker) {
                        exportPrefs.edit().remove(pendingUriKey).commit()
                    }
                    activeWrites--
                }
                runOnUiThread {
                    writeInProgress = false
                    if (pendingExport === callback) {
                        pendingExport = null
                        try {
                            // The writer, not onDestroy(), owns the result.
                            // The reply may be undeliverable if Flutter's
                            // engine was destroyed; don't invent a failure
                            // while a write might have succeeded.
                            if (saved) callback.success("saved")
                            else callback.error("write_failed", "Could not write export file", null)
                        } catch (_: IllegalStateException) {
                            // Flutter messenger was detached during teardown.
                        }
                    }
                }
            }
        }.start()
    }

    override fun onDestroy() {
        pendingJson = null
        if (!writeInProgress) {
            // A picker that hasn't returned cannot complete after teardown.
            // A write already in progress MUST keep its result until the
            // background writer finishes; do not report a false failure.
            pendingExport?.error("activity_closed", "Document picker closed", null)
            pendingExport = null
        }
        super.onDestroy()
    }
}

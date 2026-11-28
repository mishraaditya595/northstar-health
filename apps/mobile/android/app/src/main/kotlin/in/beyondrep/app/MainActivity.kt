package `in`.beyondrep.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.Settings
import java.io.File
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {
    companion object {
        // Activity recreation shares this lock and count while a SAF writer
        // survives rotation. A new process starts at zero and recovers the
        // last durable marker before another export can begin.
        private val exportStateLock = Any()
        private var activeWrites = 0
        private var cleanupInProgress = false
        // Dart streams into a temp file that must survive Activity
        // recreation; only a new process may purge leftover temp files.
        private var tempPurged = false
    }

    private var wearLink: WearLinkBridge? = null
    private var heartRateWriter: HeartRateWriter? = null
    private var weightWriter: WeightWriter? = null
    private var pendingExport: MethodChannel.Result? = null
    private var writeInProgress = false
    private var pendingFile: File? = null
    private val exportRequest = 7411
    private val exportPrefs by lazy {
        getSharedPreferences("northstar_export_recovery", MODE_PRIVATE)
    }
    private val pendingUriKey = "unfinished_document_uri"

    // App-private, excluded from Auto Backup. Dart writes here, never chooses
    // the location; each export gets its own beyondrep-export-* folder.
    private val exportTempRoot get() = noBackupFilesDir.canonicalFile

    private fun exportTempFile(path: String?): File? {
        val file = File(path ?: return null).canonicalFile
        val folder = file.parentFile ?: return null
        return file.takeIf {
            it.name == "beyondrep-workouts.json" && it.isFile &&
                folder.name.startsWith("beyondrep-export-") &&
                folder.parentFile == exportTempRoot
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        synchronized(exportStateLock) {
            if (!tempPurged) {
                tempPurged = true
                exportTempRoot.listFiles { f -> f.name.startsWith("beyondrep-export-") }
                    ?.forEach { it.deleteRecursively() }
            }
        }
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

    // Health Connect's permission settings; the app's own settings page when
    // Health Connect has no such activity. Returns false, never throws.
    private fun openHealthConnectSettings(): Boolean {
        val targets = listOf(
            Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null)),
        )
        for (intent in targets) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next target.
            } catch (_: Exception) {
                return false
            }
        }
        return false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wearLink?.dispose()
        wearLink = WearLinkBridge(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        heartRateWriter?.dispose()
        heartRateWriter = HeartRateWriter(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        weightWriter?.dispose()
        weightWriter = WeightWriter(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.register() }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "northstar/health_settings",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openHealthConnectSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(openHealthConnectSettings())
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "northstar/workout_export",
        ).setMethodCallHandler { call, result ->
            if (call.method == "prepareFile") {
                try {
                    val folder = File(exportTempRoot, "beyondrep-export-${UUID.randomUUID()}")
                    val file = File(folder, "beyondrep-workouts.json")
                    if (!folder.mkdirs() || !file.createNewFile()) throw IllegalStateException()
                    result.success(file.path)
                } catch (_: Exception) {
                    result.error("export_unavailable", "Cannot prepare export", null)
                }
                return@setMethodCallHandler
            }
            if (call.method != "saveFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val args = call.arguments as? Map<*, *>
            val filename = args?.get("name") as? String
            val file = exportTempFile(args?.get("path") as? String)
            val recoveryBusy = synchronized(exportStateLock) {
                activeWrites > 0 || cleanupInProgress
            }
            if (pendingExport != null || recoveryBusy ||
                filename != "beyondrep-workouts.json" ||
                file == null || file.length() < 2) {
                result.error("export_unavailable", "Cannot start document export", null)
                return@setMethodCallHandler
            }
            pendingExport = result
            pendingFile = file
            try {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, filename)
                }
                startActivityForResult(intent, exportRequest)
            } catch (_: Exception) {
                pendingExport = null
                pendingFile = null
                result.error("picker_unavailable", "Document picker unavailable", null)
            }
        }
    }

    @Deprecated("Flutter Activity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportRequest) return
        val callback = pendingExport
        val source = pendingFile
        pendingFile = null
        val uri = data?.data

        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingExport = null
            callback?.success("cancelled")
            return
        }
        if (callback == null || source == null) {
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
                // Stream copy keeps memory bounded regardless of history size.
                output.use { stream ->
                    source.inputStream().use { it.copyTo(stream) }
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
        wearLink?.dispose()
        wearLink = null
        heartRateWriter?.dispose()
        heartRateWriter = null
        weightWriter?.dispose()
        weightWriter = null
        pendingFile = null
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

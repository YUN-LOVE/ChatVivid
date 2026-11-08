package dev.chatvv.chatvv

import android.app.Activity
import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_FILES = 1001
        private const val REQUEST_MODEL = 1002
    }

    private var pendingFiles: MethodChannel.Result? = null
    private var pendingModel: MethodChannel.Result? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chatvv/paths")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "supportDir" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }

        audioChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "chatvv/audio",
        )
        audioChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_argument", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        mediaPlayer?.release()
                        mediaPlayer = MediaPlayer().apply {
                            setDataSource(path)
                            setOnCompletionListener {
                                audioChannel?.invokeMethod("completed", null)
                            }
                            setOnErrorListener { _, what, extra ->
                                audioChannel?.invokeMethod(
                                    "error",
                                    mapOf("what" to what, "extra" to extra),
                                )
                                true
                            }
                            prepare()
                            start()
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("play_failed", error.message, null)
                    }
                }
                "stop" -> {
                    try {
                        mediaPlayer?.stop()
                    } catch (_: Exception) {
                        // Already completed/released.
                    }
                    mediaPlayer?.release()
                    mediaPlayer = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chatvv/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTextFiles" -> {
                        if (pendingFiles != null) {
                            result.error("busy", "file picker is already open", null)
                            return@setMethodCallHandler
                        }
                        pendingFiles = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        }
                        startActivityForResult(intent, REQUEST_FILES)
                    }
                    "pickRiveFile" -> {
                        if (pendingModel != null) {
                            result.error("busy", "file picker is already open", null)
                            return@setMethodCallHandler
                        }
                        pendingModel = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, REQUEST_MODEL)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MODEL) {
            val modelResult = pendingModel ?: return
            pendingModel = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                modelResult.success(null)
                return
            }
            try {
                val uri = data.data!!
                val bytes = contentResolver.openInputStream(uri)?.use {
                    it.readBytes()
                }
                if (bytes == null || bytes.isEmpty()) {
                    modelResult.error("read_failed", "empty file", null)
                    return
                }
                modelResult.success(
                    mapOf(
                        "name" to displayName(uri),
                        "bytes" to bytes,
                    ),
                )
            } catch (error: Exception) {
                modelResult.error("read_failed", error.message, null)
            }
            return
        }
        if (requestCode != REQUEST_FILES) return
        val result = pendingFiles ?: return
        pendingFiles = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, String>>())
            return
        }

        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i)?.uri?.let(uris::add)
            }
        }
        data.data?.let(uris::add)

        val files = mutableListOf<Map<String, String>>()
        for (uri in uris) {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use {
                    it.readBytes()
                } ?: continue
                if (bytes.size > 256 * 1024) continue
                files.add(
                    mapOf(
                        "name" to displayName(uri),
                        "content" to String(bytes, StandardCharsets.UTF_8),
                    ),
                )
            } catch (_: Exception) {
                // Skip unreadable or non-UTF-8 files.
            }
        }
        result.success(files)
    }

    override fun onDestroy() {
        mediaPlayer?.release()
        mediaPlayer = null
        super.onDestroy()
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getString(0) ?: "file"
            }
        }
        return uri.lastPathSegment ?: "file"
    }
}

package dev.chatvv.chatvv

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_FILES = 1001
        private const val REQUEST_MODEL = 1002
        private const val REQUEST_MIC = 1003
    }

    private var pendingFiles: MethodChannel.Result? = null
    private var pendingModel: MethodChannel.Result? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioChannel: MethodChannel? = null
    private var micChannel: MethodChannel? = null
    private var pendingMic: MethodChannel.Result? = null
    private var recorder: PcmRecorder? = null

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
                        // Return the clip duration so Dart can arm a playback
                        // watchdog in case the completion callback is lost.
                        result.success(mediaPlayer?.duration ?: -1)
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

        micChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "chatvv/mic",
        )
        micChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val granted =
                        checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                            PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        startMicRecording(result)
                    } else if (pendingMic != null) {
                        result.error(
                            "mic_busy",
                            "permission request already running",
                            null,
                        )
                    } else {
                        pendingMic = result
                        requestPermissions(
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQUEST_MIC,
                        )
                    }
                }
                "stop" -> {
                    val current = recorder
                    recorder = null
                    if (current == null) {
                        result.success(null)
                    } else {
                        try {
                            result.success(current.stop())
                        } catch (error: Exception) {
                            result.error("mic_stop_failed", error.message, null)
                        }
                    }
                }
                "cancel" -> {
                    recorder?.cancel()
                    recorder = null
                    result.success(true)
                }
                "level" -> result.success(recorder?.currentLevel() ?: 0.0)
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

    private fun startMicRecording(result: MethodChannel.Result) {
        try {
            if (recorder != null) {
                result.error("already_recording", "microphone is already recording", null)
                return
            }
            val next = PcmRecorder(cacheDir)
            next.start()
            recorder = next
            result.success(true)
        } catch (error: Exception) {
            result.error("mic_start_failed", error.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_MIC) return
        val pending = pendingMic
        pendingMic = null
        if (pending == null) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startMicRecording(pending)
        } else {
            pending.error("mic_permission_denied", "RECORD_AUDIO permission denied", null)
        }
    }

    override fun onDestroy() {
        recorder?.cancel()
        recorder = null
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
    }}


/** Records 16 kHz mono PCM16 from the microphone into a WAV file. */
private class PcmRecorder(cacheDir: File) {
    private val file = File(cacheDir, "mic_" + System.currentTimeMillis() + ".wav")
    private val pcm = ByteArrayOutputStream()
    private var record: AudioRecord? = null
    private var thread: Thread? = null

    @Volatile
    private var level = 0.0

    @Volatile
    private var running = false

    fun start() {
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufferSize = maxOf(minBuffer, SAMPLE_RATE * 2)
        val next = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
        )
        if (next.state != AudioRecord.STATE_INITIALIZED) {
            next.release()
            throw IllegalStateException("AudioRecord could not be initialized")
        }
        record = next
        running = true
        next.startRecording()
        thread = Thread {
            val buffer = ByteArray(3200)
            while (running) {
                val read = next.read(buffer, 0, buffer.size)
                if (read > 0) {
                    synchronized(pcm) { pcm.write(buffer, 0, read) }
                    var sum = 0.0
                    var i = 0
                    while (i + 1 < read) {
                        val sample = ((buffer[i + 1].toInt() shl 8) or
                            (buffer[i].toInt() and 0xff)).toShort().toDouble()
                        sum += sample * sample
                        i += 2
                    }
                    val rms = kotlin.math.sqrt(sum / (read / 2).coerceAtLeast(1))
                    level = (rms / 32768.0).coerceIn(0.0, 1.0)
                }
            }
        }.also { it.start() }
    }

    fun stop(): String {
        running = false
        thread?.join(1500)
        thread = null
        record?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        record = null
        writeWav()
        return file.absolutePath
    }

    fun currentLevel(): Double = level

    fun cancel() {
        running = false
        thread?.join(500)
        thread = null
        record?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        record = null
        file.delete()
    }

    private fun writeWav() {
        val data = synchronized(pcm) { pcm.toByteArray() }
        val header = ByteArray(44)
        fun writeInt(offset: Int, value: Int) {
            header[offset] = (value and 0xff).toByte()
            header[offset + 1] = ((value shr 8) and 0xff).toByte()
            header[offset + 2] = ((value shr 16) and 0xff).toByte()
            header[offset + 3] = ((value shr 24) and 0xff).toByte()
        }
        fun writeShort(offset: Int, value: Int) {
            header[offset] = (value and 0xff).toByte()
            header[offset + 1] = ((value shr 8) and 0xff).toByte()
        }
        "RIFF".toByteArray().copyInto(header, 0)
        writeInt(4, 36 + data.size)
        "WAVE".toByteArray().copyInto(header, 8)
        "fmt ".toByteArray().copyInto(header, 12)
        writeInt(16, 16)
        writeShort(20, 1)
        writeShort(22, 1)
        writeInt(24, SAMPLE_RATE)
        writeInt(28, SAMPLE_RATE * 2)
        writeShort(32, 2)
        writeShort(34, 16)
        "data".toByteArray().copyInto(header, 36)
        writeInt(40, data.size)
        file.outputStream().use {
            it.write(header)
            it.write(data)
        }
    }

    companion object {
        private const val SAMPLE_RATE = 16000
    }
}

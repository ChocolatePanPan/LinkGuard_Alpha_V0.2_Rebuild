package com.linkguard.hq.audio

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * HQ 語音錄製器 + Whisper 上傳
 *
 * 錄製 16kHz mono PCM → WAV，上傳到 Whisper server /transcribe
 * 對應 iOS HQSpeechServer 的錄音 + 轉錄功能
 */
class HQVoiceRecorder(private val context: Context) {

    companion object {
        private const val TAG = "HQVoiceRecorder"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val WHISPER_PORT = 8002
        private const val UPLOAD_TIMEOUT_SECONDS = 30L
    }

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording

    private val _isTranscribing = MutableStateFlow(false)
    val isTranscribing: StateFlow<Boolean> = _isTranscribing

    private val _lastTranscription = MutableStateFlow<TranscriptionResult?>(null)
    val lastTranscription: StateFlow<TranscriptionResult?> = _lastTranscription

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    private val _recordingDurationMs = MutableStateFlow(0L)
    val recordingDurationMs: StateFlow<Long> = _recordingDurationMs

    private var audioRecord: AudioRecord? = null
    private var recordingJob: Job? = null
    private var timerJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val httpClient = OkHttpClient.Builder()
        .callTimeout(java.time.Duration.ofSeconds(UPLOAD_TIMEOUT_SECONDS))
        .connectTimeout(java.time.Duration.ofSeconds(10))
        .readTimeout(java.time.Duration.ofSeconds(UPLOAD_TIMEOUT_SECONDS))
        .build()

    private var currentFile: File? = null
    private var recordStartTime = 0L

    var whisperHost: String = ""   // set from backendBridge host
    var deviceId: String = "HQ-Android"
    var onTranscriptionComplete: ((TranscriptionResult) -> Unit)? = null

    // MARK: - 錄音控制

    fun startRecording() {
        if (_isRecording.value) return

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
            .coerceAtLeast(SAMPLE_RATE * 2) // at least 1 second buffer

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT, bufferSize
            )
        } catch (e: SecurityException) {
            _lastError.value = "缺少錄音權限"
            Log.e(TAG, "Missing RECORD_AUDIO permission", e)
            return
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            _lastError.value = "無法初始化錄音"
            audioRecord?.release()
            audioRecord = null
            return
        }

        val audioDir = File(context.filesDir, "audio").apply { mkdirs() }
        currentFile = File(audioDir, "recording_${System.currentTimeMillis()}.wav")

        audioRecord?.startRecording()
        _isRecording.value = true
        _lastError.value = null
        recordStartTime = System.currentTimeMillis()
        _recordingDurationMs.value = 0L

        timerJob = scope.launch(Dispatchers.Main) {
            try {
                while (isActive && _isRecording.value) {
                    _recordingDurationMs.value = System.currentTimeMillis() - recordStartTime
                    delay(100)
                }
            } catch (_: kotlinx.coroutines.CancellationException) {
                // 正常取消，忽略
            }
        }

        recordingJob = scope.launch {
            val pcmData = mutableListOf<ByteArray>()
            val buffer = ByteArray(bufferSize)

            try {
                while (isActive && _isRecording.value) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                    if (read > 0) {
                        pcmData.add(buffer.copyOf(read))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Recording error: ${e.message}")
            }

            // Write WAV file
            val totalDataSize = pcmData.sumOf { it.size }
            val outFile = currentFile
            if (outFile != null && totalDataSize > 0) {
                writeWavFile(outFile, pcmData, totalDataSize)
                Log.d(TAG, "Recording saved: ${outFile.absolutePath} ($totalDataSize bytes)")
            } else if (outFile == null) {
                Log.w(TAG, "Recording finished but currentFile is null")
            }
        }

        Log.d(TAG, "Recording started")
    }

    fun stopRecording() {
        if (!_isRecording.value) return

        _isRecording.value = false
        timerJob?.cancel()
        timerJob = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        audioRecord?.release()
        audioRecord = null

        // Wait for recording job to finish writing, then upload
        scope.launch {
            recordingJob?.join()
            recordingJob = null

            val file = currentFile
            if (file != null && file.exists() && file.length() > 44) {
                uploadToWhisper(file)
            } else {
                _lastError.value = "錄音檔案為空"
            }
        }

        Log.d(TAG, "Recording stopped")
    }

    // MARK: - WAV 寫入

    private fun writeWavFile(file: File, pcmData: List<ByteArray>, dataSize: Int) {
        FileOutputStream(file).use { fos ->
            val header = createWavHeader(dataSize)
            fos.write(header)
            pcmData.forEach { fos.write(it) }
        }
    }

    private fun createWavHeader(dataSize: Int): ByteArray {
        val totalSize = dataSize + 36
        val buf = ByteBuffer.allocate(44).apply { order(ByteOrder.LITTLE_ENDIAN) }

        // RIFF header
        buf.put("RIFF".toByteArray())
        buf.putInt(totalSize)
        buf.put("WAVE".toByteArray())

        // fmt chunk
        buf.put("fmt ".toByteArray())
        buf.putInt(16)           // chunk size
        buf.putShort(1)          // PCM format
        buf.putShort(1)          // mono
        buf.putInt(SAMPLE_RATE)  // sample rate
        buf.putInt(SAMPLE_RATE * 2)  // byte rate (16bit mono)
        buf.putShort(2)          // block align
        buf.putShort(16)         // bits per sample

        // data chunk
        buf.put("data".toByteArray())
        buf.putInt(dataSize)

        return buf.array()
    }

    // MARK: - Whisper 上傳

    private suspend fun uploadToWhisper(file: File) {
        if (whisperHost.isBlank()) {
            _lastError.value = "未設置 Whisper 伺服器地址"
            return
        }

        _isTranscribing.value = true
        _lastError.value = null

        try {
            val url = "http://$whisperHost:$WHISPER_PORT/transcribe"

            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("file", file.name,
                    file.asRequestBody("audio/wav".toMediaType()))
                .addFormDataPart("source", "hq_recording")
                .addFormDataPart("sender_id", deviceId)
                .addFormDataPart("language", "zh")
                .build()

            val request = Request.Builder()
                .url(url)
                .post(requestBody)
                .build()

            val response = httpClient.newCall(request).execute()
            val body = response.body?.string() ?: ""

            if (response.isSuccessful && body.isNotEmpty()) {
                val json = JSONObject(body)
                val dataObj = json.optJSONObject("data") ?: json

                val result = TranscriptionResult(
                    text = dataObj.optString("text", ""),
                    language = dataObj.optString("language", "zh"),
                    duration = dataObj.optDouble("duration", 0.0),
                    audioFile = file.absolutePath
                )

                withContext(Dispatchers.Main) {
                    _lastTranscription.value = result
                    onTranscriptionComplete?.invoke(result)
                }
                Log.d(TAG, "Transcription: ${result.text}")
            } else {
                val errorMsg = "Whisper 轉錄失敗: ${response.code}"
                withContext(Dispatchers.Main) {
                    _lastError.value = errorMsg
                }
                Log.e(TAG, "$errorMsg body=$body")
            }
        } catch (e: Exception) {
            val errorMsg = "上傳失敗: ${e.message}"
            withContext(Dispatchers.Main) {
                _lastError.value = errorMsg
            }
            Log.e(TAG, errorMsg, e)
        } finally {
            withContext(Dispatchers.Main) {
                _isTranscribing.value = false
            }
        }
    }

    fun destroy() {
        scope.cancel()
        try { audioRecord?.release() } catch (_: Exception) {}
        httpClient.dispatcher.executorService.shutdown()
    }
}

data class TranscriptionResult(
    val text: String,
    val language: String = "zh",
    val duration: Double = 0.0,
    val audioFile: String = "",
    val timestamp: Long = System.currentTimeMillis()
)

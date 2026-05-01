package com.linkguard.hq.net

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * LGAP 即時音訊串流伺服器（HQ-Android, port 8005）
 *
 * 對應 Mac HQ 的 AudioStreamServer.swift。
 * 前線裝置按住 PTT 時，透過 TCP 以 LGAP 協議傳送 PCM 16-bit 16kHz mono 音訊。
 * HQ 接收後即時播放並在連線結束後送 Whisper 轉錄。
 *
 * LGAP 封包格式（小端序）：
 *   [4 bytes] magic: "LGAP" (0x4C474150)
 *   [4 bytes] payloadLength: UInt32 (PCM Int16 位元組數)
 *   [N bytes] payload: Int16 PCM samples, 16kHz mono, little-endian
 */
class HQAudioStreamServer(private val context: Context) {

    companion object {
        private const val TAG = "HQAudioStreamServer"
        private const val PORT = 8005
        private const val SAMPLE_RATE = 16000
        private const val LGAP_MAGIC = 0x4C474150  // "LGAP"
        private const val HEADER_SIZE = 8           // 4 magic + 4 length
        private const val MAX_PAYLOAD = 1_048_576   // 1 MB safety limit
    }

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying

    private val _currentSender = MutableStateFlow<String?>(null)
    val currentSender: StateFlow<String?> = _currentSender

    private val _packetCount = MutableStateFlow(0)
    val packetCount: StateFlow<Int> = _packetCount

    /** Whisper server host for transcription after PTT ends */
    var whisperHost: String = ""

    /** Callback when transcription completes */
    var onTranscriptionComplete: ((String, String) -> Unit)? = null  // (senderId, transcription)

    /** Callback when broadcast starts/stops — wired to HQCommandServer's activeBroadcaster */
    var onBroadcastStateChanged: ((Boolean, String) -> Unit)? = null  // (isStart, senderId)

    private var serverSocket: ServerSocket? = null
    private var serverJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var audioTrack: AudioTrack? = null

    // === 生命週期 ===

    fun start() {
        if (_isRunning.value) return
        initAudioTrack()
        serverJob = scope.launch {
            try {
                serverSocket = ServerSocket(PORT)
                _isRunning.value = true
                Log.d(TAG, "✅ HQAudioStreamServer 啟動於 port $PORT")

                while (isActive) {
                    val clientSocket = serverSocket?.accept() ?: break
                    launch { handleClient(clientSocket) }
                }
            } catch (e: Exception) {
                if (isActive) Log.e(TAG, "伺服器錯誤: ${e.message}")
            } finally {
                _isRunning.value = false
            }
        }
    }

    fun stop() {
        serverJob?.cancel()
        serverJob = null
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        releaseAudioTrack()
        _isRunning.value = false
        _isPlaying.value = false
        _currentSender.value = null
        Log.d(TAG, "HQAudioStreamServer 已停止")
    }

    // === AudioTrack 初始化 ===

    private fun initAudioTrack() {
        val bufferSize = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(3200)

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        audioTrack?.play()
    }

    private fun releaseAudioTrack() {
        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null
    }

    // === 連線處理 ===

    private suspend fun handleClient(socket: Socket) {
        val addr = socket.inetAddress.hostAddress ?: "unknown"
        val senderId = "lgap-$addr:${socket.port}"
        Log.d(TAG, "📡 音訊連線: $addr")

        withContext(Dispatchers.Main) {
            _isPlaying.value = true
            _currentSender.value = senderId
            _packetCount.value = 0
        }
        onBroadcastStateChanged?.invoke(true, senderId)

        val audioBuffer = ByteArrayOutputStream()
        val buf = ByteArray(8192)
        val pending = ByteArrayOutputStream()
        var totalPackets = 0

        try {
            socket.soTimeout = 30_000
            val input: InputStream = socket.getInputStream()

            while (true) {
                val bytesRead = input.read(buf)
                if (bytesRead == -1) break

                pending.write(buf, 0, bytesRead)
                val data = pending.toByteArray()
                var offset = 0

                while (offset + HEADER_SIZE <= data.size) {
                    // Read magic (little-endian)
                    val magic = ByteBuffer.wrap(data, offset, 4)
                        .order(ByteOrder.LITTLE_ENDIAN).int
                    if (magic != LGAP_MAGIC) {
                        offset++
                        continue
                    }

                    // Read payload length (little-endian)
                    val payloadLen = ByteBuffer.wrap(data, offset + 4, 4)
                        .order(ByteOrder.LITTLE_ENDIAN).int

                    if (payloadLen <= 0 || payloadLen > MAX_PAYLOAD) {
                        offset += 4
                        continue
                    }

                    if (offset + HEADER_SIZE + payloadLen > data.size) {
                        break  // Incomplete packet, wait for more data
                    }

                    // Extract PCM payload
                    val pcm = data.copyOfRange(offset + HEADER_SIZE, offset + HEADER_SIZE + payloadLen)
                    offset += HEADER_SIZE + payloadLen

                    // Play audio
                    audioTrack?.write(pcm, 0, pcm.size)

                    // Accumulate for Whisper
                    audioBuffer.write(pcm)

                    totalPackets++
                    if (totalPackets % 50 == 0) {
                        withContext(Dispatchers.Main) {
                            _packetCount.value = totalPackets
                        }
                    }
                }

                // Retain unprocessed bytes
                pending.reset()
                if (offset < data.size) {
                    pending.write(data, offset, data.size - offset)
                }
            }
        } catch (e: java.net.SocketTimeoutException) {
            Log.d(TAG, "音訊連線逾時 (soTimeout): ${e.message}")
        } catch (e: Exception) {
            Log.d(TAG, "音訊連線結束: ${e.message}")
        } finally {
            try { socket.close() } catch (_: Exception) {}

            withContext(Dispatchers.Main) {
                _isPlaying.value = false
                _currentSender.value = null
                _packetCount.value = totalPackets
            }
            onBroadcastStateChanged?.invoke(false, senderId)

            Log.d(TAG, "📊 連線結束. 總封包: $totalPackets, 音訊: ${audioBuffer.size()} bytes")

            // Attempt Whisper transcription if enough audio
            if (audioBuffer.size() > 1600) {
                scope.launch {
                    transcribeAudio(senderId, audioBuffer.toByteArray())
                }
            }
        }
    }

    // === Whisper 轉錄 ===

    private fun transcribeAudio(senderId: String, pcmData: ByteArray) {
        val host = whisperHost
        if (host.isEmpty()) {
            Log.w(TAG, "未設定 Whisper host，跳過轉錄")
            return
        }

        try {
            // Convert PCM to WAV
            val wavData = pcmToWav(pcmData, SAMPLE_RATE, 1, 16)

            val urlHost = if (host.contains(":") && !host.startsWith("[")) "[$host]" else host
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "file", "ptt_audio.wav",
                    wavData.toRequestBody("audio/wav".toMediaType())
                )
                .addFormDataPart("source", "ptt_live")
                .addFormDataPart("sender_id", senderId)
                .addFormDataPart("language", "zh")
                .build()

            val request = Request.Builder()
                .url("http://$urlHost:8002/transcribe")
                .post(requestBody)
                .build()

            val client = OkHttpClient.Builder()
                .callTimeout(java.time.Duration.ofSeconds(30))
                .connectTimeout(java.time.Duration.ofSeconds(10))
                .readTimeout(java.time.Duration.ofSeconds(30))
                .build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string() ?: ""
                val json = org.json.JSONObject(body)
                val text = json.optString("text", "").trim()
                if (text.isNotEmpty()) {
                    Log.d(TAG, "✅ 轉錄完成: ${text.take(60)}")
                    onTranscriptionComplete?.invoke(senderId, text)
                }
            } else {
                Log.w(TAG, "Whisper 回應 ${response.code}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "轉錄失敗: ${e.message}")
        }
    }

    // === PCM → WAV 轉換 ===

    private fun pcmToWav(pcm: ByteArray, sampleRate: Int, channels: Int, bitsPerSample: Int): ByteArray {
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val dataSize = pcm.size
        val headerSize = 44

        val buffer = ByteBuffer.allocate(headerSize + dataSize).order(ByteOrder.LITTLE_ENDIAN)

        // RIFF header
        buffer.put("RIFF".toByteArray())
        buffer.putInt(36 + dataSize)
        buffer.put("WAVE".toByteArray())

        // fmt chunk
        buffer.put("fmt ".toByteArray())
        buffer.putInt(16)                   // chunk size
        buffer.putShort(1)                  // PCM format
        buffer.putShort(channels.toShort())
        buffer.putInt(sampleRate)
        buffer.putInt(byteRate)
        buffer.putShort(blockAlign.toShort())
        buffer.putShort(bitsPerSample.toShort())

        // data chunk
        buffer.put("data".toByteArray())
        buffer.putInt(dataSize)
        buffer.put(pcm)

        return buffer.array()
    }
}

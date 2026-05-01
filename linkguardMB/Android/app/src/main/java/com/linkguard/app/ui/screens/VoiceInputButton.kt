package com.linkguard.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import com.linkguard.app.ui.theme.NV
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

// =====================================================
//  通用語音輸入按鈕 — 對應 iOS VoiceInputButton
//  長按開始錄音，放開上傳 Whisper Server 轉錄
// =====================================================

enum class VoiceInputState {
    IDLE, RECORDING, UPLOADING, DONE, ERROR
}

@Composable
fun VoiceInputButton(
    serverHost: String,
    onTranscribed: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf(VoiceInputState.IDLE) }
    var resultText by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf("") }
    var audioRecorder by remember { mutableStateOf<AudioRecord?>(null) }
    var pcmBuffer by remember { mutableStateOf<ByteArrayOutputStream?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { _ -> }

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

    fun startRecording() {
        if (!hasPermission()) {
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            return
        }
        var recorder: AudioRecord? = null
        try {
            val sampleRate = 16000
            val bufSize = AudioRecord.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            @Suppress("MissingPermission")
            recorder = AudioRecord(
                MediaRecorder.AudioSource.MIC, sampleRate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize
            )
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                throw IllegalStateException("AudioRecord init failed")
            }
            val baos = ByteArrayOutputStream()
            recorder.startRecording()
            audioRecorder = recorder
            pcmBuffer = baos
            state = VoiceInputState.RECORDING

            scope.launch(Dispatchers.IO) {
                val buf = ByteArray(bufSize)
                while (state == VoiceInputState.RECORDING) {
                    val read = recorder.read(buf, 0, buf.size)
                    if (read > 0) baos.write(buf, 0, read)
                }
            }
        } catch (e: Exception) {
            // 確保失敗時 AudioRecord 不被洩漏
            try { recorder?.stop() } catch (_: Exception) {}
            try { recorder?.release() } catch (_: Exception) {}
            audioRecorder = null
            pcmBuffer = null
            state = VoiceInputState.ERROR
            errorMessage = e.message ?: "錄音啟動失敗"
        }
    }

    fun stopAndTranscribe() {
        val recorder = audioRecorder ?: return
        val baos = pcmBuffer ?: return
        state = VoiceInputState.UPLOADING

        try {
            recorder.stop()
            recorder.release()
        } catch (_: Exception) {}
        audioRecorder = null

        val pcmData = baos.toByteArray()
        pcmBuffer = null

        if (pcmData.isEmpty() || serverHost.isEmpty()) {
            state = VoiceInputState.ERROR
            errorMessage = if (serverHost.isEmpty()) "未連線伺服器" else "無錄音資料"
            return
        }

        // 轉成 WAV 格式再上傳
        val wavData = pcmToWav(pcmData, 16000, 1, 16)

        scope.launch {
            try {
                val text = withContext(Dispatchers.IO) {
                    val requestBody = MultipartBody.Builder()
                        .setType(MultipartBody.FORM)
                        .addFormDataPart(
                            "audio", "voice.wav",
                            wavData.toRequestBody("audio/wav".toMediaType())
                        )
                        .build()

                    val request = Request.Builder()
                        .url("http://$serverHost:8003/transcribe")
                        .post(requestBody)
                        .build()

                    val client = OkHttpClient.Builder()
                        .connectTimeout(10, TimeUnit.SECONDS)
                        .writeTimeout(30, TimeUnit.SECONDS)
                        .readTimeout(30, TimeUnit.SECONDS)
                        .build()

                    val response = client.newCall(request).execute()
                    if (!response.isSuccessful) throw Exception("HTTP ${response.code}")
                    val body = response.body?.string() ?: "{}"
                    JSONObject(body).optString("text", "")
                }

                if (text.isNotEmpty()) {
                    state = VoiceInputState.DONE
                    resultText = text
                    onTranscribed(text)
                    delay(1500)
                    state = VoiceInputState.IDLE
                } else {
                    state = VoiceInputState.ERROR
                    errorMessage = "未偵測到語音"
                }
            } catch (e: Exception) {
                state = VoiceInputState.ERROR
                errorMessage = e.message ?: "轉錄失敗"
            }
        }
    }

    // 錯誤狀態點擊重置
    fun resetIfError() {
        if (state == VoiceInputState.ERROR) state = VoiceInputState.IDLE
    }

    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        when (state) {
            VoiceInputState.IDLE -> {
                Button(
                    onClick = { /* 長按用 pointerInput */ },
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                    contentPadding = PaddingValues(14.dp),
                    modifier = Modifier
                        .size(56.dp)
                        .pointerInput(Unit) {
                            detectTapGestures(
                                onPress = {
                                    startRecording()
                                    tryAwaitRelease()
                                    if (state == VoiceInputState.RECORDING) {
                                        stopAndTranscribe()
                                    }
                                }
                            )
                        }
                ) {
                    Icon(Icons.Default.Mic, "語音輸入", tint = NV.white)
                }
            }

            VoiceInputState.RECORDING -> {
                val infiniteTransition = rememberInfiniteTransition(label = "pulse")
                val pulseScale by infiniteTransition.animateFloat(
                    initialValue = 1f,
                    targetValue = 1.3f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(600, easing = EaseInOut),
                        repeatMode = RepeatMode.Reverse
                    ),
                    label = "pulse"
                )
                Button(
                    onClick = { stopAndTranscribe() },
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = NV.danger.copy(alpha = 0.15f)),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                    modifier = Modifier.defaultMinSize(minHeight = 56.dp)
                ) {
                    Surface(
                        modifier = Modifier
                            .size(10.dp)
                            .scale(pulseScale),
                        shape = CircleShape,
                        color = NV.danger
                    ) {}
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("錄音中⋯ 點擊停止", fontSize = 12.sp, color = NV.danger)
                }
            }

            VoiceInputState.UPLOADING -> {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = NV.textSecondary,
                        strokeWidth = 2.dp
                    )
                    Text("轉錄中⋯", fontSize = 12.sp, color = NV.textSecondary)
                }
            }

            VoiceInputState.DONE -> {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Default.CheckCircle, null, tint = NV.green, modifier = Modifier.size(16.dp))
                    Text("已轉錄", fontSize = 12.sp, color = NV.green)
                }
            }

            VoiceInputState.ERROR -> {
                Surface(
                    onClick = { resetIfError() },
                    shape = RoundedCornerShape(8.dp),
                    color = NV.danger.copy(alpha = 0.1f)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(Icons.Default.Error, null, tint = NV.danger, modifier = Modifier.size(14.dp))
                        Text(errorMessage, fontSize = 11.sp, color = NV.danger, maxLines = 2)
                    }
                }
            }
        }
    }
}

// WAV header builder
private fun pcmToWav(pcm: ByteArray, sampleRate: Int, channels: Int, bitsPerSample: Int): ByteArray {
    val byteRate = sampleRate * channels * bitsPerSample / 8
    val blockAlign = channels * bitsPerSample / 8
    val dataLen = pcm.size
    val totalLen = 36 + dataLen

    val header = ByteArray(44)
    // RIFF header
    header[0] = 'R'.code.toByte(); header[1] = 'I'.code.toByte()
    header[2] = 'F'.code.toByte(); header[3] = 'F'.code.toByte()
    writeInt(header, 4, totalLen)
    header[8] = 'W'.code.toByte(); header[9] = 'A'.code.toByte()
    header[10] = 'V'.code.toByte(); header[11] = 'E'.code.toByte()
    // fmt
    header[12] = 'f'.code.toByte(); header[13] = 'm'.code.toByte()
    header[14] = 't'.code.toByte(); header[15] = ' '.code.toByte()
    writeInt(header, 16, 16) // subchunk1 size
    writeShort(header, 20, 1) // PCM
    writeShort(header, 22, channels)
    writeInt(header, 24, sampleRate)
    writeInt(header, 28, byteRate)
    writeShort(header, 32, blockAlign)
    writeShort(header, 34, bitsPerSample)
    // data
    header[36] = 'd'.code.toByte(); header[37] = 'a'.code.toByte()
    header[38] = 't'.code.toByte(); header[39] = 'a'.code.toByte()
    writeInt(header, 40, dataLen)

    return header + pcm
}

private fun writeInt(buf: ByteArray, offset: Int, value: Int) {
    buf[offset] = (value and 0xff).toByte()
    buf[offset + 1] = ((value shr 8) and 0xff).toByte()
    buf[offset + 2] = ((value shr 16) and 0xff).toByte()
    buf[offset + 3] = ((value shr 24) and 0xff).toByte()
}

private fun writeShort(buf: ByteArray, offset: Int, value: Int) {
    buf[offset] = (value and 0xff).toByte()
    buf[offset + 1] = ((value shr 8) and 0xff).toByte()
}

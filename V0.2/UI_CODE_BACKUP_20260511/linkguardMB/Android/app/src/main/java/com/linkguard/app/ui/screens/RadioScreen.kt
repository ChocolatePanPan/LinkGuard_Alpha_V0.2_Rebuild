package com.linkguard.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.linkguard.app.model.RadioReport
import com.linkguard.app.model.TextBroadcast
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun RadioScreen(viewModel: LinkGuardViewModel) {
    var selectedMode by remember { mutableIntStateOf(1) } // 0=live, 1=briefing, 2=textBroadcast

    Column(modifier = Modifier.fillMaxSize()) {
        // 模式選擇器
        TabRow(
            selectedTabIndex = selectedMode,
            containerColor = NV.surface,
            contentColor = NV.white,
            indicator = { tabPositions ->
                Box(Modifier.fillMaxSize()) {
                    if (selectedMode < tabPositions.size) {
                        Box(
                            Modifier
                                .align(Alignment.BottomStart)
                                .offset(x = tabPositions[selectedMode].left)
                                .width(tabPositions[selectedMode].width)
                                .height(3.dp)
                                .background(NV.green)
                        )
                    }
                }
            },
            divider = {}
        ) {
            Tab(selected = selectedMode == 0, onClick = { selectedMode = 0 },
                selectedContentColor = NV.green, unselectedContentColor = NV.textSecondary,
                text = { Text("即時廣播") },
                icon = { Icon(Icons.Default.SettingsRemote, contentDescription = null) })
            Tab(selected = selectedMode == 1, onClick = { selectedMode = 1 },
                selectedContentColor = NV.green, unselectedContentColor = NV.textSecondary,
                text = { Text("固定會報") },
                icon = { Icon(Icons.Default.Description, contentDescription = null) })
            Tab(selected = selectedMode == 2, onClick = { selectedMode = 2 },
                selectedContentColor = NV.green, unselectedContentColor = NV.textSecondary,
                text = { Text("文字廣播") },
                icon = { Icon(Icons.Default.Campaign, contentDescription = null) })
        }

        when (selectedMode) {
            0 -> LiveBroadcastContent(viewModel)
            1 -> BriefingContent(viewModel)
            2 -> TextBroadcastContent(viewModel)
        }
    }
}

// MARK: - 文字廣播

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun TextBroadcastContent(viewModel: LinkGuardViewModel) {
    var broadcastText by remember { mutableStateOf("") }
    var isUrgent by remember { mutableStateOf(false) }
    val broadcasts by viewModel.textBroadcasts.collectAsState()

    Column(modifier = Modifier.fillMaxSize()) {
        // 發送區
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // 優先級選擇
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("優先級", fontSize = 14.sp, color = NV.textSecondary)
                FilterChip(selected = !isUrgent, onClick = { isUrgent = false },
                    label = { Text("一般", color = NV.white) })
                FilterChip(selected = isUrgent, onClick = { isUrgent = true },
                    label = { Text("緊急", color = NV.white) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = NV.danger.copy(alpha = 0.2f)
                    ))
            }

            OutlinedTextField(
                value = broadcastText,
                onValueChange = { broadcastText = it },
                modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp),
                placeholder = { Text("輸入廣播訊息...", color = NV.textSecondary.copy(alpha = 0.6f)) },
                maxLines = 4,
                colors = androidx.compose.material3.TextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent
                )
            )

            Button(
                onClick = {
                    val text = broadcastText.trim()
                    if (text.isNotEmpty()) {
                        viewModel.sendTextBroadcast(text, if (isUrgent) "urgent" else "normal")
                        broadcastText = ""
                    }
                },
                modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp),
                enabled = broadcastText.trim().isNotEmpty(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isUrgent) NV.danger else NV.command
                )
            ) {
                Icon(Icons.Default.Send, contentDescription = null, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(8.dp))
                Text("發送廣播", fontSize = 16.sp)
            }
        }

        @Suppress("DEPRECATION")
        androidx.compose.material3.Divider()

        // 廣播歷史
        if (broadcasts.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Campaign, contentDescription = null,
                        tint = NV.textSecondary.copy(alpha = 0.5f), modifier = Modifier.size(64.dp))
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("尚無文字廣播", color = NV.textSecondary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(broadcasts.take(20)) { broadcast ->
                    TextBroadcastRow(broadcast)
                }
            }
        }
    }
}

@Composable
private fun TextBroadcastRow(broadcast: TextBroadcast) {
    val bgColor = if (broadcast.priority == "urgent") NV.danger.copy(alpha = 0.05f) else Color.Transparent
    Column(modifier = Modifier.fillMaxWidth().background(bgColor).padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (broadcast.priority == "urgent") {
                Icon(Icons.Default.Warning, contentDescription = null,
                    tint = NV.danger, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
            }
            Icon(Icons.Default.Campaign, contentDescription = null,
                tint = if (broadcast.priority == "urgent") NV.danger else NV.command,
                modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(4.dp))
            Text(broadcast.senderName, fontWeight = FontWeight.Bold, fontSize = 14.sp, color = NV.white)
            Spacer(Modifier.weight(1f))
            Text(broadcast.timeText, fontSize = 10.sp, color = NV.textSecondary)
        }
        Text(broadcast.message, fontSize = 14.sp, color = NV.white, modifier = Modifier.padding(top = 4.dp))
        Row(modifier = Modifier.padding(top = 2.dp)) {
            Text("ID: ${broadcast.broadcastId}", fontSize = 10.sp, color = NV.textSecondary.copy(alpha = 0.7f))
            if (broadcast.priority == "urgent") {
                Spacer(Modifier.width(8.dp))
                Text("緊急", fontSize = 10.sp, color = NV.danger,
                    modifier = Modifier.background(NV.danger.copy(alpha = 0.1f), RoundedCornerShape(4.dp))
                        .padding(horizontal = 4.dp, vertical = 1.dp))
            }
        }
    }
}

// MARK: - 即時廣播

@Composable
private fun LiveBroadcastContent(viewModel: LinkGuardViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isConnected by viewModel.commandClient.isConnected.collectAsState()
    val currentBroadcaster by viewModel.currentBroadcaster.collectAsState()
    var isBroadcasting by remember { mutableStateOf(false) }
    val nodeStatus by viewModel.nodeStatus.collectAsState()

    // AudioRecord & TCP streaming state
    val audioRecordRef = remember { mutableStateOf<AudioRecord?>(null) }
    val tcpSocketRef = remember { mutableStateOf<Socket?>(null) }
    val streamingJob = remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }

    // Local recording for transcription upload
    val mediaRecorderRef = remember { mutableStateOf<android.media.MediaRecorder?>(null) }
    val recordFileRef = remember { mutableStateOf<File?>(null) }
    var isUploading by remember { mutableStateOf(false) }
    var uploadProgress by remember { mutableStateOf<String?>(null) }
    var uploadError by remember { mutableStateOf<String?>(null) }
    var lastTranscription by remember { mutableStateOf<String?>(null) }
    // Recording elapsed timer
    var recordingStartTime by remember { mutableStateOf(0L) }
    var elapsedSeconds by remember { mutableIntStateOf(0) }

    LaunchedEffect(isBroadcasting) {
        if (isBroadcasting) {
            recordingStartTime = System.currentTimeMillis()
            while (isBroadcasting) {
                elapsedSeconds = ((System.currentTimeMillis() - recordingStartTime) / 1000).toInt()
                kotlinx.coroutines.delay(500)
            }
        } else {
            elapsedSeconds = 0
        }
    }

    var hasRecordPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        )
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasRecordPermission = granted }

    // Cleanup on dispose
    DisposableEffect(Unit) {
        onDispose {
            streamingJob.value?.cancel()
            try { audioRecordRef.value?.stop() } catch (_: Exception) {}
            try { audioRecordRef.value?.release() } catch (_: Exception) {}
            try { tcpSocketRef.value?.close() } catch (_: Exception) {}
            try { mediaRecorderRef.value?.stop() } catch (_: Exception) {}
            try { mediaRecorderRef.value?.release() } catch (_: Exception) {}
        }
    }

    // PTT 按鈕動畫
    val pttScale by animateFloatAsState(
        targetValue = if (isBroadcasting) 1.12f else 1f,
        animationSpec = spring(dampingRatio = 0.5f, stiffness = 300f),
        label = "pttScale"
    )
    val pttColor by animateColorAsState(
        targetValue = if (isBroadcasting) NV.danger else NV.command,
        animationSpec = tween(150),
        label = "pttColor"
    )
    // Recording pulse animation
    val pulseAlpha by animateFloatAsState(
        targetValue = if (isBroadcasting) 0.3f else 0f,
        animationSpec = if (isBroadcasting) infiniteRepeatable(
            tween(800, easing = LinearEasing), RepeatMode.Reverse
        ) else tween(300),
        label = "livePulse"
    )

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Spacer(Modifier.weight(1f))

        // 廣播者狀態
        currentBroadcaster?.let { broadcaster ->
            Card(
                colors = CardDefaults.cardColors(containerColor = NV.danger.copy(alpha = 0.1f)),
                shape = NVShape.card
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Default.SettingsRemote, contentDescription = null, tint = NV.danger)
                    Text("$broadcaster 正在廣播", color = NV.danger, fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(24.dp))
        }

        // PTT 按鈕
        val haptic = LocalHapticFeedback.current
        Box(
            modifier = Modifier
                .size(140.dp)
                .graphicsLayer {
                    scaleX = pttScale
                    scaleY = pttScale
                }
                .shadow(if (isBroadcasting) 24.dp else 6.dp, CircleShape,
                    ambientColor = if (isBroadcasting) NV.danger else NV.command)
                .clip(CircleShape)
                .background(pttColor)
                .pointerInput(Unit) {
                    detectTapGestures(
                        onPress = {
                            if (!hasRecordPermission) {
                                permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                return@detectTapGestures
                            }

                            // === 手指按下 → 開始廣播 ===
                            Log.d("RadioScreen", "PTT DOWN — starting broadcast")
                            isBroadcasting = true
                            uploadProgress = null
                            uploadError = null
                            lastTranscription = null
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            viewModel.commandClient.sendRadioControl("start", nodeStatus.nodeID)

                            // 同時啟動本地 M4A 錄音（用於轉錄上傳）
                            val recFile = File(context.cacheDir, "ptt_${System.currentTimeMillis()}.m4a")
                            recordFileRef.value = recFile
                            try {
                                val mr = android.media.MediaRecorder(context).apply {
                                    setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                                    setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                                    setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                                    setAudioSamplingRate(16000)
                                    setAudioChannels(1)
                                    setOutputFile(recFile.absolutePath)
                                    prepare()
                                    start()
                                }
                                mediaRecorderRef.value = mr
                            } catch (e: Exception) {
                                Log.e("RadioScreen", "MediaRecorder start failed: ${e.message}")
                            }

                            val serverHost = viewModel.commandClient.serverHost
                            streamingJob.value = scope.launch(Dispatchers.IO) {
                                startTcpAudioStream(
                                    serverHost = serverHost,
                                    audioRecordRef = audioRecordRef,
                                    tcpSocketRef = tcpSocketRef
                                )
                            }

                            // 等待手指放開
                            val released = tryAwaitRelease()
                            Log.d("RadioScreen", "PTT UP — released=$released, stopping broadcast")

                            // === 手指放開或取消 → 停止廣播 ===
                            isBroadcasting = false
                            viewModel.commandClient.sendRadioControl("stop", nodeStatus.nodeID)
                            stopTcpAudioStream(audioRecordRef, tcpSocketRef, streamingJob)

                            // 停止本地錄音並上傳轉錄
                            try { mediaRecorderRef.value?.stop() } catch (_: Exception) {}
                            try { mediaRecorderRef.value?.release() } catch (_: Exception) {}
                            mediaRecorderRef.value = null

                            val file = recordFileRef.value
                            if (file != null && file.exists() && file.length() > 100) {
                                // 檢查錄音時長
                                val durationMs = System.currentTimeMillis() - recordingStartTime
                                if (durationMs < 1000) {
                                    uploadError = "錄音太短，請按住至少 1 秒"
                                    file.delete()
                                } else {
                                    isUploading = true
                                    uploadProgress = "上傳轉錄中…"
                                    scope.launch {
                                        val result = uploadLivePtt(
                                            file = file,
                                            senderName = nodeStatus.nodeID,
                                            serverHost = viewModel.commandClient.serverHost
                                        )
                                        isUploading = false
                                        if (result.success) {
                                            uploadProgress = "轉錄完成"
                                            lastTranscription = result.transcription
                                        } else {
                                            uploadProgress = null
                                            uploadError = result.message
                                        }
                                        file.delete()
                                    }
                                }
                            }
                        }
                    )
                },
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    if (isBroadcasting) Icons.Default.Mic else Icons.Default.MicNone,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = if (isBroadcasting) NV.textOnColor else Color.White
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    if (isBroadcasting) "放開結束" else "按住說話",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (isBroadcasting) NV.textOnColor else Color.White
                )
            }
        }

        // 錄音計時器
        if (isBroadcasting) {
            Spacer(Modifier.height(8.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Box(
                    Modifier.size(8.dp).clip(CircleShape)
                        .background(NV.danger.copy(alpha = 0.5f + pulseAlpha))
                )
                Text(
                    String.format("%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = NV.danger
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        Text("按住錄音，放開後自動上傳轉錄歸檔",
            fontSize = 12.sp, color = NV.textSecondary)

        // 上傳進度
        if (isUploading) {
            Spacer(Modifier.height(12.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(uploadProgress ?: "上傳中…", fontSize = 12.sp, color = NV.textSecondary)
            }
        } else if (uploadProgress != null) {
            Spacer(Modifier.height(12.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(Icons.Default.CheckCircle, contentDescription = null,
                    tint = NV.green, modifier = Modifier.size(16.dp))
                Text(uploadProgress!!, fontSize = 12.sp, color = NV.green)
            }
        }

        // 轉錄結果
        if (lastTranscription != null) {
            Spacer(Modifier.height(8.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                )
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("語音轉錄", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.Gray)
                    Spacer(Modifier.height(4.dp))
                    Text(lastTranscription!!, fontSize = 13.sp, lineHeight = 18.sp)
                }
            }
        }

        // 錯誤訊息
        if (uploadError != null) {
            Spacer(Modifier.height(8.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(Icons.Default.Error, contentDescription = null,
                    tint = NV.danger, modifier = Modifier.size(16.dp))
                Text(uploadError!!, fontSize = 12.sp, color = NV.danger)
            }
        }

        Spacer(Modifier.weight(1f))

        // 連線狀態
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(if (isConnected) NV.green else NV.textSecondary))
            Text(if (isConnected) "已連線指揮中心" else "未連線",
                fontSize = 12.sp, color = NV.textSecondary)
        }
    }
}

// === TCP LGAP 音頻串流（與 iOS 一致） ===

private const val TCP_STREAM_PORT = 8005
private const val SAMPLE_RATE = 16000
private const val LGAP_MAGIC = 0x4C474150  // "LGAP" little-endian

/**
 * Start recording from microphone and stream PCM 16-bit 16kHz mono via TCP
 * using the LGAP protocol: Magic(4 bytes LE) + PayloadLen(4 bytes LE UInt32) + PCM Int16 data
 */
@Suppress("MissingPermission")
private fun startTcpAudioStream(
    serverHost: String,
    audioRecordRef: MutableState<AudioRecord?>,
    tcpSocketRef: MutableState<Socket?>
) {
    try {
        // 建立 TCP 連線（5 秒逾時）
        val socket = Socket()
        val cleanHost = serverHost
            .substringBefore('%')  // 移除 IPv6 zone ID
            .removePrefix("::ffff:")  // 移除 IPv4-mapped IPv6
        Log.d("RadioScreen", "[LGAP] Connecting TCP to $cleanHost:$TCP_STREAM_PORT")
        socket.connect(InetSocketAddress(cleanHost, TCP_STREAM_PORT), 5000)
        socket.tcpNoDelay = true  // 減少延遲
        tcpSocketRef.value = socket
        val outputStream = socket.getOutputStream()
        Log.d("RadioScreen", "[LGAP] ✅ TCP connected")

        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(3200) // at least 0.1s buffer

        val audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        audioRecordRef.value = audioRecord
        audioRecord.startRecording()

        // 每次讀取 ~0.1 秒（1600 samples = 3200 bytes），即時感更強
        val chunkSamples = 1600
        val pcmBuffer = ByteArray(chunkSamples * 2)
        var packetCount = 0

        while (audioRecord.recordingState == AudioRecord.RECORDSTATE_RECORDING && !socket.isClosed) {
            val bytesRead = audioRecord.read(pcmBuffer, 0, pcmBuffer.size)
            if (bytesRead <= 0) continue

            // 組裝 LGAP 封包: magic(4 LE) + payloadLen(4 LE) + PCM data
            val packet = ByteArray(8 + bytesRead)
            // Magic - little-endian
            packet[0] = (LGAP_MAGIC and 0xFF).toByte()
            packet[1] = (LGAP_MAGIC shr 8 and 0xFF).toByte()
            packet[2] = (LGAP_MAGIC shr 16 and 0xFF).toByte()
            packet[3] = (LGAP_MAGIC shr 24 and 0xFF).toByte()
            // Payload length - little-endian
            packet[4] = (bytesRead and 0xFF).toByte()
            packet[5] = (bytesRead shr 8 and 0xFF).toByte()
            packet[6] = (bytesRead shr 16 and 0xFF).toByte()
            packet[7] = (bytesRead shr 24 and 0xFF).toByte()
            // PCM data
            System.arraycopy(pcmBuffer, 0, packet, 8, bytesRead)

            outputStream.write(packet)
            outputStream.flush()
            packetCount++

            if (packetCount == 1) {
                Log.d("RadioScreen", "[LGAP] 📡 First packet sent: $bytesRead bytes PCM")
            } else if (packetCount % 50 == 0) {
                Log.d("RadioScreen", "[LGAP] 📊 Packets sent: $packetCount")
            }
        }
        Log.d("RadioScreen", "[LGAP] Stream ended. Total packets: $packetCount")
    } catch (e: Exception) {
        Log.e("RadioScreen", "[LGAP] TCP audio stream error: ${e.message}")
    }
}

private fun stopTcpAudioStream(
    audioRecordRef: MutableState<AudioRecord?>,
    tcpSocketRef: MutableState<Socket?>,
    streamingJob: MutableState<kotlinx.coroutines.Job?>
) {
    streamingJob.value?.cancel()
    streamingJob.value = null
    try { audioRecordRef.value?.stop() } catch (_: Exception) {}
    try { audioRecordRef.value?.release() } catch (_: Exception) {}
    audioRecordRef.value = null
    try { tcpSocketRef.value?.close() } catch (_: Exception) {}
    tcpSocketRef.value = null
}

// MARK: - 固定會報

@Composable
private fun BriefingContent(viewModel: LinkGuardViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val radioReports by viewModel.radioReports.collectAsState()
    val nodeStatus by viewModel.nodeStatus.collectAsState()
    val victims by viewModel.victims.collectAsState()
    val decisions by viewModel.decisions.collectAsState()

    var isRecording by remember { mutableStateOf(false) }
    var isUploading by remember { mutableStateOf(false) }
    var uploadMessage by remember { mutableStateOf<String?>(null) }
    var uploadSuccess by remember { mutableStateOf(false) }
    var lastTranscription by remember { mutableStateOf<String?>(null) }
    var recorder by remember { mutableStateOf<android.media.MediaRecorder?>(null) }
    var recordFile by remember { mutableStateOf<File?>(null) }
    var locationDesc by remember { mutableStateOf("") }

    // Recording timer
    var recordingStartTime by remember { mutableStateOf(0L) }
    var elapsedSeconds by remember { mutableIntStateOf(0) }

    // GPS location
    var lastLat by remember { mutableDoubleStateOf(0.0) }
    var lastLon by remember { mutableDoubleStateOf(0.0) }

    // Fetch GPS on composition
    LaunchedEffect(Unit) {
        try {
            val fusedClient = com.google.android.gms.location.LocationServices
                .getFusedLocationProviderClient(context)
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED
            ) {
                fusedClient.lastLocation.addOnSuccessListener { loc ->
                    if (loc != null) {
                        lastLat = loc.latitude
                        lastLon = loc.longitude
                    }
                }
            }
        } catch (_: Exception) {}
    }

    // Recording elapsed timer
    LaunchedEffect(isRecording) {
        if (isRecording) {
            recordingStartTime = System.currentTimeMillis()
            while (isRecording) {
                elapsedSeconds = ((System.currentTimeMillis() - recordingStartTime) / 1000).toInt()
                kotlinx.coroutines.delay(500)
            }
        } else {
            elapsedSeconds = 0
        }
    }

    // Recording pulse animation
    val pulseAlpha by animateFloatAsState(
        targetValue = if (isRecording) 0.3f else 0f,
        animationSpec = if (isRecording) infiniteRepeatable(
            tween(800, easing = LinearEasing), RepeatMode.Reverse
        ) else tween(300),
        label = "pulse"
    )

    // 錄音按鈕動畫
    val briefingButtonColor by animateColorAsState(
        targetValue = if (isRecording) NV.danger else NV.command,
        animationSpec = tween(200),
        label = "briefingColor"
    )
    val briefingScale by animateFloatAsState(
        targetValue = if (isRecording) 1.1f else 1f,
        animationSpec = spring(dampingRatio = 0.5f, stiffness = 300f),
        label = "briefingScale"
    )

    // Cleanup recorder on dispose
    DisposableEffect(Unit) {
        onDispose {
            try { recorder?.stop() } catch (_: Exception) {}
            try { recorder?.release() } catch (_: Exception) {}
        }
    }

    var hasRecordPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        )
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasRecordPermission = granted }

    // Get latest weather from decisions (if available)
    val weatherSnapshot = remember(decisions) {
        decisions.firstOrNull()?.weather
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // 錄音控制區
        Column(
            modifier = Modifier.fillMaxWidth().padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // 位置描述輸入
            OutlinedTextField(
                value = locationDesc,
                onValueChange = { locationDesc = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("位置描述（選填）", color = NV.textSecondary.copy(alpha = 0.6f)) },
                leadingIcon = { Icon(Icons.Default.LocationOn, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(18.dp)) },
                singleLine = true,
                enabled = !isRecording && !isUploading,
                textStyle = LocalTextStyle.current.copy(fontSize = 14.sp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = NV.white,
                    unfocusedTextColor = NV.white,
                    focusedBorderColor = NV.command,
                    unfocusedBorderColor = NV.cardBorder
                )
            )

            Spacer(Modifier.height(16.dp))

            // 錄音按鈕
            Button(
                onClick = {
                    if (isRecording) {
                        // 停止錄音
                        try {
                            recorder?.stop()
                            recorder?.release()
                        } catch (_: Exception) {}
                        recorder = null
                        isRecording = false

                        // 自動上傳
                        val file = recordFile ?: return@Button
                        isUploading = true
                        uploadMessage = null
                        lastTranscription = null
                        scope.launch {
                            val result = uploadBriefing(
                                file = file,
                                senderName = nodeStatus.nodeID,
                                victims = victims,
                                serverHost = viewModel.commandClient.serverHost,
                                locationDesc = locationDesc,
                                lat = lastLat,
                                lon = lastLon,
                                weatherSnapshot = weatherSnapshot
                            )
                            isUploading = false
                            uploadSuccess = result.success
                            uploadMessage = result.message
                            lastTranscription = result.transcription
                        }
                    } else {
                        // 開始錄音
                        if (!hasRecordPermission) {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            return@Button
                        }
                        val f = File(context.cacheDir, "briefing_${System.currentTimeMillis()}.m4a")
                        recordFile = f
                        val mr = android.media.MediaRecorder(context).apply {
                            setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                            setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                            setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                            setAudioSamplingRate(16000)
                            setAudioChannels(1)
                            setOutputFile(f.absolutePath)
                            prepare()
                            start()
                        }
                        recorder = mr
                        isRecording = true
                        uploadMessage = null
                        lastTranscription = null
                    }
                },
                modifier = Modifier
                    .size(100.dp)
                    .graphicsLayer {
                        scaleX = briefingScale
                        scaleY = briefingScale
                    }
                    .shadow(
                        if (isRecording) 18.dp else 6.dp,
                        CircleShape, ambientColor = briefingButtonColor
                    ),
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = briefingButtonColor
                ),
                enabled = !isUploading
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        if (isRecording) Icons.Default.Stop else Icons.Default.FiberManualRecord,
                        contentDescription = null,
                        modifier = Modifier.size(36.dp),
                        tint = if (isRecording) NV.textOnColor else Color.White
                    )
                    Text(
                        if (isRecording) "停止" else "錄音",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isRecording) NV.textOnColor else Color.White
                    )
                }
            }

            // 錄音計時器
            if (isRecording) {
                Spacer(Modifier.height(8.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(
                        Modifier.size(8.dp).clip(CircleShape)
                            .background(NV.danger.copy(alpha = 0.5f + pulseAlpha))
                    )
                    Text(
                        String.format("%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = NV.danger
                    )
                }
            }

            // 上傳進度
            if (isUploading) {
                Spacer(Modifier.height(12.dp))
                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                Text("正在上傳會報...", fontSize = 12.sp, color = NV.textSecondary)
            }

            // 上傳結果
            uploadMessage?.let { msg ->
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(
                        if (uploadSuccess) Icons.Default.CheckCircle else Icons.Default.Error,
                        contentDescription = null,
                        tint = if (uploadSuccess) NV.green else NV.danger,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(msg, fontSize = 12.sp, color = if (uploadSuccess) NV.green else NV.danger)
                }

                // 轉錄結果
                if (uploadSuccess && lastTranscription != null) {
                    Spacer(Modifier.height(8.dp))
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                        )
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text("語音轉錄", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.Gray)
                            Spacer(Modifier.height(4.dp))
                            Text(lastTranscription!!, fontSize = 13.sp, lineHeight = 18.sp)
                        }
                    }
                }

                // 重試按鈕（失敗時）
                if (!uploadSuccess) {
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = {
                            val file = recordFile ?: return@OutlinedButton
                            isUploading = true
                            uploadMessage = null
                            lastTranscription = null
                            scope.launch {
                                val result = uploadBriefing(
                                    file = file,
                                    senderName = nodeStatus.nodeID,
                                    victims = victims,
                                    serverHost = viewModel.commandClient.serverHost,
                                    locationDesc = locationDesc,
                                    lat = lastLat,
                                    lon = lastLon,
                                    weatherSnapshot = weatherSnapshot
                                )
                                isUploading = false
                                uploadSuccess = result.success
                                uploadMessage = result.message
                                lastTranscription = result.transcription
                            }
                        },
                        modifier = Modifier.height(32.dp)
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("重試", fontSize = 12.sp)
                    }
                }
            }
        }

        @Suppress("DEPRECATION")
        Divider()

        // 報告列表
        if (radioReports.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Description, contentDescription = null,
                        modifier = Modifier.size(40.dp), tint = NV.textSecondary.copy(alpha = 0.5f))
                    Spacer(Modifier.height(8.dp))
                    Text("尚無會報紀錄", fontSize = 14.sp, color = NV.textSecondary)
                }
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(radioReports.take(20)) { report ->
                    ReportItem(report)
                }
            }
        }
    }
}

@Composable
private fun ReportItem(report: RadioReport) {
    var expanded by remember { mutableStateOf(false) }
    val fmt = remember { SimpleDateFormat("HH:mm:ss", Locale.getDefault()) }

    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
        colors = CardDefaults.cardColors(containerColor = NV.card),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Person, contentDescription = null, tint = NV.command, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(report.senderName, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                Text(fmt.format(Date(report.timestamp)), fontSize = 11.sp, color = NV.textSecondary)
            }
            if (report.location.isNotEmpty()) {
                Row(modifier = Modifier.padding(top = 2.dp)) {
                    Icon(Icons.Default.LocationOn, contentDescription = null, modifier = Modifier.size(12.dp), tint = NV.textSecondary)
                    Text(report.location, fontSize = 11.sp, color = NV.textSecondary)
                }
            }
            if (report.transcription.isNotEmpty()) {
                Text(
                    report.transcription,
                    fontSize = 12.sp,
                    maxLines = if (expanded) Int.MAX_VALUE else 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 4.dp).fillMaxWidth()
                        .pointerInput(Unit) {
                            awaitEachGesture {
                                val down = awaitFirstDown(requireUnconsumed = false)
                                val up = waitForUpOrCancellation()
                                if (up != null) expanded = !expanded
                            }
                        }
                )
            }
            Text("ID: ${report.reportId}", fontSize = 10.sp, color = NV.textSecondary.copy(alpha = 0.7f),
                modifier = Modifier.padding(top = 2.dp))
        }
    }
}

// 上傳結果
private data class BriefingUploadResult(
    val success: Boolean,
    val message: String,
    val transcription: String? = null
)

// 上傳會報
private suspend fun uploadBriefing(
    file: File,
    senderName: String,
    victims: List<com.linkguard.app.model.VictimNode>,
    serverHost: String,
    locationDesc: String = "",
    lat: Double = 0.0,
    lon: Double = 0.0,
    weatherSnapshot: com.linkguard.app.model.WeatherSnapshot? = null
): BriefingUploadResult = withContext(Dispatchers.IO) {
    try {
        val victimsArr = JSONArray()
        for (v in victims.take(50)) {
            victimsArr.put(JSONObject().apply {
                put("id", v.id); put("heartRate", v.heartRate)
                put("isSOS", v.isSOS); put("isOnline", v.isOnline)
            })
        }

        val host = serverHost.ifEmpty {
            return@withContext BriefingUploadResult(false, "未連線指揮中心，無法上傳會報")
        }

        // Handle IPv6 addresses
        val urlHost = if (host.contains(":") && !host.startsWith("[")) "[$host]" else host

        val weatherJson = if (weatherSnapshot != null) {
            JSONObject().apply {
                weatherSnapshot.temp?.let { put("temp", it) }
                weatherSnapshot.humidity?.let { put("humidity", it) }
                weatherSnapshot.wind?.let { put("wind", it) }
                weatherSnapshot.rainfall?.let { put("rainfall", it) }
            }.toString()
        } else "{}"

        val isoFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US)
        val requestBody = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("device_id", senderName)
            .addFormDataPart("sender_name", senderName)
            .addFormDataPart("location_lat", lat.toString())
            .addFormDataPart("location_lon", lon.toString())
            .addFormDataPart("location_desc", locationDesc)
            .addFormDataPart("patients_snapshot", victimsArr.toString())
            .addFormDataPart("weather_snapshot", weatherJson)
            .addFormDataPart("timestamp", isoFmt.format(Date()))
            .addFormDataPart("audio", "briefing.m4a",
                file.asRequestBody("audio/mp4".toMediaType()))
            .build()

        val request = Request.Builder()
            .url("http://$urlHost:8003/report")
            .post(requestBody)
            .build()

        val client = OkHttpClient.Builder()
            .connectTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .build()

        val response = client.newCall(request).execute()
        if (response.isSuccessful) {
            val body = response.body?.string() ?: ""
            val json = try { JSONObject(body) } catch (_: Exception) { null }
            val reportId = json?.optString("report_id", "") ?: ""
            val transcription = json?.optString("transcription", "") ?: ""
            BriefingUploadResult(
                success = true,
                message = if (reportId.isNotEmpty()) "上傳成功 (ID: $reportId)" else "上傳成功",
                transcription = transcription.ifEmpty { null }
            )
        } else {
            BriefingUploadResult(false, "伺服器錯誤 (${response.code})")
        }
    } catch (e: Exception) {
        Log.e("RadioScreen", "Upload failed: ${e.message}")
        BriefingUploadResult(false, "上傳失敗：${e.message}")
    }
}

// 即時廣播 PTT 上傳轉錄（source_type=live）
private suspend fun uploadLivePtt(
    file: File,
    senderName: String,
    serverHost: String
): BriefingUploadResult = withContext(Dispatchers.IO) {
    try {
        val host = serverHost.ifEmpty {
            return@withContext BriefingUploadResult(false, "未連線指揮中心")
        }
        val urlHost = if (host.contains(":") && !host.startsWith("[")) "[$host]" else host
        val isoFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US)

        val requestBody = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("device_id", senderName)
            .addFormDataPart("sender_name", senderName)
            .addFormDataPart("source_type", "live")
            .addFormDataPart("location_lat", "0")
            .addFormDataPart("location_lon", "0")
            .addFormDataPart("location_desc", "")
            .addFormDataPart("timestamp", isoFmt.format(Date()))
            .addFormDataPart("patients_snapshot", "[]")
            .addFormDataPart("weather_snapshot", "{}")
            .addFormDataPart("audio", "ptt.m4a",
                file.asRequestBody("audio/mp4".toMediaType()))
            .build()

        val request = Request.Builder()
            .url("http://$urlHost:8003/report")
            .post(requestBody)
            .build()

        val client = OkHttpClient.Builder()
            .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .build()

        val response = client.newCall(request).execute()
        if (response.isSuccessful) {
            val body = response.body?.string() ?: ""
            val json = try { JSONObject(body) } catch (_: Exception) { null }
            val transcription = json?.optString("transcription", "") ?: ""
            BriefingUploadResult(
                success = true,
                message = "轉錄完成",
                transcription = transcription.ifEmpty { null }
            )
        } else {
            BriefingUploadResult(false, "伺服器錯誤 (${response.code})")
        }
    } catch (e: Exception) {
        Log.e("RadioScreen", "PTT upload failed: ${e.message}")
        BriefingUploadResult(false, "上傳失敗：${e.message}")
    }
}

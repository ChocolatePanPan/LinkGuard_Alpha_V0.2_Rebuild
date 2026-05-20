package com.linkguard.hq.net

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.*
import java.net.ServerSocket
import java.net.Socket
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

/**
 * 輕量 HTTP 伺服器（port 8003），接收前線裝置的固定會報音頻上傳。
 * 對應 iOS Mac HQ 的 HQSpeechServer.swift。
 *
 * 流程：
 * 1. 接收  POST /report（multipart/form-data），包含 audio + metadata
 * 2. 存檔音頻至 app cache
 * 3. 立即回覆 200 JSON（非阻塞）
 * 4. 背景轉發音頻到 Windows Whisper server（port 8002）取得轉錄
 * 5. 透過 onTranscriptionComplete 回調 → HQViewModel → 廣播結果給前線裝置
 */
class HQSpeechServer(private val context: Context) {

    companion object {
        private const val TAG = "HQSpeechServer"
        private const val PORT = 8003
        private const val MAX_CONTENT_LENGTH = 30 * 1024 * 1024 // 30 MB
    }

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning

    private val _processedCount = MutableStateFlow(0)
    val processedCount: StateFlow<Int> = _processedCount

    private var serverSocket: ServerSocket? = null
    private var serverJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** Windows 後台 Whisper server host（由 HQViewModel 設定） */
    var whisperHost: String = ""

    /** 轉錄完成回調 — 在 HQViewModel 中接線 */
    var onTranscriptionComplete: ((SpeechReport) -> Unit)? = null

    private var reportSeq = 0
    private val audioDir: File by lazy {
        File(context.cacheDir, "speech_audio").also { it.mkdirs() }
    }

    // === 生命週期 ===

    fun start() {
        if (_isRunning.value) return
        serverJob = scope.launch {
            try {
                serverSocket = ServerSocket(PORT)
                _isRunning.value = true
                Log.d(TAG, "✅ HQSpeechServer 啟動於 port $PORT")

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
        _isRunning.value = false
        Log.d(TAG, "HQSpeechServer 已停止")
    }

    // === HTTP 處理 ===

    private suspend fun handleClient(socket: Socket) {
        try {
            socket.soTimeout = 30_000
            val input = socket.getInputStream().buffered()
            val output = socket.getOutputStream()

            // 讀取 HTTP 請求行
            val requestLine = readLine(input) ?: return
            val parts = requestLine.split(" ")
            if (parts.size < 3) {
                sendResponse(output, 400, """{"error":"Bad Request"}""")
                return
            }
            val method = parts[0]
            val path = parts[1]

            // 讀取 headers
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = readLine(input) ?: break
                if (line.isEmpty()) break
                val colonIdx = line.indexOf(':')
                if (colonIdx > 0) {
                    headers[line.substring(0, colonIdx).trim().lowercase()] =
                        line.substring(colonIdx + 1).trim()
                }
            }

            when {
                method == "POST" && path == "/report" -> handleReport(input, output, headers)
                method == "GET" && path == "/health" -> {
                    val json = JSONObject().apply {
                        put("status", "ok")
                        put("server", "HQSpeechServer-Android")
                        put("processed", _processedCount.value)
                    }
                    sendResponse(output, 200, json.toString())
                }
                else -> sendResponse(output, 404, """{"error":"Not Found"}""")
            }
        } catch (e: Exception) {
            Log.e(TAG, "處理連線錯誤: ${e.message}")
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    // === POST /report 處理 ===

    private suspend fun handleReport(
        input: BufferedInputStream,
        output: OutputStream,
        headers: Map<String, String>
    ) {
        val contentType = headers["content-type"] ?: ""
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0

        if (contentLength > MAX_CONTENT_LENGTH) {
            sendResponse(output, 413, """{"error":"Payload Too Large"}""")
            return
        }

        if (!contentType.contains("multipart/form-data")) {
            sendResponse(output, 400, """{"error":"Expected multipart/form-data"}""")
            return
        }

        // 提取 boundary
        val boundaryMatch = Regex("""boundary=(.+)""").find(contentType)
        val boundary = boundaryMatch?.groupValues?.get(1)?.trim()?.removeSurrounding("\"")
        if (boundary == null) {
            sendResponse(output, 400, """{"error":"Missing boundary"}""")
            return
        }

        // 讀取整個 body
        val bodyBytes = ByteArray(contentLength)
        var bytesRead = 0
        while (bytesRead < contentLength) {
            val r = input.read(bodyBytes, bytesRead, contentLength - bytesRead)
            if (r == -1) break
            bytesRead += r
        }

        // 解析 multipart
        val formFields = mutableMapOf<String, String>()
        var audioData: ByteArray? = null
        var audioFilename = "briefing.m4a"

        parseMultipart(bodyBytes, boundary, formFields) { filename, data ->
            audioFilename = filename
            audioData = data
        }

        // 產生 report ID
        reportSeq++
        val datePart = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
        val uuidPart = UUID.randomUUID().toString().take(4)
        val reportId = "RPT-$datePart-${String.format("%03d", reportSeq)}-$uuidPart"

        val senderName = formFields["sender_name"] ?: formFields["device_id"] ?: "unknown"
        val deviceId = formFields["device_id"] ?: senderName

        // 存檔音頻
        val audioFile = if (audioData != null) {
            val ext = audioFilename.substringAfterLast('.', "m4a")
            val f = File(audioDir, "$reportId.$ext")
            f.writeBytes(audioData!!)
            Log.d(TAG, "📁 音頻已存檔: ${f.name} (${audioData!!.size} bytes)")
            f
        } else null

        // 立即回覆 200（非阻塞）
        val response = JSONObject().apply {
            put("report_id", reportId)
            put("status", "accepted")
            put("engine", "whisper_remote")
        }
        sendResponse(output, 200, response.toString())
        _processedCount.value = _processedCount.value + 1
        Log.d(TAG, "✅ 收到會報 $reportId from $senderName")

        // 背景轉錄
        if (audioFile != null) {
            scope.launch {
                val transcription = transcribeViaWhisper(audioFile, senderName)
                val report = SpeechReport(
                    reportId = reportId,
                    senderName = senderName,
                    deviceId = deviceId,
                    transcription = transcription,
                    locationLat = formFields["location_lat"]?.toDoubleOrNull() ?: 0.0,
                    locationLon = formFields["location_lon"]?.toDoubleOrNull() ?: 0.0,
                    locationDesc = formFields["location_desc"] ?: "",
                    patientsSnapshot = formFields["patients_snapshot"] ?: "[]",
                    weatherSnapshot = formFields["weather_snapshot"] ?: "{}",
                    sourceType = "briefing"
                )
                withContext(Dispatchers.Main) {
                    onTranscriptionComplete?.invoke(report)
                }

                // 清理舊音頻（保留最多 100 檔）
                cleanupAudioFiles()
            }
        }
    }

    // === Whisper 遠端轉錄 ===

    private fun transcribeViaWhisper(audioFile: File, senderId: String): String {
        val host = whisperHost
        if (host.isEmpty()) {
            Log.w(TAG, "未設定 Whisper host，跳過轉錄")
            return ""
        }

        return try {
            val urlHost = if (host.contains(":") && !host.startsWith("[")) "[$host]" else host
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("file", audioFile.name,
                    audioFile.readBytes().toRequestBody("audio/mp4".toMediaType()))
                .addFormDataPart("source", "report")
                .addFormDataPart("sender_id", senderId)
                .addFormDataPart("language", "zh")
                .build()

            val request = okhttp3.Request.Builder()
                .url("http://$urlHost:8002/transcribe")
                .post(requestBody)
                .build()

            val client = OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .writeTimeout(60, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string() ?: ""
                val json = JSONObject(body)
                val text = json.optString("text", "")
                Log.d(TAG, "📝 Whisper 轉錄完成: ${text.take(50)}")
                text
            } else {
                Log.e(TAG, "Whisper 轉錄失敗: HTTP ${response.code}")
                ""
            }
        } catch (e: Exception) {
            Log.e(TAG, "Whisper 轉錄錯誤: ${e.message}")
            ""
        }
    }

    // === Multipart 解析 ===

    private fun parseMultipart(
        body: ByteArray,
        boundary: String,
        formFields: MutableMap<String, String>,
        onFile: (filename: String, data: ByteArray) -> Unit
    ) {
        val boundaryBytes = "--$boundary".toByteArray()
        val endBoundaryBytes = "--$boundary--".toByteArray()

        // 用 boundary 分割
        val parts = splitByBoundary(body, boundaryBytes)
        for (part in parts) {
            if (part.size < 4) continue

            // 找 header/body 分隔（\r\n\r\n）
            val headerEnd = findDoubleCRLF(part)
            if (headerEnd < 0) continue

            val headerStr = String(part, 0, headerEnd, Charsets.UTF_8)
            val bodyStart = headerEnd + 4
            val partBody = part.copyOfRange(bodyStart, part.size)

            // 解析 Content-Disposition
            val nameMatch = Regex("""name="([^"]+)"""").find(headerStr)
            val filenameMatch = Regex("""filename="([^"]+)"""").find(headerStr)
            val fieldName = nameMatch?.groupValues?.get(1) ?: continue

            if (filenameMatch != null) {
                // 檔案欄位
                val trimmed = trimTrailingCRLF(partBody)
                onFile(filenameMatch.groupValues[1], trimmed)
            } else {
                // 一般 form 欄位
                formFields[fieldName] = String(trimTrailingCRLF(partBody), Charsets.UTF_8).trim()
            }
        }
    }

    private fun splitByBoundary(data: ByteArray, boundary: ByteArray): List<ByteArray> {
        val parts = mutableListOf<ByteArray>()
        var searchFrom = 0
        var lastEnd = -1

        while (searchFrom < data.size) {
            val idx = indexOf(data, boundary, searchFrom)
            if (idx < 0) break

            if (lastEnd >= 0) {
                parts.add(data.copyOfRange(lastEnd, idx))
            }
            lastEnd = idx + boundary.size
            // 跳過 boundary 後的 \r\n
            if (lastEnd + 1 < data.size && data[lastEnd] == '\r'.code.toByte() && data[lastEnd + 1] == '\n'.code.toByte()) {
                lastEnd += 2
            }
            searchFrom = lastEnd
        }
        return parts
    }

    private fun indexOf(data: ByteArray, pattern: ByteArray, from: Int): Int {
        outer@ for (i in from..data.size - pattern.size) {
            for (j in pattern.indices) {
                if (data[i + j] != pattern[j]) continue@outer
            }
            return i
        }
        return -1
    }

    private fun findDoubleCRLF(data: ByteArray): Int {
        for (i in 0..data.size - 4) {
            if (data[i] == '\r'.code.toByte() && data[i + 1] == '\n'.code.toByte()
                && data[i + 2] == '\r'.code.toByte() && data[i + 3] == '\n'.code.toByte()) {
                return i
            }
        }
        return -1
    }

    private fun trimTrailingCRLF(data: ByteArray): ByteArray {
        var end = data.size
        while (end > 0 && (data[end - 1] == '\r'.code.toByte() || data[end - 1] == '\n'.code.toByte())) {
            end--
        }
        return if (end == data.size) data else data.copyOfRange(0, end)
    }

    // === 清理 ===

    private fun cleanupAudioFiles() {
        try {
            val files = audioDir.listFiles() ?: return
            if (files.size > 100) {
                files.sortedBy { it.lastModified() }
                    .take(files.size - 100)
                    .forEach { it.delete() }
            }
        } catch (_: Exception) {}
    }

    // === HTTP 工具 ===

    private fun readLine(input: InputStream): String? {
        val sb = StringBuilder()
        while (true) {
            val b = input.read()
            if (b == -1) return if (sb.isEmpty()) null else sb.toString()
            if (b == '\n'.code) {
                // 移除尾部 \r
                if (sb.isNotEmpty() && sb[sb.length - 1] == '\r') sb.deleteCharAt(sb.length - 1)
                return sb.toString()
            }
            sb.append(b.toChar())
        }
    }

    private fun sendResponse(output: OutputStream, statusCode: Int, body: String) {
        val statusText = when (statusCode) {
            200 -> "OK"
            400 -> "Bad Request"
            404 -> "Not Found"
            413 -> "Payload Too Large"
            500 -> "Internal Server Error"
            else -> "Unknown"
        }
        val bodyBytes = body.toByteArray(Charsets.UTF_8)
        val response = buildString {
            append("HTTP/1.1 $statusCode $statusText\r\n")
            append("Content-Type: application/json; charset=utf-8\r\n")
            append("Content-Length: ${bodyBytes.size}\r\n")
            append("Connection: close\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("\r\n")
        }
        output.write(response.toByteArray(Charsets.UTF_8))
        output.write(bodyBytes)
        output.flush()
    }
}

/** 轉錄完成的報告結構 */
data class SpeechReport(
    val reportId: String,
    val senderName: String,
    val deviceId: String,
    val transcription: String,
    val locationLat: Double = 0.0,
    val locationLon: Double = 0.0,
    val locationDesc: String = "",
    val patientsSnapshot: String = "[]",
    val weatherSnapshot: String = "{}",
    val sourceType: String = "briefing"
)

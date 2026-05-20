package com.linkguard.hq.net

import android.util.Log
import com.linkguard.hq.model.HQDecision
import com.linkguard.hq.model.HQPatientWarning
import com.linkguard.hq.model.HQTranslationResult
import com.linkguard.hq.model.PatientDecisionEntry
import com.linkguard.hq.model.PhotoAlert
import com.linkguard.hq.model.SOSAlert
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.*
import java.net.InetSocketAddress
import java.net.Socket

/**
 * 連接 HQ App 到 win11 Backend TCP Server (port 9000)
 * 對應 iOS 版 HQBackendBridge.swift
 */
class HQBackendBridge {

    companion object {
        private const val TAG = "HQBackendBridge"
        private const val BACKEND_PORT = 9000
        private const val RECONNECT_DELAY_MS = 3000L
        private const val PING_INTERVAL_MS = 30_000L
        private const val CONNECT_TIMEOUT_MS = 5000
    }

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _backendHost = MutableStateFlow("")
    val backendHost: StateFlow<String> = _backendHost

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    private val _isRequestingAI = MutableStateFlow(false)
    val isRequestingAI: StateFlow<Boolean> = _isRequestingAI

    private val _latestAIDecision = MutableStateFlow<HQDecision?>(null)
    val latestAIDecision: StateFlow<HQDecision?> = _latestAIDecision

    private val _backendDecisions = MutableStateFlow<List<HQDecision>>(emptyList())
    val backendDecisions: StateFlow<List<HQDecision>> = _backendDecisions

    private var socket: Socket? = null
    private var writer: BufferedWriter? = null
    private var readerJob: Job? = null
    private var pingJob: Job? = null
    private var reconnectJob: Job? = null
    private var reconnectAttempt = 0
    private val maxReconnectDelay = 30_000L
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** 由 HQCommandServer 注入，用於將後台決策廣播給前線裝置 */
    var onDecisionFromBackend: ((HQDecision) -> Unit)? = null
    var onSOSFromBackend: ((SOSAlert) -> Unit)? = null
    var onPhotoAlertFromBackend: ((PhotoAlert) -> Unit)? = null
    var onPatientWarningFromBackend: ((HQPatientWarning) -> Unit)? = null
    var onTranslationResultFromBackend: ((HQTranslationResult) -> Unit)? = null
    var onWeatherUpdate: ((JSONObject) -> Unit)? = null
    var onNodeStatus: ((JSONObject) -> Unit)? = null
    var onStatsUpdate: ((JSONObject) -> Unit)? = null
    var onReportSummary: ((JSONObject) -> Unit)? = null

    // MARK: - 連線管理

    fun connect(host: String) {
        _backendHost.value = host
        _lastError.value = null
        doConnect(host)
    }

    fun disconnect() {
        reconnectJob?.cancel()
        reconnectJob = null
        pingJob?.cancel()
        pingJob = null
        readerJob?.cancel()
        readerJob = null
        closeSocket()
        _isConnected.value = false
        Log.d(TAG, "已斷開後台連線")
    }

    private fun doConnect(host: String) {
        readerJob?.cancel()
        pingJob?.cancel()
        closeSocket()

        readerJob = scope.launch {
            try {
                val s = Socket()
                s.connect(InetSocketAddress(host, BACKEND_PORT), CONNECT_TIMEOUT_MS)
                socket = s
                writer = BufferedWriter(OutputStreamWriter(s.getOutputStream(), Charsets.UTF_8))

                withContext(Dispatchers.Main) {
                    _isConnected.value = true
                    _lastError.value = null
                }
                reconnectAttempt = 0  // 連線成功重置重試計數
                Log.d(TAG, "已連接到後台 $host:$BACKEND_PORT")

                sendHello()
                startPing()

                // 讀取迴圈
                val reader = BufferedReader(InputStreamReader(s.getInputStream(), Charsets.UTF_8))
                val buffer = StringBuilder()
                val charBuf = CharArray(4096)
                while (isActive && !s.isClosed) {
                    val bytesRead = reader.read(charBuf)
                    if (bytesRead == -1) break
                    buffer.append(charBuf, 0, bytesRead)

                    while (true) {
                        val nlIdx = buffer.indexOf('\n')
                        if (nlIdx < 0) break
                        val line = buffer.substring(0, nlIdx).trim()
                        buffer.delete(0, nlIdx + 1)
                        if (line.isNotEmpty()) {
                            withContext(Dispatchers.Main) {
                                processMessage(line)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                if (isActive) {
                    Log.e(TAG, "連線失敗: ${e.message}")
                    withContext(Dispatchers.Main) {
                        _isConnected.value = false
                        _lastError.value = e.message
                    }
                }
            } finally {
                withContext(Dispatchers.Main) {
                    _isConnected.value = false
                }
                if (isActive) scheduleReconnect()
            }
        }
    }

    private fun closeSocket() {
        try { writer?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        writer = null
        socket = null
    }

    private fun scheduleReconnect() {
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            val delayMs = (RECONNECT_DELAY_MS * (1L shl reconnectAttempt.coerceAtMost(4)))
                .coerceAtMost(maxReconnectDelay)  // 3s, 6s, 12s, 24s, 30s
            reconnectAttempt++
            Log.d(TAG, "第${reconnectAttempt}次重連，${delayMs}ms 後嘗試...")
            delay(delayMs)
            val host = _backendHost.value
            if (host.isNotEmpty() && !_isConnected.value) {
                doConnect(host)
            }
        }
    }

    // MARK: - 心跳

    private fun startPing() {
        pingJob?.cancel()
        pingJob = scope.launch {
            while (isActive) {
                delay(PING_INTERVAL_MS)
                sendToBackend("ping", JSONObject())
            }
        }
    }

    // MARK: - 發送

    private fun sendHello() {
        sendToBackend("ping", JSONObject().apply {
            put("role", "hq")
            put("name", "HQ-Android")
        })
    }

    fun requestAIDecision(context: String = "") {
        if (!_isConnected.value) return
        _isRequestingAI.value = true
        sendToBackend("request_decision", JSONObject().apply {
            put("voice_text", context)
        }, deviceId = "HQ")
    }

    fun forwardPatient(patientJson: JSONObject, deviceId: String = "HQ-bridge") {
        sendToBackend("patient", patientJson, deviceId)
    }

    fun forwardVoiceResult(text: String, deviceId: String) {
        sendToBackend("voice_result", JSONObject().apply {
            put("text", text)
        }, deviceId)
    }

    private fun sendToBackend(type: String, data: JSONObject, deviceId: String = "HQ") {
        if (!_isConnected.value) return
        scope.launch {
            try {
                val msg = JSONObject().apply {
                    put("type", type)
                    put("data", data)
                    put("device_id", deviceId)
                    put("timestamp", java.text.SimpleDateFormat(
                        "yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US
                    ).format(java.util.Date()))
                }
                val line = msg.toString() + "\n"
                synchronized(this@HQBackendBridge) {
                    writer?.write(line)
                    writer?.flush()
                }
            } catch (e: Exception) {
                Log.e(TAG, "發送失敗: ${e.message}")
            }
        }
    }

    // MARK: - 接收處理

    private fun processMessage(line: String) {
        try {
            val json = JSONObject(line)
            val type = json.optString("type", "")
            val data = json.optJSONObject("data") ?: JSONObject()

            when (type) {
                "decision" -> handleDecision(data, json)
                "weather_update", "weather" -> onWeatherUpdate?.invoke(data)
                "node_status" -> onNodeStatus?.invoke(data)
                "stats_update" -> onStatsUpdate?.invoke(data)
                "report_summary" -> onReportSummary?.invoke(data)
                "translate_result" -> handleTranslateResult(data)
                "sos_alert" -> handleSOSAlert(data)
                "sos_cancel_alert" -> { /* handled by command server */ }
                "patient_warning" -> handlePatientWarning(data)
                "photo_alert" -> handlePhotoAlert(data)
                "pong", "ack" -> { /* 心跳回應 */ }
                else -> Log.d(TAG, "未知後台訊息: $type")
            }
        } catch (e: Exception) {
            Log.e(TAG, "解析失敗: ${e.message}")
        }
    }

    private fun handleDecision(data: JSONObject, fullJson: JSONObject) {
        val decisionText = data.optString("decision", "")
        val trigger = data.optString("trigger", "")
        val timestamp = fullJson.optString("timestamp", data.optString("timestamp", ""))

        val patients = mutableListOf<PatientDecisionEntry>()
        val patientsArr = data.optJSONArray("patients")
        if (patientsArr != null) {
            for (i in 0 until patientsArr.length()) {
                val pj = patientsArr.getJSONObject(i)
                patients.add(PatientDecisionEntry(
                    id = pj.optString("id", ""),
                    location = pj.optString("location", ""),
                    priority = pj.optString("priority", "")
                ))
            }
        }

        val decision = HQDecision(
            decision = decisionText,
            patients = patients,
            timestamp = timestamp,
            model = data.optString("model", ""),
            escalated = data.optBoolean("escalated", false)
        )

        val current = _backendDecisions.value.toMutableList()
        current.add(0, decision)
        if (current.size > 100) _backendDecisions.value = current.take(100)
        else _backendDecisions.value = current

        _isRequestingAI.value = false
        _latestAIDecision.value = decision

        // 通知 HQCommandServer 廣播給前線
        onDecisionFromBackend?.invoke(decision)

        Log.d(TAG, "收到後台決策: $decisionText (trigger=$trigger)")
    }

    private fun handleTranslateResult(data: JSONObject) {
        val result = HQTranslationResult(
            original = data.optString("original", ""),
            translated = data.optString("translated", ""),
            sourceLang = data.optString("detected_lang", data.optString("source_lang", "")),
            targetLang = data.optString("target_lang", "")
        )
        onTranslationResultFromBackend?.invoke(result)
    }

    private fun handleSOSAlert(data: JSONObject) {
        val alert = SOSAlert(
            deviceID = data.optString("device_id", ""),
            senderName = data.optString("sender_name", ""),
            lat = data.optDouble("lat", 0.0),
            lon = data.optDouble("lon", 0.0)
        )
        onSOSFromBackend?.invoke(alert)
    }

    private fun handlePatientWarning(data: JSONObject) {
        val warning = HQPatientWarning(
            patientID = data.optString("patient_id", ""),
            deviceID = data.optString("device_id", ""),
            triageLevel = data.optString("triage_level", "")
        )
        onPatientWarningFromBackend?.invoke(warning)
    }

    private fun handlePhotoAlert(data: JSONObject) {
        val alert = PhotoAlert(
            photoID = data.optString("photo_id", ""),
            senderID = data.optString("sender_id", ""),
            senderName = data.optString("sender_name", ""),
            thumbnailUrl = data.optString("thumbnail_url", ""),
            fullUrl = data.optString("full_url", ""),
            caption = data.optString("caption", ""),
            lat = data.optDouble("lat", 0.0),
            lon = data.optDouble("lon", 0.0)
        )
        onPhotoAlertFromBackend?.invoke(alert)
    }

    // === 新增發送方法 ===

    fun sendTextBroadcast(message: String, senderName: String, priority: String = "normal") {
        sendToBackend("text_broadcast", JSONObject().apply {
            put("message", message); put("sender_name", senderName); put("priority", priority)
        })
    }

    fun sendTranslateRequest(text: String, sourceLang: String = "", targetLang: String = "zh") {
        sendToBackend("translate_request", JSONObject().apply {
            put("text", text); put("source_lang", sourceLang); put("target_lang", targetLang)
        })
    }

    fun sendPatientWarning(patientId: String, triageLevel: String) {
        sendToBackend("patient_warning", JSONObject().apply {
            put("patient_id", patientId); put("triage_level", triageLevel)
        })
    }

    fun destroy() {
        scope.cancel()
        disconnect()
    }
}

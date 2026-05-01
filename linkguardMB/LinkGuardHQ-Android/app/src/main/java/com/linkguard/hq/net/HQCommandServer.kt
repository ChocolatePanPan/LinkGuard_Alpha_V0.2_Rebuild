package com.linkguard.hq.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.linkguard.hq.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.*
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class HQCommandServer(private val context: Context) {

    companion object {
        private const val TAG = "HQCommandServer"
        private const val PORT = 8930
        private const val SERVICE_TYPE = "_linkguard-hq._tcp."
        private const val SERVICE_NAME = "LinkGuardHQ"
    }

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning

    private val _fieldUnits = MutableStateFlow<List<ConnectedFieldUnit>>(emptyList())
    val fieldUnits: StateFlow<List<ConnectedFieldUnit>> = _fieldUnits

    // HQ 同伴裝置列表
    private val _hqPeers = MutableStateFlow<List<HQPeerInfo>>(emptyList())
    val hqPeers: StateFlow<List<HQPeerInfo>> = _hqPeers

    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private var nsdManager: NsdManager? = null
    private var serverScope: CoroutineScope? = null
    private val clients = ConcurrentHashMap<String, ClientConnection>()
    // clientId → HQPeerInfo，對應 hq_peer 連線
    private val peers = ConcurrentHashMap<String, HQPeerInfo>()

    private val _chatMessages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages

    var onChatReceived: ((ChatMessage) -> Unit)? = null

    // 指揮決策列表
    private val _decisions = MutableStateFlow<List<HQDecision>>(emptyList())
    val decisions: StateFlow<List<HQDecision>> = _decisions

    var onDecisionReceived: ((HQDecision) -> Unit)? = null

    // SOS 警報列表
    private val _sosAlerts = MutableStateFlow<List<SOSAlert>>(emptyList())
    val sosAlerts: StateFlow<List<SOSAlert>> = _sosAlerts

    var onSOSReceived: ((SOSAlert) -> Unit)? = null

    // 任務指派
    private val _taskAssignments = MutableStateFlow<List<TaskAssignment>>(emptyList())
    val taskAssignments: StateFlow<List<TaskAssignment>> = _taskAssignments

    var onTaskUpdate: ((TaskAssignment) -> Unit)? = null

    // 文字廣播 & 已讀
    private val _textBroadcasts = MutableStateFlow<List<HQTextBroadcast>>(emptyList())
    val textBroadcasts: StateFlow<List<HQTextBroadcast>> = _textBroadcasts

    // 照片
    private val _photoAlerts = MutableStateFlow<List<PhotoAlert>>(emptyList())
    val photoAlerts: StateFlow<List<PhotoAlert>> = _photoAlerts

    // 電台
    private val _radioReports = MutableStateFlow<List<HQRadioReport>>(emptyList())
    val radioReports: StateFlow<List<HQRadioReport>> = _radioReports

    private val _activeBroadcaster = MutableStateFlow<RadioControlPayload?>(null)
    val activeBroadcaster: StateFlow<RadioControlPayload?> = _activeBroadcaster

    // 傷患警告
    private val _patientWarnings = MutableStateFlow<List<HQPatientWarning>>(emptyList())
    val patientWarnings: StateFlow<List<HQPatientWarning>> = _patientWarnings

    // 傷患排序（START triage 評分結果）
    private val _rankedPatients = MutableStateFlow<List<PatientDecisionEntry>>(emptyList())
    val rankedPatients: StateFlow<List<PatientDecisionEntry>> = _rankedPatients

    // 快速狀態
    private val _quickStatuses = MutableStateFlow<List<QuickStatus>>(emptyList())
    val quickStatuses: StateFlow<List<QuickStatus>> = _quickStatuses

    // 危害報告
    private val _hazardReports = MutableStateFlow<List<HazardReport>>(emptyList())
    val hazardReports: StateFlow<List<HazardReport>> = _hazardReports

    // 增援請求
    private val _reinforcementRequests = MutableStateFlow<List<ReinforcementRequest>>(emptyList())
    val reinforcementRequests: StateFlow<List<ReinforcementRequest>> = _reinforcementRequests

    // 翻譯結果
    private val _translationResults = MutableStateFlow<List<HQTranslationResult>>(emptyList())
    val translationResults: StateFlow<List<HQTranslationResult>> = _translationResults

    var onTranslationResult: ((HQTranslationResult) -> Unit)? = null

    /** 聊天已讀回條回調: (messageId, deviceID) */
    var onChatReadReceipt: ((String, String) -> Unit)? = null

    /** 前線裝置自動同步人員配置回調 */
    var onFieldPersonnelSync: ((PersonnelAssignment) -> Unit)? = null

    // 聊天已讀追蹤: messageId → Set<deviceID>
    private val chatReadTracker = ConcurrentHashMap<String, MutableSet<String>>()

    // connID → deviceID mapping for routing
    private val connDeviceMap = ConcurrentHashMap<String, String>()

    // === 聚合屬性 ===

    val allVictims: List<VictimSummary>
        get() = _fieldUnits.value.flatMap { it.victims }

    val allTeamMembers: List<TeamSummary>
        get() = _fieldUnits.value.flatMap { it.teamMembers }

    val totalSOSCount: Int
        get() = _fieldUnits.value.sumOf { it.sosCount } + _sosAlerts.value.size

    val onlineFieldUnitCount: Int
        get() = _fieldUnits.value.count { it.isOnline }

    // === 啟動 / 停止 ===

    fun start() {
        if (_isRunning.value) return

        _isRunning.value = true

        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        serverScope = scope
        scope.launch {
            try {
                serverSocket = ServerSocket(PORT)
                Log.d(TAG, "Server started on port $PORT")

                while (_isRunning.value) {
                    try {
                        val socket = serverSocket?.accept() ?: break
                        handleNewConnection(socket)
                    } catch (e: Exception) {
                        if (_isRunning.value) Log.e(TAG, "Accept error: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Server start failed: ${e.message}")
                _isRunning.value = false
            }
        }

        registerNSD()
    }

    fun stop() {
        _isRunning.value = false
        serverScope?.cancel()
        serverScope = null
        unregisterNSD()

        clients.values.forEach { it.close() }
        clients.clear()
        peers.clear()
        _hqPeers.value = emptyList()

        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        acceptThread?.interrupt()
        acceptThread = null

        _fieldUnits.value = emptyList()
    }

    // === NSD 註冊 ===

    private fun registerNSD() {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = SERVICE_NAME
            serviceType = SERVICE_TYPE
            port = PORT
        }
        nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
    }

    private fun unregisterNSD() {
        try { nsdManager?.unregisterService(registrationListener) } catch (_: Exception) {}
    }

    private val registrationListener = object : NsdManager.RegistrationListener {
        override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
            Log.d(TAG, "NSD registered: ${serviceInfo.serviceName}")
        }
        override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
            Log.e(TAG, "NSD registration failed: $errorCode")
        }
        override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
            Log.d(TAG, "NSD unregistered")
        }
        override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
            Log.e(TAG, "NSD unregistration failed: $errorCode")
        }
    }

    // === 連線處理 ===

    private fun handleNewConnection(socket: Socket) {
        val clientId = UUID.randomUUID().toString()
        val connection = ClientConnection(clientId, socket)
        clients[clientId] = connection

        val unit = ConnectedFieldUnit(id = clientId)
        _fieldUnits.value = _fieldUnits.value + unit

        Log.d(TAG, "New field unit connected: ${socket.inetAddress.hostAddress}")

        Thread {
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            val buffer = StringBuilder()
            try {
                val charBuf = CharArray(4096)
                while (!Thread.currentThread().isInterrupted && !socket.isClosed) {
                    val bytesRead = reader.read(charBuf)
                    if (bytesRead == -1) break
                    buffer.append(charBuf, 0, bytesRead)

                    while (true) {
                        val nlIdx = buffer.indexOf('\n')
                        if (nlIdx < 0) break
                        val line = buffer.substring(0, nlIdx).trim()
                        buffer.delete(0, nlIdx + 1)
                        if (line.isNotEmpty()) processMessage(clientId, line)
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Client $clientId disconnected: ${e.message}")
            } finally {
                clients.remove(clientId)
                // 清除 field unit 或 peer
                val removedPeer = peers.remove(clientId)
                if (removedPeer != null) {
                    _hqPeers.value = _hqPeers.value.filter { it.id != clientId }
                } else {
                    _fieldUnits.value = _fieldUnits.value.filter { it.id != clientId }
                }
                try { socket.close() } catch (_: Exception) {}
            }
        }.start()
    }

    private fun processMessage(clientId: String, line: String) {
        try {
            val json = JSONObject(line)
            // Support both { msgType, payload } and { type, data } formats
            val msgType = json.optString("msgType", json.optString("type", ""))
            val payload = json.optString("payload", "")
            val data = json.optJSONObject("data")

            when (msgType) {
                "hello" -> processHello(clientId, payload)
                "hq_command" -> processHQCommand(clientId, payload)
                "status_report" -> {
                    if (!peers.containsKey(clientId)) processStatusReport(clientId, payload)
                }
                "chat_message" -> processChatMessage(clientId, payload)
                "decision" -> processDecision(clientId, payload)
                "sos" -> processSOS(clientId, data ?: tryParsePayload(payload))
                "sos_cancel" -> processSOSCancel(clientId, data ?: tryParsePayload(payload))
                "task_update" -> processTaskUpdate(clientId, data ?: tryParsePayload(payload))
                "text_broadcast" -> processTextBroadcast(clientId, data ?: tryParsePayload(payload))
                "message_ack" -> processMessageAck(clientId, data ?: tryParsePayload(payload))
                "photo_alert" -> processPhotoAlert(clientId, data ?: tryParsePayload(payload))
                "radio_control" -> processRadioControl(clientId, data ?: tryParsePayload(payload))
                "radio_report" -> processRadioReport(clientId, data ?: tryParsePayload(payload))
                "patient_warning" -> processPatientWarning(clientId, data ?: tryParsePayload(payload))
                "patient_ranking" -> processPatientRanking(clientId, payload)
                "quick_status" -> processQuickStatus(clientId, data ?: tryParsePayload(payload))
                "hazard_report" -> processHazardReport(clientId, data ?: tryParsePayload(payload))
                "reinforcement_request" -> processReinforcementRequest(clientId, data ?: tryParsePayload(payload))
                "reinforcement_reply" -> processReinforcementReply(clientId, data ?: tryParsePayload(payload))
                "translate_request" -> processTranslateRequest(clientId, data ?: tryParsePayload(payload))
                "translate_result" -> processTranslateResult(clientId, data ?: tryParsePayload(payload))
                "chat_read_receipt" -> processChatReadReceipt(clientId, data ?: tryParsePayload(payload))
                "location" -> processLocation(clientId, data ?: tryParsePayload(payload))
                "report_summary" -> processReportSummary(clientId, data ?: tryParsePayload(payload))
                else -> Log.d(TAG, "Unknown message type: $msgType")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse error: ${e.message}")
        }
    }

    private fun tryParsePayload(payload: String): JSONObject {
        return if (payload.isNotEmpty()) try { JSONObject(payload) } catch (_: Exception) { JSONObject() } else JSONObject()
    }

    private fun processHello(clientId: String, payload: String) {
        if (payload.isEmpty()) return
        val json = JSONObject(payload)
        val role = json.optString("role", "field_unit")
        val peerId = json.optString("id", clientId)
        val peerName = json.optString("name", "HQ Peer")
        if (role == "hq_peer") {
            val info = HQPeerInfo(id = clientId, peerID = peerId, peerName = peerName)
            peers[clientId] = info
            _hqPeers.value = _hqPeers.value + info
            // 將目前狀態推送給新 peer
            Log.d(TAG, "HQ peer connected: $peerName ($peerId)")
        }
    }

    private fun processHQCommand(clientId: String, payload: String) {
        if (payload.isEmpty()) return
        try {
            val cmdJson = JSONObject(payload)
            val cmd = WiFiCommand(
                id = cmdJson.optString("id", UUID.randomUUID().toString()),
                type = cmdJson.optString("type", ""),
                priority = cmdJson.optInt("priority", 0),
                title = cmdJson.optString("title", ""),
                detail = cmdJson.optString("detail", ""),
                sender = cmdJson.optString("sender", "HQ Peer")
            )
            // 廣播給所有前線裝置（包含其他 peer）
            sendCommand(cmd)
            Log.d(TAG, "HQ command from peer $clientId: ${cmd.title}")
        } catch (e: Exception) {
            Log.e(TAG, "HQ command parse error: ${e.message}")
        }
    }

    private val knownVictimIds = mutableSetOf<String>()

    private fun processStatusReport(clientId: String, payload: String) {
        if (payload.isEmpty()) return
        val reportJson = JSONObject(payload)

        val deviceID = reportJson.optString("deviceID", "")
        if (deviceID.isNotEmpty()) connDeviceMap[clientId] = deviceID

        val victims = mutableListOf<VictimSummary>()
        val victimsArr = reportJson.optJSONArray("victims")
        if (victimsArr != null) {
            for (i in 0 until victimsArr.length()) {
                val vj = victimsArr.getJSONObject(i)
                val vid = vj.getString("id")
                victims.add(VictimSummary(
                    id = vid, heartRate = vj.getInt("heartRate"),
                    battery = vj.getInt("battery"), rssi = vj.getDouble("rssi"),
                    isSOS = vj.getBoolean("isSOS"), isOnline = vj.getBoolean("isOnline")
                ))
                
                // Track new victims and broadcast an alert
                if (knownVictimIds.add(vid)) {
                    val alertCmd = WiFiCommand(
                        id = UUID.randomUUID().toString(),
                        type = "alert",
                        priority = 1,
                        title = "New Victim Detected",
                        detail = "HQ received report for victim ID: $vid",
                        sender = "HQ Auto-Alert"
                    )
                    sendCommand(alertCmd)
                }
            }
        }
        val teamMembers = mutableListOf<TeamSummary>()
        val teamArr = reportJson.optJSONArray("teamMembers")
        if (teamArr != null) {
            for (i in 0 until teamArr.length()) {
                val tj = teamArr.getJSONObject(i)
                teamMembers.add(TeamSummary(
                    id = tj.getString("id"), deptCode = tj.getString("deptCode"),
                    battery = tj.getInt("battery"), rssi = tj.getDouble("rssi"),
                    isOnline = tj.getBoolean("isOnline"), victimCount = tj.getInt("victimCount")
                ))
            }
        }
        _fieldUnits.value = _fieldUnits.value.map { unit ->
            if (unit.id == clientId) unit.copy(
                deviceID = reportJson.optString("deviceID", unit.deviceID),
                deptCode = reportJson.optString("deptCode", unit.deptCode),
                battery = reportJson.optInt("battery", unit.battery),
                bleConnected = reportJson.optBoolean("bleConnected", unit.bleConnected),
                lastReport = System.currentTimeMillis(),
                victims = victims, teamMembers = teamMembers,
                sosCount = reportJson.optInt("sosCount", 0)
            ) else unit
        }

        // 自動將前線裝置註冊為救援人員
        val selfPJson = reportJson.optJSONObject("selfPersonnel")
        if (selfPJson != null) {
            val sp = PersonnelAssignment(
                id = selfPJson.optString("id", "field-$deviceID"),
                name = selfPJson.optString("name", deviceID),
                assignedZone = selfPJson.optString("assignedZone", ""),
                assignedFloor = selfPJson.optString("assignedFloor", ""),
                role = PersonnelRole.fromKey(selfPJson.optString("role", "rescue")),
                timestamp = selfPJson.optDouble("timestamp", System.currentTimeMillis() / 1000.0)
            )
            onFieldPersonnelSync?.invoke(sp)
        } else if (deviceID.isNotEmpty()) {
            // 相容舊版前線：自動建立
            val autoID = "field-$deviceID"
            onFieldPersonnelSync?.invoke(PersonnelAssignment(
                id = autoID, name = deviceID, role = PersonnelRole.RESCUE
            ))
        }
    }

    private fun processChatMessage(clientId: String, payload: String) {
        if (payload.isEmpty()) return
        try {
            val cj = JSONObject(payload)
            val mentionsList = mutableListOf<String>()
            cj.optJSONArray("mentions")?.let { arr ->
                for (i in 0 until arr.length()) mentionsList.add(arr.optString(i))
            }
            val chat = ChatMessage(
                id = cj.optString("id", UUID.randomUUID().toString()),
                senderID = cj.optString("senderID", ""),
                senderName = cj.optString("senderName", ""),
                recipientID = if (cj.has("recipientID") && !cj.isNull("recipientID")) cj.getString("recipientID") else null,
                content = cj.optString("content", ""),
                timestamp = cj.optDouble("timestamp", System.currentTimeMillis() / 1000.0),
                mentions = mentionsList
            )
            val list = _chatMessages.value.toMutableList()
            list.add(chat)
            if (list.size > 500) _chatMessages.value = list.takeLast(300) else _chatMessages.value = list
            onChatReceived?.invoke(chat)
            relayChatMessage(chat, fromClientId = clientId)
        } catch (e: Exception) {
            Log.e(TAG, "Chat parse error: ${e.message}")
        }
    }

    private fun processDecision(clientId: String, payload: String) {
        if (payload.isEmpty()) return
        try {
            val json = JSONObject(payload)
            val dataObj = json.optJSONObject("data") ?: return
            val decisionText = dataObj.optString("decision", "")
            val timestamp = json.optString("timestamp", "")
            val patientsArr = dataObj.optJSONArray("patients")
            val patients = mutableListOf<PatientDecisionEntry>()
            if (patientsArr != null) {
                for (i in 0 until patientsArr.length()) {
                    val pj = patientsArr.getJSONObject(i)
                    patients.add(PatientDecisionEntry(
                        id = pj.optString("id", pj.optString("patient_id", "")),
                        location = pj.optString("location", ""),
                        priority = pj.optString("priority", ""),
                        reason = pj.optString("reason", ""),
                        totalScore = pj.optDouble("total_score", 0.0),
                        startBonus = pj.optInt("start_bonus", 0),
                        rank = pj.optInt("rank", 0)
                    ))
                }
            }
            val decision = HQDecision(
                decision = decisionText,
                patients = patients,
                timestamp = timestamp
            )
            _decisions.value = listOf(decision) + _decisions.value
            onDecisionReceived?.invoke(decision)
            Log.d(TAG, "Decision received from $clientId: $decisionText")
        } catch (e: Exception) {
            Log.e(TAG, "Decision parse error: ${e.message}")
        }
    }

    // === SOS ===

    private fun processSOS(clientId: String, data: JSONObject) {
        val deviceID = data.optString("device_id", data.optString("sender_id", connDeviceMap[clientId] ?: clientId))
        val alert = SOSAlert(
            deviceID = deviceID,
            senderName = data.optString("sender_name", deviceID),
            lat = data.optDouble("lat", 0.0),
            lon = data.optDouble("lon", 0.0)
        )
        _sosAlerts.value = listOf(alert) + _sosAlerts.value
        onSOSReceived?.invoke(alert)
        // Relay to all devices
        val relayData = buildWiFiMessage("sos_alert", JSONObject().apply {
            put("id", alert.id); put("device_id", alert.deviceID)
            put("sender_name", alert.senderName)
            put("lat", alert.lat); put("lon", alert.lon)
            put("timestamp", alert.timestamp)
        }.toString())
        sendToDevices(relayData, null)
        Log.d(TAG, "SOS from $deviceID")
    }

    private fun processSOSCancel(clientId: String, data: JSONObject) {
        val sosId = data.optString("sos_id", data.optString("id", ""))
        if (sosId.isNotEmpty()) {
            _sosAlerts.value = _sosAlerts.value.map {
                if (it.id == sosId) it.copy(isAcknowledged = true) else it
            }
        }
        val relayData = buildWiFiMessage("sos_cancel", data.toString())
        sendToDevices(relayData, null)
    }

    fun acknowledgeSOSAlert(alertId: String) {
        _sosAlerts.value = _sosAlerts.value.map {
            if (it.id == alertId) it.copy(isAcknowledged = true) else it
        }
    }

    fun acknowledgeAllSOS() {
        _sosAlerts.value = _sosAlerts.value.map { it.copy(isAcknowledged = true) }
    }

    // === Task Update ===

    private fun processTaskUpdate(clientId: String, data: JSONObject) {
        val taskId = data.optString("id", data.optString("task_id", ""))
        val newStatus = TaskStatus.fromKey(data.optString("taskStatus", data.optString("status", "")))
        if (taskId.isEmpty()) return
        _taskAssignments.value = _taskAssignments.value.map {
            if (it.id == taskId) it.copy(status = newStatus).also { t -> onTaskUpdate?.invoke(t) } else it
        }
        // Relay
        val relayData = buildWiFiMessage("task_update", data.toString())
        sendToDevices(relayData, null)
    }

    fun sendTaskAssignment(task: TaskAssignment) {
        _taskAssignments.value = listOf(task) + _taskAssignments.value
        val payload = JSONObject().apply {
            put("id", task.id); put("title", task.title); put("detail", task.detail)
            put("assignedDeviceID", task.assignedDeviceID); put("assignedName", task.assignedName)
            put("priority", task.priority.value); put("status", task.status.key)
            put("timestamp", task.timestamp)
        }.toString()
        val data = buildWiFiMessage("task_assignment", payload)
        if (task.assignedDeviceID.isNotEmpty()) {
            sendToDevices(data, listOf(task.assignedDeviceID))
        } else {
            sendToDevices(data, null)
        }
    }

    // === Text Broadcast ===

    private fun processTextBroadcast(clientId: String, data: JSONObject) {
        val broadcast = HQTextBroadcast(
            id = data.optString("id", UUID.randomUUID().toString()),
            message = data.optString("message", ""),
            senderName = data.optString("sender_name", connDeviceMap[clientId] ?: ""),
            priority = data.optString("priority", "normal")
        )
        _textBroadcasts.value = listOf(broadcast) + _textBroadcasts.value
        // Relay
        val relayData = buildWiFiMessage("text_broadcast", data.toString())
        clients.filter { it.key != clientId }.values.forEach { it.send(relayData) }
    }

    fun sendTextBroadcast(broadcast: HQTextBroadcast) {
        _textBroadcasts.value = listOf(broadcast) + _textBroadcasts.value
        val payload = JSONObject().apply {
            put("id", broadcast.id); put("message", broadcast.message)
            put("sender_name", broadcast.senderName); put("priority", broadcast.priority)
            put("timestamp", broadcast.timestamp)
        }.toString()
        val data = buildWiFiMessage("text_broadcast", payload)
        sendToDevices(data, broadcast.targetDeviceIDs)
    }

    private fun processMessageAck(clientId: String, data: JSONObject) {
        val messageId = data.optString("message_id", data.optString("id", ""))
        val deviceID = connDeviceMap[clientId] ?: clientId
        if (messageId.isEmpty()) return
        _textBroadcasts.value = _textBroadcasts.value.map { b ->
            if (b.id == messageId) { b.readBy.add(deviceID); b } else b
        }
    }

    // === Photo Alert ===

    private fun processPhotoAlert(clientId: String, data: JSONObject) {
        val alert = PhotoAlert(
            photoID = data.optString("photo_id", ""),
            senderID = data.optString("sender_id", connDeviceMap[clientId] ?: ""),
            senderName = data.optString("sender_name", ""),
            thumbnailUrl = data.optString("thumbnail_url", ""),
            fullUrl = data.optString("full_url", ""),
            caption = data.optString("caption", ""),
            lat = data.optDouble("lat", 0.0),
            lon = data.optDouble("lon", 0.0)
        )
        _photoAlerts.value = listOf(alert) + _photoAlerts.value
        // Relay
        val relayData = buildWiFiMessage("photo_alert", data.toString())
        clients.filter { it.key != clientId }.values.forEach { it.send(relayData) }
    }

    fun injectPhotoAlert(alert: PhotoAlert) {
        _photoAlerts.value = listOf(alert) + _photoAlerts.value
    }

    // === Radio Control ===

    /** Allow external callers (e.g. HQAudioStreamServer) to set/clear the active broadcaster */
    fun setActiveBroadcaster(payload: RadioControlPayload?) {
        _activeBroadcaster.value = payload
        // Relay to all connected field units
        if (payload != null) {
            val data = JSONObject().apply {
                put("action", payload.action)
                put("sender_name", payload.senderName)
                put("device_id", payload.deviceID)
            }
            val relayData = buildWiFiMessage("radio_control", data.toString())
            clients.values.forEach { it.send(relayData) }
        }
    }

    private fun processRadioControl(clientId: String, data: JSONObject) {
        val action = data.optString("action", "")
        val senderName = data.optString("sender_name", connDeviceMap[clientId] ?: "")
        val deviceID = data.optString("device_id", connDeviceMap[clientId] ?: "")
        val payload = RadioControlPayload(action = action, senderName = senderName, deviceID = deviceID)
        _activeBroadcaster.value = if (action == "start") payload else null
        // Relay
        val relayData = buildWiFiMessage("radio_control", data.toString())
        clients.filter { it.key != clientId }.values.forEach { it.send(relayData) }
    }

    private fun processRadioReport(clientId: String, data: JSONObject) {
        val report = HQRadioReport(
            senderName = data.optString("sender_name", connDeviceMap[clientId] ?: ""),
            senderDeviceID = data.optString("device_id", connDeviceMap[clientId] ?: ""),
            transcription = data.optString("transcription", ""),
            sourceType = RadioSourceType.fromKey(data.optString("source_type", "live"))
        )
        _radioReports.value = listOf(report) + _radioReports.value
        // Relay
        val relayData = buildWiFiMessage("radio_report", data.toString())
        clients.filter { it.key != clientId }.values.forEach { it.send(relayData) }
    }

    // === Patient Warning ===

    private fun processPatientWarning(clientId: String, data: JSONObject) {
        val warning = HQPatientWarning(
            patientID = data.optString("patient_id", ""),
            deviceID = data.optString("device_id", connDeviceMap[clientId] ?: ""),
            triageLevel = data.optString("triage_level", "")
        )
        _patientWarnings.value = listOf(warning) + _patientWarnings.value
        // Relay
        val relayData = buildWiFiMessage("patient_warning", data.toString())
        sendToDevices(relayData, null)
    }

    // === Patient Ranking (START triage 評分排序) ===

    private fun processPatientRanking(clientId: String, payload: String) {
        try {
            val json = JSONObject(payload)
            val dataObj = json.optJSONObject("data") ?: return
            val patientsArr = dataObj.optJSONArray("patients") ?: return
            val ranked = mutableListOf<PatientDecisionEntry>()
            for (i in 0 until patientsArr.length()) {
                val pj = patientsArr.getJSONObject(i)
                ranked.add(PatientDecisionEntry(
                    id = pj.optString("id", pj.optString("patient_id", "")),
                    location = pj.optString("location", ""),
                    priority = pj.optString("priority", ""),
                    reason = pj.optString("reason", ""),
                    totalScore = pj.optDouble("total_score", 0.0),
                    startBonus = pj.optInt("start_bonus", 0),
                    rank = pj.optInt("rank", i + 1)
                ))
            }
            _rankedPatients.value = ranked
            Log.d(TAG, "Patient ranking received: ${ranked.size} patients from $clientId")

            // 中繼給所有前線裝置
            val relayData = buildWiFiMessage("patient_ranking", dataObj.toString())
            sendToDevices(relayData, null)
        } catch (e: Exception) {
            Log.e(TAG, "Patient ranking parse error: ${e.message}")
        }
    }

    // === Quick Status ===

    private fun processQuickStatus(clientId: String, data: JSONObject) {
        val qs = QuickStatus(
            deviceID = data.optString("device_id", connDeviceMap[clientId] ?: ""),
            type = QuickStatusType.fromKey(data.optString("type", "")),
            zone = data.optString("zone", ""),
            note = data.optString("note", "")
        )
        _quickStatuses.value = listOf(qs) + _quickStatuses.value
        // Relay
        val relayData = buildWiFiMessage("quick_status", data.toString())
        clients.filter { it.key != clientId }.values.forEach { it.send(relayData) }
    }

    // === Hazard Report ===

    private fun processHazardReport(clientId: String, data: JSONObject) {
        val report = HazardReport(
            deviceID = data.optString("device_id", connDeviceMap[clientId] ?: ""),
            hazardType = HazardType.fromKey(data.optString("hazardType", data.optString("hazard_type", ""))),
            severity = HazardSeverity.fromKey(data.optString("severity", "medium")),
            description = data.optString("description", ""),
            lat = data.optDouble("lat", 0.0),
            lon = data.optDouble("lon", 0.0)
        )
        _hazardReports.value = listOf(report) + _hazardReports.value
        // Relay
        val relayData = buildWiFiMessage("hazard_report", data.toString())
        sendToDevices(relayData, null)
    }

    // === Reinforcement ===

    private fun processReinforcementRequest(clientId: String, data: JSONObject) {
        val req = ReinforcementRequest(
            fromDeviceID = data.optString("device_id", connDeviceMap[clientId] ?: ""),
            fromTeam = data.optString("fromTeam", ""),
            message = data.optString("message", ""),
            location = data.optString("location", "")
        )
        _reinforcementRequests.value = listOf(req) + _reinforcementRequests.value
        val relayData = buildWiFiMessage("reinforcement_request", data.toString())
        sendToDevices(relayData, null)
    }

    private fun processReinforcementReply(clientId: String, data: JSONObject) {
        val reqId = data.optString("request_id", "")
        val responder = data.optString("responder", connDeviceMap[clientId] ?: "")
        val accepted = data.optBoolean("accepted", false)
        _reinforcementRequests.value = _reinforcementRequests.value.map { r ->
            if (r.id == reqId) {
                r.respondedBy.add(responder)
                r.copy(status = if (accepted) ReinforcementStatus.ACCEPTED else ReinforcementStatus.DECLINED)
            } else r
        }
        val relayData = buildWiFiMessage("reinforcement_reply", data.toString())
        sendToDevices(relayData, null)
    }

    // === Translation ===

    private fun processTranslateRequest(clientId: String, data: JSONObject) {
        // Forward to backend bridge — the ViewModel will handle this
        val relayData = buildWiFiMessage("translate_request", data.toString())
        // Not relayed to other field units; handled by backend
        Log.d(TAG, "Translate request from $clientId")
    }

    private fun processTranslateResult(clientId: String, data: JSONObject) {
        val result = HQTranslationResult(
            original = data.optString("original", ""),
            translated = data.optString("translated", ""),
            sourceLang = data.optString("detected_lang", data.optString("source_lang", "")),
            targetLang = data.optString("target_lang", "")
        )
        _translationResults.value = listOf(result) + _translationResults.value
        onTranslationResult?.invoke(result)
    }

    fun injectTranslationResult(result: HQTranslationResult) {
        _translationResults.value = listOf(result) + _translationResults.value
        onTranslationResult?.invoke(result)
    }

    // === Chat Read Receipt ===

    private fun processChatReadReceipt(clientId: String, data: JSONObject) {
        val deviceID = data.optString("device_id", connDeviceMap[clientId] ?: clientId)
        val messageIds = mutableListOf<String>()
        val idsArr = data.optJSONArray("message_ids")
        if (idsArr != null) {
            for (i in 0 until idsArr.length()) {
                messageIds.add(idsArr.getString(i))
            }
        } else {
            val singleId = data.optString("message_id", "")
            if (singleId.isNotEmpty()) messageIds.add(singleId)
        }
        for (msgId in messageIds) {
            val readers = chatReadTracker.getOrPut(msgId) { mutableSetOf() }
            if (readers.add(deviceID)) {
                onChatReadReceipt?.invoke(msgId, deviceID)
            }
        }
    }

    fun getChatReadCount(messageId: String): Int {
        return chatReadTracker[messageId]?.size ?: 0
    }

    // === Location ===

    private fun processLocation(clientId: String, data: JSONObject) {
        // Update field unit location — store in connDeviceMap metadata
        val deviceID = data.optString("device_id", connDeviceMap[clientId] ?: "")
        Log.d(TAG, "Location update from $deviceID: ${data.optDouble("lat", 0.0)}, ${data.optDouble("lon", 0.0)}")
    }

    // === Report Summary ===

    private fun processReportSummary(clientId: String, data: JSONObject) {
        val report = HQRadioReport(
            id = data.optString("report_id", UUID.randomUUID().toString()),
            senderName = data.optString("sender_name", ""),
            senderDeviceID = data.optString("device_id", ""),
            sourceType = RadioSourceType.BRIEFING,
            transcription = data.optString("transcription", "")
        )
        _radioReports.value = listOf(report) + _radioReports.value
    }

    fun broadcastPatientReport(patientJson: String) {
        val data = buildWiFiMessage("patient", patientJson)
        sendToDevices(data, null)
    }

    /** 從 HQBackendBridge 注入後台 AI 決策，加入 decisions 列表並廣播給前線 */
    fun injectDecision(decision: HQDecision) {
        _decisions.value = listOf(decision) + _decisions.value
        onDecisionReceived?.invoke(decision)

        // 廣播給所有已連線的前線裝置
        val payload = JSONObject().apply {
            put("data", JSONObject().apply {
                put("decision", decision.decision)
                put("timestamp", decision.timestamp)
                put("trigger", decision.trigger)
                put("patients", JSONArray().apply {
                    decision.patients.forEach { p ->
                        put(JSONObject().apply {
                            put("id", p.id)
                            put("location", p.location)
                            put("priority", p.priority)
                        })
                    }
                })
            })
            put("timestamp", decision.timestamp)
        }.toString()
        val data = buildWiFiMessage("decision", payload)
        sendToDevices(data, null)
    }

    private fun relayChatMessage(chat: ChatMessage, fromClientId: String) {
        val data = buildWiFiMessage("chat_message", chatToJson(chat))
        val recipientID = chat.recipientID
        if (recipientID != null) {
            val targetClientId = connDeviceMap.entries.firstOrNull { it.value == recipientID }?.key
            if (targetClientId != null) clients[targetClientId]?.send(data)
        } else {
            clients.filter { it.key != fromClientId }.values.forEach { it.send(data) }
        }
    }

    private fun chatToJson(chat: ChatMessage): String {
        return JSONObject().apply {
            put("id", chat.id); put("senderID", chat.senderID); put("senderName", chat.senderName)
            if (chat.recipientID != null) put("recipientID", chat.recipientID) else put("recipientID", JSONObject.NULL)
            put("content", chat.content); put("timestamp", chat.timestamp); put("isRead", chat.isRead)
            put("mentions", JSONArray().apply { chat.mentions.forEach { put(it) } })
        }.toString()
    }

    // === 發送命令 ===

    fun sendCommand(command: WiFiCommand, targetDeviceIDs: List<String>? = null) {
        val cmdJson = JSONObject().apply {
            put("id", command.id); put("type", command.type); put("priority", command.priority)
            put("title", command.title); put("detail", command.detail)
            put("sender", command.sender); put("timestamp", command.timestamp)
        }
        val data = buildWiFiMessage("command", cmdJson.toString())
        sendToDevices(data, targetDeviceIDs)
    }

    fun broadcastCommand(command: WiFiCommand) = sendCommand(command)

    // === 新訊息廣播 ===

    fun broadcastDisasterUpdate(siteJson: String, targetDeviceIDs: List<String>? = null) {
        val data = buildWiFiMessage("disaster_update", siteJson)
        sendToDevices(data, targetDeviceIDs)
    }

    fun broadcastPersonnelAssignment(assignmentsJson: String, targetDeviceIDs: List<String>? = null) {
        val data = buildWiFiMessage("personnel_assignment", assignmentsJson)
        sendToDevices(data, targetDeviceIDs)
    }

    fun broadcastPWSAlert(alertJson: String, targetDeviceIDs: List<String>? = null) {
        val data = buildWiFiMessage("pws_alert", alertJson)
        sendToDevices(data, targetDeviceIDs)
    }

    fun broadcastBriefing(briefingJson: String, targetDeviceIDs: List<String>? = null) {
        val data = buildWiFiMessage("briefing", briefingJson)
        sendToDevices(data, targetDeviceIDs)
    }

    fun sendPersonalNotification(notifJson: String, targetDeviceID: String) {
        val targetClientId = connDeviceMap.entries.firstOrNull { it.value == targetDeviceID }?.key
        if (targetClientId != null) {
            val data = buildWiFiMessage("personal_notification", notifJson)
            clients[targetClientId]?.send(data)
        }
    }

    fun broadcastPatientWarning(warningJson: String) {
        val data = buildWiFiMessage("patient_warning", warningJson)
        sendToDevices(data, null)
    }

    fun broadcastSOSRelay(sosJson: String) {
        val data = buildWiFiMessage("sos_alert", sosJson)
        sendToDevices(data, null)
    }

    /** 廣播會報轉錄結果給所有前線裝置（由 HQSpeechServer 回調觸發） */
    fun broadcastReportSummary(report: SpeechReport) {
        val payload = JSONObject().apply {
            put("report_id", report.reportId)
            put("sender_name", report.senderName)
            put("device_id", report.deviceId)
            put("transcription", report.transcription)
            put("timestamp", System.currentTimeMillis() / 1000.0)
            put("location_desc", report.locationDesc)
            put("source_type", report.sourceType)
        }.toString()
        val data = buildWiFiMessage("report_summary", payload)
        sendToDevices(data, null)
    }

    fun sendChatFromHQ(chat: ChatMessage) {
        val list = _chatMessages.value.toMutableList()
        list.add(chat)
        _chatMessages.value = if (list.size > 500) list.takeLast(300) else list

        val data = buildWiFiMessage("chat_message", chatToJson(chat))
        if (chat.recipientID != null) {
            val targetClientId = connDeviceMap.entries.firstOrNull { it.value == chat.recipientID }?.key
            if (targetClientId != null) clients[targetClientId]?.send(data)
        } else {
            clients.values.toList().forEach { it.send(data) }
        }
    }

    // === PADOS 統一路由 ===

    /** 統一路由：targetDeviceIDs 為 null/空 → 廣播全體（包含 peers）；有値 → 僅發送給指定裝置 */
    private fun sendToDevices(data: String, targetDeviceIDs: List<String>?) {
        if (targetDeviceIDs.isNullOrEmpty()) {
            // 廣播: 所有 field unit + 所有 peer（snapshot 避免 ConcurrentModification）
            clients.values.toList().forEach { it.send(data) }
        } else {
            val targetSet = targetDeviceIDs.toSet()
            val connSnapshot = connDeviceMap.toMap()
            for ((clientId, deviceID) in connSnapshot) {
                if (deviceID in targetSet) {
                    clients[clientId]?.send(data)
                }
            }
            // 廣播給所有 peers（不限 target）
            peers.keys.toList().forEach { peerId ->
                clients[peerId]?.send(data)
            }
        }
    }

    // === 通用 WiFiMessage 構建 ===

    private fun buildWiFiMessage(msgType: String, payloadJson: String): String {
        return JSONObject().apply {
            put("msgType", msgType)
            put("payload", payloadJson)
        }.toString() + "\n"
    }

    // === 內部連線類 ===

    private class ClientConnection(val id: String, private val socket: Socket) {
        private val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))

        fun send(data: String) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    synchronized(writer) { 
                        writer.write(data + "\n")
                        writer.flush() 
                    }
                } catch (e: Exception) {
                    Log.e("HQCommandServer", "Send to $id failed: ${e.message}")
                }
            }
        }

        fun close() {
            try { writer.close() } catch (_: Exception) {}
            try { socket.close() } catch (_: Exception) {}
        }
    }
}

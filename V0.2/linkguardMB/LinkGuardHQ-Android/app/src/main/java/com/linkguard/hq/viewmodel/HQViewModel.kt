package com.linkguard.hq.viewmodel

import android.app.Application
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.provider.Settings
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import com.linkguard.hq.audio.HQVoiceRecorder
import com.linkguard.hq.audio.TranscriptionResult
import com.linkguard.hq.model.*
import com.linkguard.hq.net.HQBackendBridge
import com.linkguard.hq.net.HQCommandServer
import com.linkguard.hq.net.HQPeerClient
import com.linkguard.hq.net.HQSpeechServer
import com.linkguard.hq.net.HQAudioStreamServer
import com.linkguard.hq.net.DiscoveredHQServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import androidx.lifecycle.viewModelScope
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class HQViewModel(application: Application) : AndroidViewModel(application) {

    // MARK: - 角色模式
    enum class HQRole { SERVER, PEER }

    private val _hqRole = MutableStateFlow(HQRole.SERVER)
    val hqRole: StateFlow<HQRole> = _hqRole

    val server = HQCommandServer(application.applicationContext)
    val peerClient = HQPeerClient(application.applicationContext)

    private var switchJob: Job? = null

    /** peer 模式看 peerClient.isConnected，server 模式看 server.isRunning */
    val isHQActive: StateFlow<Boolean> = combine(
        _hqRole, server.isRunning, peerClient.isConnected
    ) { role, serverRunning, peerConnected ->
        if (role == HQRole.PEER) peerConnected else serverRunning
    }.stateIn(viewModelScope, SharingStarted.Eagerly, false)
    val backendBridge = HQBackendBridge()
    val voiceRecorder = HQVoiceRecorder(application.applicationContext)
    val speechServer = HQSpeechServer(application.applicationContext)
    val audioStreamServer = HQAudioStreamServer(application.applicationContext)

    // 指揮決策列表（合併 server 收到的 + 後台 bridge 收到的）
    val decisions: StateFlow<List<HQDecision>> = server.decisions

    // 後台 AI 狀態
    val isRequestingAI: StateFlow<Boolean> = backendBridge.isRequestingAI
    val latestAIDecision: StateFlow<HQDecision?> = backendBridge.latestAIDecision
    val isBackendConnected: StateFlow<Boolean> = backendBridge.isConnected

    // === 語音錄製狀態 ===
    val isRecording: StateFlow<Boolean> = voiceRecorder.isRecording
    val isTranscribing: StateFlow<Boolean> = voiceRecorder.isTranscribing
    val lastTranscription: StateFlow<TranscriptionResult?> = voiceRecorder.lastTranscription
    val voiceError: StateFlow<String?> = voiceRecorder.lastError
    val recordingDurationMs: StateFlow<Long> = voiceRecorder.recordingDurationMs

    // === 聊天已讀回條追蹤 ===
    private val _chatReadCounts = MutableStateFlow<Map<String, Int>>(emptyMap())
    val chatReadCounts: StateFlow<Map<String, Int>> = _chatReadCounts

    // === 已解除 SOS 設備追蹤 ===
    private val _dismissedSOSDeviceIDs = MutableStateFlow<Set<String>>(emptySet())
    val dismissedSOSDeviceIDs: StateFlow<Set<String>> = _dismissedSOSDeviceIDs

    // === 受困者 START 檢傷理由 ===
    private val _victimTriageReasons = MutableStateFlow<Map<String, String>>(emptyMap())
    val victimTriageReasons: StateFlow<Map<String, String>> = _victimTriageReasons

    // === 後台自動發現 ===
    private val _discoveredBackends = MutableStateFlow<List<DiscoveredBackend>>(emptyList())
    val discoveredBackends: StateFlow<List<DiscoveredBackend>> = _discoveredBackends

    private val _isDiscoveringBackend = MutableStateFlow(false)
    val isDiscoveringBackend: StateFlow<Boolean> = _isDiscoveringBackend

    private var nsdManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    init {
        server.onDecisionReceived = { _ -> }
        // 後台決策回傳時，也注入到 server 的決策列表並廣播給前線
        backendBridge.onDecisionFromBackend = { decision ->
            server.injectDecision(decision)
        }
        // SOS 處理
        server.onSOSReceived = { alert ->
            val dismissed = _dismissedSOSDeviceIDs.value
            if (!dismissed.contains(alert.deviceID)) {
                _showSOSOverlay.value = server.sosAlerts.value.any { !it.isAcknowledged && !dismissed.contains(it.deviceID) }
            }
        }
        backendBridge.onSOSFromBackend = { alert ->
            // Forward backend SOS to server state
            server.acknowledgeSOSAlert("") // trigger re-evaluation (no-op for non-matching)
        }
        // 照片
        backendBridge.onPhotoAlertFromBackend = { alert ->
            server.injectPhotoAlert(alert)
        }
        // 傷患警告
        backendBridge.onPatientWarningFromBackend = { warning ->
            // Already handled by server
        }
        // 翻譯
        backendBridge.onTranslationResultFromBackend = { result ->
            server.injectTranslationResult(result)
        }
        // 聊天已讀回條
        server.onChatReadReceipt = { msgId, deviceID ->
            val current = _chatReadCounts.value.toMutableMap()
            current[msgId] = (current[msgId] ?: 0) + 1
            _chatReadCounts.value = current
        }
        // 前線裝置自動同步為救援人員
        server.onFieldPersonnelSync = { sp ->
            val current = _personnelAssignments.value.toMutableList()
            val idx = current.indexOfFirst { it.id == sp.id }
            if (idx >= 0) current[idx] = sp else current.add(sp)
            _personnelAssignments.value = current
        }
        // 語音轉錄完成 → 建立 radio report + 轉發給後台
        voiceRecorder.onTranscriptionComplete = { result ->
            addRadioReport("HQ 指揮中心", result.text, "HQ")
            backendBridge.forwardVoiceResult(result.text, "HQ")
            addTimelineEvent(TimelineEventType.CHAT, "HQ 語音轉錄：${result.text.take(30)}")
        }
        // Speech HTTP 伺服器（port 8003）接收前線會報音頻 → 轉錄 + 廣播
        speechServer.onTranscriptionComplete = { report ->
            addRadioReport(report.senderName, report.transcription, report.deviceId)
            server.broadcastReportSummary(report)
            backendBridge.forwardVoiceResult(report.transcription, report.deviceId)
            addTimelineEvent(TimelineEventType.CHAT, "收到前線會報 (${report.senderName})：${report.transcription.take(30)}")
        }
        // LGAP 即時音訊伺服器（port 8005）接收前線 PTT 音訊
        audioStreamServer.onBroadcastStateChanged = { isStart, senderId ->
            val payload = RadioControlPayload(
                action = if (isStart) "start" else "stop",
                senderName = senderId,
                deviceID = senderId
            )
            // 更新 HQ activeBroadcaster 狀態
            server.setActiveBroadcaster(if (isStart) payload else null)
        }
        audioStreamServer.onTranscriptionComplete = { senderId, transcription ->
            addRadioReport(senderId, transcription, senderId)
            backendBridge.forwardVoiceResult(transcription, senderId)
            addTimelineEvent(TimelineEventType.CHAT, "PTT 轉錄 ($senderId)：${transcription.take(30)}")
        }
        loadLocalPatients()
    }

    // 命令表單狀態
    private val _selectedType = MutableStateFlow(CommandType.STATUS_REPORT)
    val selectedType: StateFlow<CommandType> = _selectedType

    private val _selectedPriority = MutableStateFlow(CommandPriority.ROUTINE)
    val selectedPriority: StateFlow<CommandPriority> = _selectedPriority

    private val _commandTitle = MutableStateFlow("")
    val commandTitle: StateFlow<String> = _commandTitle

    private val _commandDetail = MutableStateFlow("")
    val commandDetail: StateFlow<String> = _commandDetail

    private val _senderName = MutableStateFlow("指揮中心")
    val senderName: StateFlow<String> = _senderName

    // 命令歷史
    private val _sentCommands = MutableStateFlow<List<SentCommand>>(emptyList())
    val sentCommands: StateFlow<List<SentCommand>> = _sentCommands

    val quickCommands = defaultQuickCommands

    // --- 新功能狀態 ---
    // 災害狀態
    private val _disasterSite = MutableStateFlow(DisasterSite())
    val disasterSite: StateFlow<DisasterSite> = _disasterSite

    // 聊天
    private val _chatMessages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages

    private val _chatDraft = MutableStateFlow("")
    val chatDraft: StateFlow<String> = _chatDraft

    // 人員配置
    private val _personnelAssignments = MutableStateFlow<List<PersonnelAssignment>>(emptyList())
    val personnelAssignments: StateFlow<List<PersonnelAssignment>> = _personnelAssignments

    // PWS 警報
    private val _pwsAlerts = MutableStateFlow<List<PWSAlert>>(emptyList())
    val pwsAlerts: StateFlow<List<PWSAlert>> = _pwsAlerts

    // 會報
    private val _briefings = MutableStateFlow<List<BriefingReport>>(emptyList())
    val briefings: StateFlow<List<BriefingReport>> = _briefings

    // 個人通知
    private val _personalNotifications = MutableStateFlow<List<PersonalNotification>>(emptyList())
    val personalNotifications: StateFlow<List<PersonalNotification>> = _personalNotifications

    // 事件日誌
    private val _timelineEvents = MutableStateFlow<List<TimelineEvent>>(emptyList())
    val timelineEvents: StateFlow<List<TimelineEvent>> = _timelineEvents

    // 會報儀表板（電台報告）
    private val _radioReports = MutableStateFlow<List<RadioReport>>(emptyList())
    val radioReports: StateFlow<List<RadioReport>> = _radioReports

    // === 新增功能狀態 ===

    // SOS 警報
    val sosAlerts: StateFlow<List<SOSAlert>> = server.sosAlerts
    private val _showSOSOverlay = MutableStateFlow(false)
    val showSOSOverlay: StateFlow<Boolean> = _showSOSOverlay

    // 任務指派
    val taskAssignments: StateFlow<List<TaskAssignment>> = server.taskAssignments

    // 倒數計時器
    private val _countdownTimers = MutableStateFlow<List<CountdownTimerModel>>(emptyList())
    val countdownTimers: StateFlow<List<CountdownTimerModel>> = _countdownTimers
    private val timerJobs = mutableMapOf<String, Job>()
    private val timerScope = CoroutineScope(Dispatchers.Main)

    // 文字廣播
    val textBroadcasts: StateFlow<List<HQTextBroadcast>> = server.textBroadcasts

    // 傷患警告
    val patientWarnings: StateFlow<List<HQPatientWarning>> = server.patientWarnings

    // 電台報告（新版）
    val hqRadioReports: StateFlow<List<HQRadioReport>> = server.radioReports
    val activeBroadcaster: StateFlow<RadioControlPayload?> = server.activeBroadcaster

    // 照片
    val photoAlerts: StateFlow<List<PhotoAlert>> = server.photoAlerts

    // 快速狀態
    val quickStatuses: StateFlow<List<QuickStatus>> = server.quickStatuses

    // 危害報告
    val hazardReports: StateFlow<List<HazardReport>> = server.hazardReports

    // 增援請求
    val reinforcementRequests: StateFlow<List<ReinforcementRequest>> = server.reinforcementRequests

    // 翻譯結果
    val translationResults: StateFlow<List<HQTranslationResult>> = server.translationResults

    // 物資管理
    private val _resourceItems = MutableStateFlow<List<ResourceItem>>(emptyList())
    val resourceItems: StateFlow<List<ResourceItem>> = _resourceItems

    // 本地傷患回報（持久化）
    private val _localPatients = MutableStateFlow<List<PatientReport>>(emptyList())
    val localPatients: StateFlow<List<PatientReport>> = _localPatients

    // PADOS 多裝置目標選擇
    enum class TargetMode { BROADCAST, SELECTED }
    private val _targetMode = MutableStateFlow(TargetMode.BROADCAST)
    val targetMode: StateFlow<TargetMode> = _targetMode
    private val _selectedTargetDeviceIDs = MutableStateFlow<Set<String>>(emptySet())
    val selectedTargetDeviceIDs: StateFlow<Set<String>> = _selectedTargetDeviceIDs

    val effectiveTargetIDs: List<String>?
        get() = if (_targetMode.value == TargetMode.BROADCAST) null
                else _selectedTargetDeviceIDs.value.toList()

    fun setTargetMode(mode: TargetMode) { _targetMode.value = mode }
    fun toggleTargetDevice(deviceID: String) {
        val current = _selectedTargetDeviceIDs.value.toMutableSet()
        if (current.contains(deviceID)) current.remove(deviceID) else current.add(deviceID)
        _selectedTargetDeviceIDs.value = current
    }
    fun selectAllDevices() {
        _selectedTargetDeviceIDs.value = server.fieldUnits.value.map { it.deviceID }.toSet()
    }
    fun deselectAllDevices() { _selectedTargetDeviceIDs.value = emptySet() }

    // MARK: - 受困者總覽（含優先級、處置狀態）

    private val _victimPriorities = MutableStateFlow<Map<String, VictimPriority>>(emptyMap())
    val victimPriorities: StateFlow<Map<String, VictimPriority>> = _victimPriorities

    private val _victimNotes = MutableStateFlow<Map<String, String>>(emptyMap())
    val victimNotes: StateFlow<Map<String, String>> = _victimNotes

    private val _victimStatuses = MutableStateFlow<Map<String, VictimStatus>>(emptyMap())
    val victimStatuses: StateFlow<Map<String, VictimStatus>> = _victimStatuses

    private val _victimDescriptions = MutableStateFlow<Map<String, String>>(emptyMap())
    val victimDescriptions: StateFlow<Map<String, String>> = _victimDescriptions

    fun allVictimRecords(): List<HQVictimRecord> {
        val seen = mutableSetOf<String>()
        val records = mutableListOf<HQVictimRecord>()
        val priorities = _victimPriorities.value
        val notes = _victimNotes.value
        val statuses = _victimStatuses.value
        val descriptions = _victimDescriptions.value
        for (unit in server.fieldUnits.value) {
            for (v in unit.victims) {
                if (seen.add(v.id)) {
                    records.add(HQVictimRecord(
                        id = v.id, heartRate = v.heartRate, battery = v.battery,
                        rssi = v.rssi, isSOS = v.isSOS, isOnline = v.isOnline,
                        sourceDeviceID = unit.deviceID, sourceDeptCode = unit.deptCode,
                        priority = priorities[v.id] ?: VictimPriority.UNSET,
                        status = statuses[v.id] ?: VictimStatus.PENDING,
                        note = notes[v.id] ?: "",
                        description = descriptions[v.id] ?: ""
                    ))
                }
            }
        }
        return records
    }

    fun setVictimPriority(victimID: String, priority: VictimPriority) {
        _victimPriorities.value = _victimPriorities.value.toMutableMap().apply { put(victimID, priority) }
    }

    fun setVictimNote(victimID: String, note: String) {
        _victimNotes.value = _victimNotes.value.toMutableMap().apply { put(victimID, note) }
    }

    fun setVictimStatus(victimID: String, status: VictimStatus) {
        _victimStatuses.value = _victimStatuses.value.toMutableMap().apply { put(victimID, status) }
    }

    fun setVictimDescription(victimID: String, desc: String) {
        _victimDescriptions.value = _victimDescriptions.value.toMutableMap().apply { put(victimID, desc) }
    }

    // === 操作 ===

    fun setSelectedType(type: CommandType) { _selectedType.value = type }
    fun setSelectedPriority(priority: CommandPriority) { _selectedPriority.value = priority }
    fun setCommandTitle(title: String) { _commandTitle.value = title }
    fun setCommandDetail(detail: String) { _commandDetail.value = detail }
    fun setSenderName(name: String) { _senderName.value = name }
    fun setChatDraft(text: String) { _chatDraft.value = text }

    fun toggleServer() {
        if (_hqRole.value == HQRole.PEER) return
        if (server.isRunning.value) {
            server.stop()
            speechServer.stop()
            audioStreamServer.stop()
        } else {
            server.start()
            speechServer.whisperHost = backendBridge.backendHost.value
            speechServer.start()
            audioStreamServer.whisperHost = backendBridge.backendHost.value
            audioStreamServer.start()
        }
    }

    fun switchRole(role: HQRole) {
        if (_hqRole.value == role) return
        // 取消先前切換操作，防止快速點擊競爭
        switchJob?.cancel()
        _hqRole.value = role
        switchJob = viewModelScope.launch(Dispatchers.IO) {
            try {
                if (role == HQRole.SERVER) {
                    peerClient.disconnect()
                    peerClient.stopBrowsing()
                    // 切回 Server 時重新啟動伺服器
                    if (!server.isRunning.value) {
                        server.start()
                    }
                } else {
                    server.stop()
                    peerClient.startBrowsing()
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("HQViewModel", "switchRole error: ${e.message}")
            }
        }
    }

    fun connectToPeer(target: DiscoveredHQServer) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                peerClient.connect(target)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e("HQViewModel", "connectToPeer error: ${e.message}")
            }
        }
    }

    fun sendCustomCommand() {
        val title = _commandTitle.value.trim()
        if (title.isEmpty()) return

        val cmd = WiFiCommand(
            type = _selectedType.value.key,
            priority = _selectedPriority.value.value,
            title = title,
            detail = _commandDetail.value.trim(),
            sender = _senderName.value.trim().ifEmpty { "指揮中心" }
        )

        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendCommand(cmd)
        } else {
            server.sendCommand(cmd, effectiveTargetIDs)
        }

        _sentCommands.value = listOf(SentCommand(
            id = cmd.id,
            type = _selectedType.value,
            priority = _selectedPriority.value,
            title = title,
            detail = _commandDetail.value.trim(),
            sender = cmd.sender
        )) + _sentCommands.value

        _commandTitle.value = ""
        _commandDetail.value = ""
    }

    fun sendQuickCommand(qc: QuickCommand) {
        val cmd = WiFiCommand(
            type = qc.type.key,
            priority = qc.priority.value,
            title = qc.title,
            detail = qc.detail,
            sender = _senderName.value.trim().ifEmpty { "指揮中心" }
        )
        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendCommand(cmd)
        } else {
            server.sendCommand(cmd, effectiveTargetIDs)
        }

        _sentCommands.value = listOf(SentCommand(
            id = cmd.id,
            type = qc.type,
            priority = qc.priority,
            title = qc.title,
            detail = qc.detail,
            sender = cmd.sender
        )) + _sentCommands.value
    }

    // === 聊天 ===

    fun sendChat(text: String) {
        val content = text.trim()
        if (content.isEmpty()) return
        val sn = _senderName.value.trim().ifEmpty { "指揮中心" }
        // 解析 @提及：對應到 personnel.id
        val mentions = parseMentionsFromText(content)
        val msg = ChatMessage(
            senderID = "HQ", senderName = sn, content = content,
            mentions = mentions
        )
        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendChat(msg)
        } else {
            server.sendChatFromHQ(msg)
            // 本地新增
            _chatMessages.value = _chatMessages.value + msg
        }
        _chatDraft.value = ""
    }

    private fun chatToJson(c: ChatMessage): String {
        return JSONObject().apply {
            put("id", c.id)
            put("senderID", c.senderID)
            put("senderName", c.senderName)
            if (c.recipientID != null) put("recipientID", c.recipientID)
            put("content", c.content)
            put("timestamp", c.timestamp)
            put("isRead", c.isRead)
            put("mentions", JSONArray().apply { c.mentions.forEach { put(it) } })
        }.toString()
    }

    /** 從訊息文字中提取 @ 提及，對比 personnelAssignments 的 nickname/name/id，返回 personnel.id 列表 */
    private fun parseMentionsFromText(text: String): List<String> {
        if (!text.contains('@')) return emptyList()
        val tokens = Regex("@([\\u4e00-\\u9fa5A-Za-z0-9_\\-]{1,20})").findAll(text).map { it.groupValues[1] }.toList()
        if (tokens.isEmpty()) return emptyList()
        val plist = _personnelAssignments.value
        val out = mutableListOf<String>()
        for (tok in tokens) {
            val hit = plist.firstOrNull { it.nickname == tok }
                ?: plist.firstOrNull { it.name == tok }
                ?: plist.firstOrNull { it.id == tok }
                ?: plist.firstOrNull { it.id.endsWith(tok) && tok.length >= 3 }
            if (hit != null && hit.id !in out) out.add(hit.id)
        }
        return out
    }

    // === 災害狀態 ===

    fun updateDisasterSite(site: DisasterSite) {
        _disasterSite.value = site
        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendRaw("disaster_update", disasterSiteToJson(site))
        } else {
            server.broadcastDisasterUpdate(disasterSiteToJson(site), effectiveTargetIDs)
        }
    }

    private fun disasterSiteToJson(s: DisasterSite): String {
        return JSONObject().apply {
            put("buildingName", s.buildingName)
            put("address", s.address)
            put("collapseType", s.collapseType.key)
            put("aboveGroundFloors", s.aboveGroundFloors)
            put("undergroundFloors", s.undergroundFloors)
            put("floors", JSONArray().apply {
                s.floors.forEach { f ->
                    put(JSONObject().apply {
                        put("id", f.id); put("condition", f.condition.key); put("note", f.note)
                    })
                }
            })
            put("zones", JSONArray().apply {
                s.zones.forEach { z ->
                    put(JSONObject().apply {
                        put("id", z.id); put("name", z.name); put("status", z.status.key)
                        put("assignedPersonnel", JSONArray().apply { z.assignedPersonnel.forEach { put(it) } })
                        put("note", z.note)
                    })
                }
            })
            put("hazards", JSONArray().apply { s.hazards.forEach { put(it.key) } })
            put("entryPoints", JSONArray().apply {
                s.entryPoints.forEach { e ->
                    put(JSONObject().apply {
                        put("id", e.id); put("name", e.name)
                        put("description", e.description)
                        put("isAccessible", e.isAccessible)
                    })
                }
            })
            put("rallyPoint", s.rallyPoint)
            put("note", s.note)
        }.toString()
    }

    // === 人員配置 ===

    fun assignPersonnel(assignment: PersonnelAssignment) {
        val current = _personnelAssignments.value.toMutableList()
        val idx = current.indexOfFirst { it.id == assignment.id }
        if (idx >= 0) current[idx] = assignment else current.add(assignment)
        _personnelAssignments.value = current
        server.broadcastPersonnelAssignment(JSONObject().apply {
            put("id", assignment.id)
            put("name", assignment.name); put("role", assignment.role.key)
            put("assignedZone", assignment.assignedZone)
            put("assignedFloor", assignment.assignedFloor)
            put("timestamp", assignment.timestamp)
        }.toString(), effectiveTargetIDs)
    }

    // === PWS 警報 ===

    fun addPWSAlert(alert: PWSAlert) {
        _pwsAlerts.value = listOf(alert) + _pwsAlerts.value
        server.broadcastPWSAlert(JSONObject().apply {
            put("id", alert.id); put("alertType", alert.alertType.key)
            put("severity", alert.severity.key); put("title", alert.title)
            put("content", alert.content); put("publisher", alert.publisher)
            put("publishTime", alert.publishTime); put("isActive", alert.isActive)
        }.toString(), effectiveTargetIDs)
    }

    fun deactivatePWSAlert(id: String) {
        _pwsAlerts.value = _pwsAlerts.value.map {
            if (it.id == id) it.copy(isActive = false) else it
        }
    }

    // === 會報 ===

    fun addBriefing(report: BriefingReport) {
        _briefings.value = listOf(report) + _briefings.value
        server.broadcastBriefing(JSONObject().apply {
            put("id", report.id); put("type", report.type.key)
            put("title", report.title); put("author", report.author)
            put("sections", JSONArray().apply {
                report.sections.forEach { s ->
                    put(JSONObject().apply { put("title", s.title); put("content", s.content) })
                }
            })
            put("timestamp", report.timestamp)
        }.toString(), effectiveTargetIDs)
    }

    // === 個人通知 ===

    fun sendNotification(notification: PersonalNotification) {
        _personalNotifications.value = listOf(notification) + _personalNotifications.value
        server.sendPersonalNotification(JSONObject().apply {
            put("id", notification.id); put("targetDeviceID", notification.targetDeviceID)
            put("title", notification.title); put("content", notification.content)
            put("timestamp", notification.timestamp)
            put("isRead", notification.isRead)
        }.toString(), notification.targetDeviceID)
    }

    override fun onCleared() {
        super.onCleared()
        server.stop()
        speechServer.stop()
        audioStreamServer.stop()
        peerClient.disconnect()
        peerClient.stopBrowsing()
        backendBridge.destroy()
        voiceRecorder.destroy()
        stopBackendDiscovery()
        timerJobs.values.forEach { it.cancel() }
    }

    // === SOS ===

    fun acknowledgeSOSAlert(alertId: String) {
        server.acknowledgeSOSAlert(alertId)
        _showSOSOverlay.value = server.sosAlerts.value.any { !it.isAcknowledged }
    }

    fun acknowledgeAllSOS() {
        server.acknowledgeAllSOS()
        _showSOSOverlay.value = false
    }

    // === 任務指派 ===

    fun sendTaskAssignment(title: String, detail: String, assignedDeviceID: String, assignedName: String, priority: CommandPriority) {
        val task = TaskAssignment(
            title = title, detail = detail,
            assignedDeviceID = assignedDeviceID, assignedName = assignedName,
            priority = priority
        )
        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendTaskAssignment(task)
        } else {
            server.sendTaskAssignment(task)
        }
        addTimelineEvent(TimelineEventType.COMMAND, "任務指派：$title → $assignedName")
    }

    // === 倒數計時器 ===

    fun startCountdown(label: String, durationSeconds: Int, targetDeviceID: String? = null) {
        val timer = CountdownTimerModel(
            label = label, durationSeconds = durationSeconds,
            remainingSeconds = durationSeconds, targetDeviceID = targetDeviceID, isRunning = true
        )
        _countdownTimers.value = _countdownTimers.value + timer

        // Broadcast to field
        val payload = JSONObject().apply {
            put("id", timer.id); put("label", label); put("durationSeconds", durationSeconds)
        }.toString()
        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendTimerStart(timer.id, label, durationSeconds)
        } else {
            server.broadcastDisasterUpdate(payload, if (targetDeviceID != null) listOf(targetDeviceID) else null)
        }

        val job = timerScope.launch {
            while (true) {
                delay(1000)
                val current = _countdownTimers.value.find { it.id == timer.id } ?: break
                if (!current.isRunning || current.remainingSeconds <= 0) break
                _countdownTimers.value = _countdownTimers.value.map {
                    if (it.id == timer.id) it.copy(remainingSeconds = it.remainingSeconds - 1)
                    else it
                }
            }
            _countdownTimers.value = _countdownTimers.value.map {
                if (it.id == timer.id) it.copy(isRunning = false) else it
            }
        }
        timerJobs[timer.id] = job
    }

    fun stopCountdown(timerId: String) {
        timerJobs[timerId]?.cancel()
        timerJobs.remove(timerId)
        _countdownTimers.value = _countdownTimers.value.map {
            if (it.id == timerId) it.copy(isRunning = false) else it
        }
        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendTimerCancel(timerId)
        }
    }

    fun removeCountdown(timerId: String) {
        stopCountdown(timerId)
        _countdownTimers.value = _countdownTimers.value.filter { it.id != timerId }
    }

    // === 文字廣播 ===

    fun sendTextBroadcast(message: String, priority: String = "normal") {
        val sn = _senderName.value.trim().ifEmpty { "指揮中心" }
        val broadcast = HQTextBroadcast(
            message = message, senderName = sn, priority = priority,
            targetDeviceIDs = effectiveTargetIDs
        )
        server.sendTextBroadcast(broadcast)
        backendBridge.sendTextBroadcast(message, sn, priority)
        addTimelineEvent(TimelineEventType.CHAT, "文字廣播：${message.take(30)}")
    }

    // === 後台 AI 決策 ===

    fun connectBackend(host: String) {
        backendBridge.connect(host)
        speechServer.whisperHost = host
        audioStreamServer.whisperHost = host
    }

    fun disconnectBackend() {
        backendBridge.disconnect()
    }

    fun requestAIDecision(context: String = "") {
        backendBridge.requestAIDecision(context)
    }

    // === 傷員回報 ===

    fun sendPatientReport(report: PatientReport) {
        val androidId = Settings.Secure.getString(
            getApplication<Application>().contentResolver,
            Settings.Secure.ANDROID_ID
        ) ?: "unknown"
        val dataObj = JSONObject().apply {
            put("id", report.patient_id)
            put("breathing_rate", report.breathing_rate)
            put("capillary_refill", report.capillary_refill)
            put("can_follow_commands", report.can_follow_commands)
            put("location", report.location)
        }
        val payload = JSONObject().apply {
            put("type", "patient")
            put("data", dataObj)
            put("device_id", androidId)
        }.toString()
        if (_hqRole.value == HQRole.PEER) {
            peerClient.sendRaw("patient", payload)
        } else {
            server.broadcastPatientReport(payload)
        }
        // 持久化到本地
        _localPatients.value = _localPatients.value + report
        saveLocalPatients()
    }

    private fun saveLocalPatients() {
        val prefs = getApplication<Application>()
            .getSharedPreferences("linkguard_hq_prefs", Application.MODE_PRIVATE)
        val arr = JSONArray()
        _localPatients.value.forEach { p ->
            arr.put(JSONObject().apply {
                put("patient_id", p.patient_id)
                put("location", p.location)
                put("breathing_rate", p.breathing_rate)
                put("capillary_refill", p.capillary_refill)
                put("can_follow_commands", p.can_follow_commands)
            })
        }
        prefs.edit().putString("local_patients", arr.toString()).apply()
    }

    private fun loadLocalPatients() {
        val prefs = getApplication<Application>()
            .getSharedPreferences("linkguard_hq_prefs", Application.MODE_PRIVATE)
        val json = prefs.getString("local_patients", null) ?: return
        try {
            val arr = JSONArray(json)
            val list = mutableListOf<PatientReport>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                list.add(PatientReport(
                    patient_id = o.getString("patient_id"),
                    location = o.getString("location"),
                    breathing_rate = o.getInt("breathing_rate"),
                    capillary_refill = o.getDouble("capillary_refill"),
                    can_follow_commands = o.getBoolean("can_follow_commands")
                ))
            }
            _localPatients.value = list
        } catch (_: Exception) {}
    }

    // === 事件日誌 ===

    fun addTimelineEvent(type: TimelineEventType, title: String, detail: String = "") {
        _timelineEvents.value = listOf(TimelineEvent(eventType = type, title = title, detail = detail)) + _timelineEvents.value
    }

    fun clearTimeline() { _timelineEvents.value = emptyList() }

    // === 分區地圖 ===

    fun addZone(name: String) {
        val site = _disasterSite.value
        val newZone = RescueZone(name = name)
        updateDisasterSite(site.copy(zones = site.zones + newZone))
        addTimelineEvent(TimelineEventType.DISASTER, "新增分區：$name")
    }

    fun updateZoneStatus(zoneId: String, status: ZoneStatus) {
        val site = _disasterSite.value
        val updated = site.zones.map { if (it.id == zoneId) it.copy(status = status) else it }
        updateDisasterSite(site.copy(zones = updated))
        addTimelineEvent(TimelineEventType.DISASTER, "分區狀態更新：${status.label}")
    }

    fun removeZone(zoneId: String) {
        val site = _disasterSite.value
        val zone = site.zones.find { it.id == zoneId }
        updateDisasterSite(site.copy(zones = site.zones.filter { it.id != zoneId }))
        addTimelineEvent(TimelineEventType.DISASTER, "移除分區：${zone?.name ?: zoneId}")
    }

    // === 樓層管理 ===

    fun generateFloors(above: Int, below: Int) {
        val floors = mutableListOf<FloorStatus>()
        for (i in below downTo 1) floors.add(FloorStatus(id = "B$i"))
        for (i in 1..above) floors.add(FloorStatus(id = "${i}F"))
        val site = _disasterSite.value.copy(
            aboveGroundFloors = above, undergroundFloors = below, floors = floors
        )
        updateDisasterSite(site)
    }

    fun updateFloorCondition(floorId: String, condition: FloorCondition) {
        val site = _disasterSite.value
        val updated = site.floors.map { if (it.id == floorId) it.copy(condition = condition) else it }
        updateDisasterSite(site.copy(floors = updated))
    }

    // === 危害管理 ===

    fun toggleHazard(hazard: HazardType) {
        val site = _disasterSite.value
        val current = site.hazards.toMutableList()
        if (current.contains(hazard)) current.remove(hazard) else current.add(hazard)
        updateDisasterSite(site.copy(hazards = current))
    }

    // === 進入點管理 ===

    fun addEntryPoint(name: String, description: String) {
        val site = _disasterSite.value
        val ep = EntryPoint(name = name, description = description)
        updateDisasterSite(site.copy(entryPoints = site.entryPoints + ep))
        addTimelineEvent(TimelineEventType.DISASTER, "新增進入點：$name")
    }

    fun removeEntryPoint(epId: String) {
        val site = _disasterSite.value
        updateDisasterSite(site.copy(entryPoints = site.entryPoints.filter { it.id != epId }))
    }

    fun toggleEntryPointAccessible(epId: String) {
        val site = _disasterSite.value
        val updated = site.entryPoints.map {
            if (it.id == epId) it.copy(isAccessible = !it.isAccessible) else it
        }
        updateDisasterSite(site.copy(entryPoints = updated))
    }

    // === 分區危害標記 ===

    fun toggleZoneHazard(zoneId: String, hazard: HazardType) {
        val site = _disasterSite.value
        val updated = site.zones.map { zone ->
            if (zone.id == zoneId) {
                val hazards = zone.hazards.toMutableList()
                if (hazards.contains(hazard)) hazards.remove(hazard) else hazards.add(hazard)
                zone.copy(hazards = hazards)
            } else zone
        }
        updateDisasterSite(site.copy(zones = updated))
    }

    fun updateZoneNote(zoneId: String, note: String) {
        val site = _disasterSite.value
        val updated = site.zones.map { if (it.id == zoneId) it.copy(note = note) else it }
        updateDisasterSite(site.copy(zones = updated))
    }

    // === 物資管理 ===

    fun addResourceItem(name: String, total: Int, available: Int) {
        _resourceItems.value = _resourceItems.value + ResourceItem(name = name, total = total, available = available)
    }

    fun removeResourceItem(id: String) {
        _resourceItems.value = _resourceItems.value.filter { it.id != id }
    }

    fun updateResourceItem(id: String, total: Int, available: Int) {
        _resourceItems.value = _resourceItems.value.map {
            if (it.id == id) it.copy(total = total, available = available) else it
        }
    }

    // === 會報儀表板 ===

    fun addRadioReport(senderName: String, transcription: String, deviceID: String = "") {
        _radioReports.value = listOf(RadioReport(senderName = senderName, transcription = transcription, senderDeviceID = deviceID)) + _radioReports.value
        addTimelineEvent(TimelineEventType.CHAT, "收到會報：$senderName")
    }

    // === 語音錄製 → Whisper 上傳 ===

    fun startVoiceRecording() {
        voiceRecorder.whisperHost = backendBridge.backendHost.value
        voiceRecorder.deviceId = "HQ-Android"
        voiceRecorder.startRecording()
    }

    fun stopVoiceRecording() {
        voiceRecorder.stopRecording()
    }

    // === 自動 START 檢傷 ===

    fun autoStartTriage(report: PatientReport): Pair<VictimPriority, String> {
        return when {
            report.breathing_rate == -1 ->
                VictimPriority.LOW to "START 黑色：無呼吸"
            report.breathing_rate > 30 ->
                VictimPriority.CRITICAL to "START 紅色：呼吸 >30 次/分"
            report.capillary_refill > 2.0 || report.capillary_refill == -1.0 ->
                VictimPriority.CRITICAL to "START 紅色：微血管回填 >2 秒或無脈搏"
            !report.can_follow_commands ->
                VictimPriority.CRITICAL to "START 紅色：無法遵從指令"
            else ->
                VictimPriority.LOW to "START 綠色：三項檢查正常"
        }
    }

    fun applyAutoTriage(victimID: String, report: PatientReport) {
        val (priority, reason) = autoStartTriage(report)
        // 僅在使用者未手動覆寫時自動設定
        if ((_victimPriorities.value[victimID] ?: VictimPriority.UNSET) == VictimPriority.UNSET) {
            setVictimPriority(victimID, priority)
        }
        _victimTriageReasons.value = _victimTriageReasons.value.toMutableMap().apply {
            put(victimID, reason)
        }
    }

    // === 已解除 SOS 設備追蹤 ===

    fun dismissSOSDevice(deviceID: String) {
        _dismissedSOSDeviceIDs.value = _dismissedSOSDeviceIDs.value + deviceID
        // 重新評估 overlay
        _showSOSOverlay.value = server.sosAlerts.value.any {
            !it.isAcknowledged && !_dismissedSOSDeviceIDs.value.contains(it.deviceID)
        }
    }

    fun resetDismissedSOSDevices() {
        _dismissedSOSDeviceIDs.value = emptySet()
    }

    // === 後台自動發現 (NSD/mDNS) ===

    fun startBackendDiscovery() {
        if (_isDiscoveringBackend.value) return
        _isDiscoveringBackend.value = true
        _discoveredBackends.value = emptyList()

        val mgr = getApplication<Application>()
            .getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return
        nsdManager = mgr

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                Log.d("HQViewModel", "NSD discovery started for $serviceType")
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                Log.d("HQViewModel", "NSD found: ${serviceInfo.serviceName}")
                mgr.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(si: NsdServiceInfo, errorCode: Int) {
                        Log.e("HQViewModel", "NSD resolve failed: $errorCode")
                    }

                    override fun onServiceResolved(si: NsdServiceInfo) {
                        val host = si.host?.hostAddress ?: return
                        val port = si.port
                        val backend = DiscoveredBackend(
                            name = si.serviceName,
                            host = host,
                            port = port
                        )
                        _discoveredBackends.value = _discoveredBackends.value + backend
                        Log.d("HQViewModel", "NSD resolved: $host:$port")
                    }
                })
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                _discoveredBackends.value = _discoveredBackends.value.filter {
                    it.name != serviceInfo.serviceName
                }
            }

            override fun onDiscoveryStopped(serviceType: String) {
                _isDiscoveringBackend.value = false
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                _isDiscoveringBackend.value = false
                Log.e("HQViewModel", "NSD start failed: $errorCode")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e("HQViewModel", "NSD stop failed: $errorCode")
            }
        }

        mgr.discoverServices("_linkguard-backend._tcp.", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
    }

    fun stopBackendDiscovery() {
        try {
            discoveryListener?.let { nsdManager?.stopServiceDiscovery(it) }
        } catch (_: Exception) {}
        discoveryListener = null
        _isDiscoveringBackend.value = false
    }

    fun connectToDiscoveredBackend(backend: DiscoveredBackend) {
        stopBackendDiscovery()
        connectBackend(backend.host)
    }
}

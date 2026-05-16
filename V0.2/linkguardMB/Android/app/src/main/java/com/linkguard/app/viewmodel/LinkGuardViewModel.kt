package com.linkguard.app.viewmodel

import android.app.Application
import android.content.Context
import android.os.BatteryManager
import android.util.Log
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.linkguard.app.ble.BluetoothManager
import com.linkguard.app.ble.DiscoveredDevice
import com.linkguard.app.data.PersistenceManager
import com.linkguard.app.engine.*
import com.linkguard.app.model.*
import com.linkguard.app.net.CommandClient
import com.linkguard.app.ui.theme.NV
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.update
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.launch
import java.util.*

class LinkGuardViewModel(application: Application) : AndroidViewModel(application) {

    // === 狀態 ===

    private val _victims = MutableStateFlow<List<VictimNode>>(emptyList())
    val victims: StateFlow<List<VictimNode>> = _victims

    private val _sosRecords = MutableStateFlow<List<SOSRecord>>(emptyList())
    val sosRecords: StateFlow<List<SOSRecord>> = _sosRecords

    private val _nodeStatus = MutableStateFlow(RescueNodeStatus(
        nodeID = persistentNodeID(application),
        deptCode = persistentDeptCode(application)
    ))
    val nodeStatus: StateFlow<RescueNodeStatus> = _nodeStatus

    companion object {
        /** 自動產生並持久化裝置 ID（格式 RT-XXX），LoRa 連線後由韌體覆蓋 */
        private fun persistentNodeID(app: Application): String {
            val prefs = app.getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
            val custom = prefs.getString("linkguard_custom_node_id", null)
            if (!custom.isNullOrEmpty()) return custom
            val key = "linkguard_node_hex_id"
            val saved = prefs.getString(key, null)
            if (saved != null) return "RT-$saved"
            val hex = String.format("%03X", (0..0xFFF).random())
            prefs.edit().putString(key, hex).apply()
            return "RT-$hex"
        }

        private fun persistentDeptCode(app: Application): String {
            val prefs = app.getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
            return prefs.getString("linkguard_dept_code", null) ?: "EMT"
        }
    }

    private val startTimeMs = System.currentTimeMillis()
    private val _uptimeSeconds = MutableStateFlow(0)
    val uptimeSeconds: StateFlow<Int> = _uptimeSeconds

    // 省電：狀態差異上報
    private var lastReportedBattery = -1
    private var lastReportedBLE: Boolean? = null
    private var lastReportedVictimCount = -1
    private var lastReportedSOSCount = -1

    private val _latestSOSVictim = MutableStateFlow<VictimNode?>(null)
    val latestSOSVictim: StateFlow<VictimNode?> = _latestSOSVictim

    // 模擬
    private val _isSimulating = MutableStateFlow(false)
    val isSimulating: StateFlow<Boolean> = _isSimulating

    // 命令
    private val _commandOrders = MutableStateFlow<List<CommandOrder>>(emptyList())
    val commandOrders: StateFlow<List<CommandOrder>> = _commandOrders

    private val _latestCriticalCommand = MutableStateFlow<CommandOrder?>(null)
    val latestCriticalCommand: StateFlow<CommandOrder?> = _latestCriticalCommand

    // 團隊
    private val _teamMembers = MutableStateFlow<List<TeamMember>>(emptyList())
    val teamMembers: StateFlow<List<TeamMember>> = _teamMembers

    // 增援
    private val _reinforcementRequests = MutableStateFlow<List<ReinforcementRequest>>(emptyList())
    val reinforcementRequests: StateFlow<List<ReinforcementRequest>> = _reinforcementRequests

    private val _latestReinforcementRequest = MutableStateFlow<ReinforcementRequest?>(null)
    val latestReinforcementRequest: StateFlow<ReinforcementRequest?> = _latestReinforcementRequest

    // HQ 決策
    private val _decisions = MutableStateFlow<List<HQDecision>>(emptyList())
    val decisions: StateFlow<List<HQDecision>> = _decisions

    // --- 新功能狀態 ---
    // 災害狀態（從 HQ 接收）
    private val _disasterSite = MutableStateFlow<DisasterSite?>(null)
    val disasterSite: StateFlow<DisasterSite?> = _disasterSite

    // 聊天訊息
    private val _chatMessages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages

    // 人員配置（從 HQ 接收）
    private val _personnelAssignments = MutableStateFlow<List<PersonnelAssignment>>(emptyList())
    val personnelAssignments: StateFlow<List<PersonnelAssignment>> = _personnelAssignments

    // PWS 警報（從 HQ 接收）
    private val _pwsAlerts = MutableStateFlow<List<PWSAlert>>(emptyList())
    val pwsAlerts: StateFlow<List<PWSAlert>> = _pwsAlerts

    // 會報（從 HQ 接收）
    private val _briefings = MutableStateFlow<List<BriefingReport>>(emptyList())
    val briefings: StateFlow<List<BriefingReport>> = _briefings

    // 個人通知
    private val _personalNotifications = MutableStateFlow<List<PersonalNotification>>(emptyList())
    val personalNotifications: StateFlow<List<PersonalNotification>> = _personalNotifications

    private val _unreadNotificationCount = MutableStateFlow(0)
    val unreadNotificationCount: StateFlow<Int> = _unreadNotificationCount

    // WiFi 命令模式
    private val _isWiFiCommandMode = MutableStateFlow(false)
    val isWiFiCommandMode: StateFlow<Boolean> = _isWiFiCommandMode

    // 快速狀態回報
    private val _quickStatuses = MutableStateFlow<List<QuickStatus>>(emptyList())
    val quickStatuses: StateFlow<List<QuickStatus>> = _quickStatuses

    // 任務指派
    private val _tasks = MutableStateFlow<List<TaskAssignment>>(emptyList())
    val tasks: StateFlow<List<TaskAssignment>> = _tasks

    // 倒數計時器
    private val _countdownTimers = MutableStateFlow<List<CountdownTimerModel>>(emptyList())
    val countdownTimers: StateFlow<List<CountdownTimerModel>> = _countdownTimers
    private var countdownRefreshTimer: Timer? = null

    // 危險標記
    private val _hazardReports = MutableStateFlow<List<HazardReport>>(emptyList())
    val hazardReports: StateFlow<List<HazardReport>> = _hazardReports

    // 電台會報
    private val _radioReports = MutableStateFlow<List<RadioReport>>(emptyList())
    val radioReports: StateFlow<List<RadioReport>> = _radioReports

    private val _currentBroadcaster = MutableStateFlow<String?>(null)
    val currentBroadcaster: StateFlow<String?> = _currentBroadcaster

    // TCP SOS
    private val _tcpSOSActive = MutableStateFlow(false)
    val tcpSOSActive: StateFlow<Boolean> = _tcpSOSActive

    private val _tcpSOSId = MutableStateFlow<String?>(null)
    val tcpSOSId: StateFlow<String?> = _tcpSOSId

    private val _incomingTCPSOS = MutableStateFlow<TCPSOSAlert?>(null)
    val incomingTCPSOS: StateFlow<TCPSOSAlert?> = _incomingTCPSOS

    // 照片回報
    private val _photoReports = MutableStateFlow<List<PhotoReport>>(emptyList())
    val photoReports: StateFlow<List<PhotoReport>> = _photoReports

    // 資源狀態
    private val _resourceStatus = MutableStateFlow<ResourceStatus?>(null)
    val resourceStatus: StateFlow<ResourceStatus?> = _resourceStatus

    // 統計快照
    private val _latestStats = MutableStateFlow<org.json.JSONObject?>(null)
    val latestStats: StateFlow<org.json.JSONObject?> = _latestStats

    // 文字廣播
    private val _textBroadcasts = MutableStateFlow<List<TextBroadcast>>(emptyList())
    val textBroadcasts: StateFlow<List<TextBroadcast>> = _textBroadcasts

    private val _urgentBroadcast = MutableStateFlow<TextBroadcast?>(null)
    val urgentBroadcast: StateFlow<TextBroadcast?> = _urgentBroadcast

    // 本地傷患回報（持久化）
    private val _localPatients = MutableStateFlow<List<PatientReport>>(emptyList())
    val localPatients: StateFlow<List<PatientReport>> = _localPatients

    // 傷患惡化預警
    private val _patientWarnings = MutableStateFlow<List<PatientWarning>>(emptyList())
    val patientWarnings: StateFlow<List<PatientWarning>> = _patientWarnings

    private val _activePatientWarning = MutableStateFlow<PatientWarning?>(null)
    val activePatientWarning: StateFlow<PatientWarning?> = _activePatientWarning

    // 翻譯結果
    private val _latestTranslation = MutableStateFlow<TranslationResult?>(null)
    val latestTranslation: StateFlow<TranslationResult?> = _latestTranslation

    // 翻譯狀態（進行中 / 錯誤）
    private val _isTranslating = MutableStateFlow(false)
    val isTranslating: StateFlow<Boolean> = _isTranslating
    private val _translationError = MutableStateFlow<String?>(null)
    val translationError: StateFlow<String?> = _translationError

    // 已讀回條
    private val _readStatuses = MutableStateFlow<Map<String, Pair<Int, Int>>>(emptyMap())
    val readStatuses: StateFlow<Map<String, Pair<Int, Int>>> = _readStatuses

    // === NFC 讀取 ===
    private val _nfcScanResult = MutableStateFlow<NfcScanResult?>(null)
    val nfcScanResult: StateFlow<NfcScanResult?> = _nfcScanResult

    private val _isNfcAvailable = MutableStateFlow(false)
    val isNfcAvailable: StateFlow<Boolean> = _isNfcAvailable

    // === AI 助理 ===
    private val _aiChatMessages = MutableStateFlow<List<FieldAIMessage>>(emptyList())
    val aiChatMessages: StateFlow<List<FieldAIMessage>> = _aiChatMessages

    private val _isAISending = MutableStateFlow(false)
    val isAISending: StateFlow<Boolean> = _isAISending

    private val _isAIServicePaused = MutableStateFlow(false)
    val isAIServicePaused: StateFlow<Boolean> = _isAIServicePaused

    // === 統一活動日誌 ===
    private val _activityLog = MutableStateFlow<List<ActivityLogEntry>>(emptyList())
    val activityLog: StateFlow<List<ActivityLogEntry>> = _activityLog

    // === GPS 城市（醫院目錄使用） ===
    private val _gpsCity = MutableStateFlow<String?>(null)
    val gpsCity: StateFlow<String?> = _gpsCity

    // === USAR 指揮角色（從 personnelAssignments 及 nodeStatus 中派生） ===
    val usarRole: StateFlow<UsarRole> by lazy {
        combine(_personnelAssignments, _nodeStatus) { assignments, node ->
            val myAssignment = assignments.firstOrNull { it.id == node.nodeID || it.name == node.nodeID }
            if (myAssignment != null) UsarRole.fromPersonnelRole(myAssignment.role)
            else UsarRole.SQUAD_LEADER
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UsarRole.SQUAD_LEADER)
    }

    // BLE
    val bluetoothManager = BluetoothManager(application.applicationContext)

    // WiFi 指揮中心
    val commandClient = CommandClient(application.applicationContext)

    // 引擎
    private val simulation = SimulationEngine()
    private val commandEngine = CommandEngine()
    private val notificationManager = LinkGuardNotificationManager(application.applicationContext)

    // 計時器
    private var statusReportTimer: Timer? = null
    private var locationTimer: Timer? = null
    private var simulationTimer: Timer? = null
    private var commandTimer: Timer? = null
    private var sosAutoDowngradeTimer: Timer? = null

    // GPS 靜止偵測（省電）
    private var lastGpsLat: Double? = null
    private var lastGpsLon: Double? = null
    private var stationaryCount = 0
    private var locationIntervalMs = 30_000L
    private val stationaryThresholdMeters = 10.0
    private val stationaryCountThreshold = 3

    // SQLite 持久化
    private val persistence = PersistenceManager.getInstance(application)

    // 入門引導
    private val _isOnboardingComplete = MutableStateFlow(
        application.getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
            .getBoolean("onboarding_complete", false)
    )
    val isOnboardingComplete: StateFlow<Boolean> = _isOnboardingComplete

    fun completeOnboarding(role: String, deptCode: String) {
        val prefs = getApplication<Application>()
            .getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("onboarding_complete", true)
            .putString("linkguard_dept_code", deptCode.ifEmpty { "EMT" })
            .putString("linkguard_role", role)
            .apply()
        _isOnboardingComplete.value = true
        // Update nodeStatus with new dept code
        _nodeStatus.update { it.copy(deptCode = deptCode.ifEmpty { "EMT" }) }
    }

    // 外觀模式（system / light / dark）— 預設跟隨系統
    private val _themeMode = MutableStateFlow(
        com.linkguard.app.ui.theme.ThemeMode.fromPref(
            application.getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
                .getString("theme_mode", "system")
        )
    )
    val themeMode: StateFlow<com.linkguard.app.ui.theme.ThemeMode> = _themeMode

    fun setThemeMode(mode: com.linkguard.app.ui.theme.ThemeMode) {
        getApplication<Application>()
            .getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
            .edit()
            .putString("theme_mode", mode.toPref())
            .apply()
        _themeMode.value = mode
    }

    // 離線/低電量追蹤
    private val previousOnlineStates = mutableMapOf<String, Boolean>()
    private val lowBatteryNotified = mutableSetOf<String>()

    // === 計算屬性 ===

    val onlineVictimCount: Int get() = _victims.value.count { it.isOnline }
    val sosVictimCount: Int get() = _victims.value.count { it.isSOS && it.isOnline }
    val unacknowledgedSOSCount: Int get() = _sosRecords.value.count { !it.isAcknowledged }
    val unreadCommandCount: Int get() = _commandOrders.value.count { !it.isRead }
    val onlineTeamCount: Int get() = _teamMembers.value.count { it.isOnline }
    val unreadChatMessageCount: Int get() = _chatMessages.value.count { !it.isRead }
    val pendingReinforcementCount: Int get() = _reinforcementRequests.value.count { it.status == ReinforcementStatus.PENDING }
    val activeTaskCount: Int get() = _tasks.value.count { it.isActive }

    fun uptimeText(): String {
        val s = ((System.currentTimeMillis() - startTimeMs) / 1000).toInt()
        _uptimeSeconds.value = s
        val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
        return if (h > 0) "%02d:%02d:%02d".format(h, m, sec) else "%02d:%02d".format(m, sec)
    }

    fun systemStatus(): Pair<String, Color> {
        if (commandClient.isConnected.value) return "已連線指揮中心" to NV.green
        if (sosVictimCount > 0) return "SOS 警報中" to NV.danger
        return "未連線指揮中心" to Color.Gray
    }

    // === 初始化 ===

    init {
        setupBLECallbacks()
        setupWiFiClient()
        persistence.migrateFromSharedPreferences(application)
        loadLocalPatients()
        loadAIChatHistory()
        startLocationTimer()
    }

    override fun onCleared() {
        super.onCleared()
        statusReportTimer?.cancel()
        locationTimer?.cancel()
        commandTimer?.cancel()
        sosAutoDowngradeTimer?.cancel()
        stopSimulation()
        bluetoothManager.onStatusUpdate = null
        bluetoothManager.onLoRaCommand = null
        bluetoothManager.disconnect()
        // Null out all callbacks before stopping to prevent calls on cancelled scope
        commandClient.onCommand = null
        commandClient.onChatMessage = null
        commandClient.onDisasterUpdate = null
        commandClient.onPersonnelAssignment = null
        commandClient.onPWSAlert = null
        commandClient.onBriefing = null
        commandClient.onPersonalNotification = null
        commandClient.onQuickStatus = null
        commandClient.onTaskAssignment = null
        commandClient.onTimerSync = null
        commandClient.onTimerCancel = null
        commandClient.onHazardReport = null
        commandClient.onReinforcementRequest = null
        commandClient.onReinforcementReply = null
        commandClient.onDecision = null
        commandClient.onReportSummary = null
        commandClient.onRadioControl = null
        commandClient.onSOSAlert = null
        commandClient.onSOSCancelAlert = null
        commandClient.onPhotoAlert = null
        commandClient.onResourceUpdate = null
        commandClient.onStatsUpdate = null
        commandClient.onTextBroadcast = null
        commandClient.onPatientWarning = null
        commandClient.onTranslateResult = null
        commandClient.onReadStatus = null
        commandClient.stop()
    }

    private fun setupBLECallbacks() {
        bluetoothManager.onStatusUpdate = { response ->
            handleFirmwareUpdate(response)
        }
        bluetoothManager.onLoRaCommand = { rawJson ->
            handleLoRaCommand(rawJson)
        }
    }

    private fun handleLoRaCommand(rawJson: String) {
        val loraCmd = com.linkguard.app.ble.BLEDataParser.parseLoRaCommand(
            rawJson.toByteArray(Charsets.UTF_8)
        ) ?: return

        // 防止重複（用 cmd_id 去重）
        if (_commandOrders.value.any { it.id == loraCmd.cmd_id }) return

        val order = loraCmd.toCommandOrder()
        _commandOrders.update { listOf(order) + it }

        // 發送回執通知韌體
        bluetoothManager.sendCommandAck(loraCmd.cmd_id)

        // 本地通知
        notificationManager.sendCommandNotification(order)

        // Critical 命令：全螢幕覆蓋
        if (order.priority == CommandPriority.CRITICAL) {
            _latestCriticalCommand.value = order
        }
    }

    fun sendCommandAck(commandID: String) {
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendCommandAck(commandID)
        }
    }

    private fun setupWiFiClient() {
        commandClient.onCommand = { wifiCmd ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                handleWiFiCommand(wifiCmd)
            }
        }
        commandClient.onChatMessage = { chat ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _chatMessages.update { current ->
                    if (current.none { it.id == chat.id }) current + chat else current
                }
            }
        }
        commandClient.onDisasterUpdate = { site ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _disasterSite.value = site
            }
        }
        commandClient.onPersonnelAssignment = { assignment ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _personnelAssignments.update { current ->
                    val mutable = current.toMutableList()
                    val idx = mutable.indexOfFirst { it.id == assignment.id }
                    if (idx >= 0) mutable[idx] = assignment else mutable.add(assignment)
                    mutable
                }
            }
        }
        commandClient.onPWSAlert = { alert ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _pwsAlerts.update { listOf(alert) + it }
            }
        }
        commandClient.onBriefing = { briefing ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _briefings.update { listOf(briefing) + it }
            }
        }
        commandClient.onPersonalNotification = { notification ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                var isNew = false
                _personalNotifications.update { current ->
                    val index = current.indexOfFirst { it.id == notification.id }
                    if (index >= 0) {
                        current.toMutableList().also { it[index] = notification }
                    } else {
                        isNew = true
                        listOf(notification) + current
                    }
                }
                if (isNew) _unreadNotificationCount.update { it + 1 }
            }
        }
        commandClient.onQuickStatus = { status ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _quickStatuses.update { current ->
                    if (current.none { it.id == status.id }) listOf(status) + current else current
                }
            }
        }
        commandClient.onTaskAssignment = { task ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _tasks.update { current ->
                    val mutable = current.toMutableList()
                    val idx = mutable.indexOfFirst { it.id == task.id }
                    if (idx >= 0) mutable[idx] = task else mutable.add(0, task)
                    mutable
                }
            }
        }
        commandClient.onTimerSync = { timer ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _countdownTimers.update { it + timer }
                startCountdownRefresh()
            }
        }
        commandClient.onTimerCancel = { timerID ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _countdownTimers.update { it.filter { t -> t.id != timerID } }
            }
        }
        commandClient.onHazardReport = { report ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _hazardReports.update { current ->
                    if (current.none { it.id == report.id }) listOf(report) + current else current
                }
            }
        }
        commandClient.onReinforcementRequest = { request ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _reinforcementRequests.update { current ->
                    if (current.none { it.id == request.id }) {
                        if (!request.isFromSelf) {
                            _latestReinforcementRequest.value = request
                        }
                        listOf(request) + current
                    } else current
                }
            }
        }
        commandClient.onReinforcementReply = { reply ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _reinforcementRequests.update { current ->
                    current.map { if (it.id == reply.id) reply else it }
                }
            }
        }
        commandClient.onDecision = { decision ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _decisions.update { listOf(decision) + it }
                if (decision.decisionId.isNotEmpty()) {
                    commandClient.sendMessageAck(decision.decisionId, "decision", _nodeStatus.value.nodeID)
                }
            }
        }
        commandClient.onReportSummary = { summary ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val report = RadioReport(
                    senderName = summary.senderName,
                    transcription = summary.transcription,
                    locationDesc = summary.locationDesc,
                    reportId = summary.reportId,
                    patientsCount = summary.patientsCount,
                    audioUrl = summary.audioUrl,
                    weather = summary.weather
                )
                _radioReports.update { listOf(report) + it }
            }
        }
        commandClient.onRadioControl = { ctrl ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _currentBroadcaster.value = if (ctrl.action == "start") ctrl.senderName else null
            }
        }
        commandClient.onSOSAlert = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val data = json.optJSONObject("data") ?: json
                val alert = TCPSOSAlert(
                    id = data.optString("sos_id", data.optString("id", java.util.UUID.randomUUID().toString())),
                    senderID = data.optString("device_id", data.optString("deviceID", "")),
                    senderName = data.optString("sender_name", data.optString("senderName", "")),
                    lat = data.optDouble("lat", 0.0),
                    lon = data.optDouble("lon", 0.0),
                    message = data.optString("message", "")
                )
                _incomingTCPSOS.value = alert
                AlarmPlayer.shared.playSOSAlarm(getApplication())
            }
        }
        commandClient.onSOSCancelAlert = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val data = json.optJSONObject("data") ?: json
                val cancelledId = data.optString("sos_id", "")
                val cancelledDeviceId = data.optString("device_id", data.optString("deviceID", ""))
                val current = _incomingTCPSOS.value
                if (current != null && (current.id == cancelledId || current.senderID == cancelledDeviceId || cancelledId.isEmpty())) {
                    _incomingTCPSOS.value = null
                    AlarmPlayer.shared.stopAlarm()
                }
            }
        }
        commandClient.onPhotoAlert = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val photo = PhotoReport(
                    id = json.optString("photo_id", java.util.UUID.randomUUID().toString()),
                    senderName = json.optString("sender_name", ""),
                    lat = json.optDouble("lat", 0.0),
                    lon = json.optDouble("lon", 0.0),
                    locationDesc = json.optString("location_desc", ""),
                    caption = json.optString("caption", ""),
                    thumbnailURL = json.optString("thumbnail_url", ""),
                    fullURL = json.optString("full_url", "")
                )
                _photoReports.update { listOf(photo) + it }
            }
        }
        commandClient.onResourceUpdate = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val summary = json.optJSONObject("summary")
                val amb = summary?.optJSONObject("救護車")
                val med = summary?.optJSONObject("醫療包")
                val per = summary?.optJSONObject("人員")
                _resourceStatus.value = ResourceStatus(
                    ambulanceTotal = amb?.optInt("total", 0) ?: 0,
                    ambulanceAvailable = amb?.optInt("available", 0) ?: 0,
                    medicalKitTotal = med?.optInt("total", 0) ?: 0,
                    medicalKitAvailable = med?.optInt("available", 0) ?: 0,
                    personnelTotal = per?.optInt("total", 0) ?: 0,
                    personnelAvailable = per?.optInt("available", 0) ?: 0
                )
            }
        }
        commandClient.onStatsUpdate = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _latestStats.value = json
            }
        }
        commandClient.onTextBroadcast = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val broadcast = TextBroadcast(
                    broadcastId = json.optString("broadcast_id", ""),
                    message = json.optString("message", ""),
                    senderName = json.optString("sender_name", ""),
                    priority = json.optString("priority", "normal"),
                    timestamp = json.optDouble("timestamp", System.currentTimeMillis() / 1000.0)
                )
                _textBroadcasts.update { listOf(broadcast) + it }
                commandClient.sendMessageAck(broadcast.broadcastId, "text_broadcast", _nodeStatus.value.nodeID)
                if (broadcast.priority == "urgent") {
                    _urgentBroadcast.value = broadcast
                }
            }
        }
        commandClient.onPatientWarning = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val warning = PatientWarning(
                    patientId = json.optString("patient_id", ""),
                    priority = json.optString("priority", ""),
                    location = json.optString("location", ""),
                    minutesSinceTriage = json.optInt("minutes_since_triage", 0),
                    warningLevel = json.optString("warning_level", "low"),
                    message = json.optString("message", ""),
                    timestamp = json.optDouble("timestamp", System.currentTimeMillis() / 1000.0)
                )
                _patientWarnings.update { listOf(warning) + it }
                if (warning.warningLevel == "high") {
                    _activePatientWarning.value = warning
                }
            }
        }
        commandClient.onTranslateResult = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                _latestTranslation.value = TranslationResult(
                    original = json.optString("original", ""),
                    translated = json.optString("translated", ""),
                    detectedLang = json.optString("detected_lang", ""),
                    targetLang = json.optString("target_lang", "")
                )
                _isTranslating.value = false
                _translationError.value = null
            }
        }
        commandClient.onReadStatus = { json ->
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val messageId = json.optString("message_id", "")
                val total = json.optInt("total", 0)
                val readCount = json.optInt("read_count", 0)
                if (messageId.isNotEmpty()) {
                    _readStatuses.update { it + (messageId to Pair(total, readCount)) }
                }
            }
        }
        commandClient.deviceID = _nodeStatus.value.nodeID
        commandClient.startBrowsing()

        statusReportTimer = Timer().also {
            it.scheduleAtFixedRate(object : TimerTask() {
                override fun run() { sendStatusReport() }
            }, 30000, 30000)
        }
    }

    // === 韌體資料處理（BLE Notify）===

    private fun handleFirmwareUpdate(response: FirmwareStatusResponse) {
        val status = _nodeStatus.value.copy(
            nodeID = response.id ?: _nodeStatus.value.nodeID,
            deptCode = response.dept ?: _nodeStatus.value.deptCode,
            battery = response.bat,
            loraLevel = response.lvl,
            isConnected = true,
            pairCode = response.pair ?: _nodeStatus.value.pairCode
        )
        _nodeStatus.value = status

        val now = System.currentTimeMillis()
        val currentVictims = _victims.value.toMutableList()
        val currentSOS = _sosRecords.value.toMutableList()

        for (fv in response.victims) {
            val idx = currentVictims.indexOfFirst { it.id == fv.id }
            if (idx >= 0) {
                val v = currentVictims[idx].copy(
                    heartRate = fv.hr,
                    battery = fv.bat,
                    rssi = fv.rssi,
                    snr = fv.snr ?: currentVictims[idx].snr,
                    isSOS = fv.sos,
                    isOnline = fv.online,
                    lastSeen = if (fv.online) now else currentVictims[idx].lastSeen
                )
                currentVictims[idx] = v

                if (fv.sos && currentSOS.none { it.victimID == fv.id && (now - it.time) < 30000 }) {
                    currentSOS.add(0, SOSRecord(
                        victimID = fv.id, heartRate = fv.hr,
                        rssi = fv.rssi, distance = fv.dist ?: v.distanceText,
                        battery = fv.bat, time = now
                    ))
                    triggerSOSNotification(v)
                }
            } else {
                val victim = VictimNode(
                    id = fv.id, heartRate = fv.hr, battery = fv.bat,
                    rssi = fv.rssi, snr = fv.snr ?: 0.0, isSOS = fv.sos,
                    lastSeen = now, isOnline = fv.online
                )
                currentVictims.add(victim)
                if (fv.sos) {
                    currentSOS.add(0, SOSRecord(
                        victimID = fv.id, heartRate = fv.hr,
                        rssi = fv.rssi, distance = fv.dist ?: victim.distanceText,
                        battery = fv.bat, time = now
                    ))
                    triggerSOSNotification(victim)
                }
            }
        }

        val firmwareIDs = response.victims.map { it.id }.toSet()
        currentVictims.removeAll { it.id !in firmwareIDs }

        _victims.value = currentVictims
        _sosRecords.value = currentSOS

        // 更新團隊成員
        response.team?.let { teamNodes ->
            val currentTeam = _teamMembers.value.toMutableList()
            for (ft in teamNodes) {
                val idx = currentTeam.indexOfFirst { it.id == ft.id }
                if (idx >= 0) {
                    currentTeam[idx] = currentTeam[idx].copy(
                        deptCode = ft.dept,
                        battery = ft.bat,
                        rssi = ft.rssi,
                        isOnline = ft.online,
                        victimCount = ft.vc,
                        lastSeen = if (ft.online) now else currentTeam[idx].lastSeen
                    )
                } else {
                    currentTeam.add(TeamMember(
                        id = ft.id, deptCode = ft.dept, battery = ft.bat,
                        rssi = ft.rssi, isOnline = ft.online, victimCount = ft.vc,
                        lastSeen = now
                    ))
                }
            }
            _teamMembers.value = currentTeam
        }

        // 更新增援請求
        response.rf?.let { rfList ->
            val currentRF = _reinforcementRequests.value.toMutableList()
            for (fr in rfList) {
                if (currentRF.none { it.fromTeam == fr.from && it.message == fr.msg }) {
                    val req = ReinforcementRequest(
                        fromTeam = fr.from,
                        message = fr.msg,
                        location = fr.loc,
                        time = now - fr.ago * 1000L
                    )
                    currentRF.add(0, req)
                    _latestReinforcementRequest.value = req
                }
            }
            _reinforcementRequests.value = currentRF
        }
    }

    // === 模擬模式 ===

    fun toggleSimulation() {
        if (_isSimulating.value) stopSimulation() else startSimulation()
    }

    fun startSimulation() {
        _isSimulating.value = true
        if (_victims.value.isEmpty()) {
            _victims.value = simulation.createInitialVictims()
            _nodeStatus.value = simulation.createInitialNodeStatus()
            _sosRecords.value = simulation.createInitialSOSRecords()
        }
        simulationTimer = Timer().also {
            it.scheduleAtFixedRate(object : TimerTask() {
                override fun run() { simulationTick() }
            }, 2000, 2000)
        }
        startCommandEngine()
    }

    fun stopSimulation() {
        _isSimulating.value = false
        simulationTimer?.cancel()
        simulationTimer = null
        stopCommandEngine()
    }

    // === 手動新增受困者 ===

    fun addManualVictim(id: String, heartRate: Int, battery: Int) {
        val existing = _victims.value.any { it.id == id }
        if (existing) return
        val victim = VictimNode(
            id = id,
            heartRate = heartRate,
            battery = battery,
            rssi = -50.0,
            isOnline = true,
            lastSeen = System.currentTimeMillis()
        )
        _victims.value = _victims.value + victim
    }

    // === WiFi 命令模式 ===

    fun toggleWiFiCommandMode() {
        if (_isWiFiCommandMode.value) stopWiFiCommandMode() else startWiFiCommandMode()
    }

    private fun startWiFiCommandMode() {
        _isWiFiCommandMode.value = true
        startCommandEngine()
    }

    private fun stopWiFiCommandMode() {
        _isWiFiCommandMode.value = false
        if (!_isSimulating.value) {
            stopCommandEngine()
        }
    }

    private fun simulationTick() {
        val victims = _victims.value.toMutableList()
        simulation.updateVictimSignals(victims)
        simulation.updateVictimOnlineStatus(victims)

        // 離線/低電量通知
        for (victim in victims) {
            val wasOnline = previousOnlineStates[victim.id] ?: victim.isOnline
            if (wasOnline && !victim.isOnline) {
                notificationManager.sendOfflineNotification(victim.id)
            }
            previousOnlineStates[victim.id] = victim.isOnline

            if (victim.battery <= 15 && victim.id !in lowBatteryNotified) {
                lowBatteryNotified.add(victim.id)
                notificationManager.sendLowBatteryNotification(victim.id, victim.battery)
            }
        }

        _nodeStatus.value = simulation.updateNodeStatus(_nodeStatus.value)

        val newVictim = simulation.maybeDiscoverNewVictim(victims)
        if (newVictim != null) {
            victims.add(newVictim)
            if (newVictim.isSOS) {
                val record = SOSRecord(
                    victimID = newVictim.id, heartRate = newVictim.heartRate,
                    rssi = newVictim.rssi, distance = newVictim.distanceText,
                    battery = newVictim.battery
                )
                _sosRecords.value = listOf(record) + _sosRecords.value
                triggerSOSNotification(newVictim)
            }
        }

        val sosRecord = simulation.maybeToggleSOS(victims)
        if (sosRecord != null) {
            _sosRecords.value = listOf(sosRecord) + _sosRecords.value
            val v = victims.firstOrNull { it.id == sosRecord.victimID }
            if (v != null) triggerSOSNotification(v)
        }

        _victims.value = victims
    }

    // === 使用者操作 ===

    fun acknowledgeRecord(record: SOSRecord) {
        _sosRecords.value = _sosRecords.value.map {
            if (it.id == record.id) it.copy(isAcknowledged = true) else it
        }
    }

    fun changeDeptCode(dept: String) {
        val d = dept.uppercase().trim()
        if (d.length !in 1..3) return
        _nodeStatus.value = _nodeStatus.value.copy(deptCode = d)
        getApplication<Application>().getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
            .edit().putString("linkguard_dept_code", d).apply()
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendDeptChange(d)
        }
    }

    fun changeNodeID(newID: String) {
        val id = newID.uppercase().trim()
        if (id.isEmpty() || id.length > 10) return
        _nodeStatus.value = _nodeStatus.value.copy(nodeID = id)
        getApplication<Application>().getSharedPreferences("linkguard_prefs", Application.MODE_PRIVATE)
            .edit().putString("linkguard_custom_node_id", id).apply()
    }

    fun changeLoRaLevel(level: Int) {
        val l = level.coerceIn(0, 8)
        _nodeStatus.value = _nodeStatus.value.copy(loraLevel = l)
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendLevelChange(l)
        }
    }

    fun changePairCode(code: String) {
        val c = code.uppercase().trim()
        if (c.length !in 1..8) return
        _nodeStatus.value = _nodeStatus.value.copy(pairCode = c)
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendPairChange(c)
        }
    }

    fun scanForDevices() = bluetoothManager.startScanning()
    fun stopScanning() = bluetoothManager.stopScanning()
    fun connectToDevice(device: DiscoveredDevice) = bluetoothManager.connect(device)
    fun disconnectDevice() = bluetoothManager.disconnect()

    // === SOS 警報 ===

    private fun triggerSOSNotification(victim: VictimNode) {
        _latestSOSVictim.value = victim
        AlarmPlayer.shared.playSOSAlarm(getApplication())
        notificationManager.sendSOSNotification(victim.id, victim.heartRate, victim.distanceText)
        // 30秒後自動降級（全螢幕 → 關閉 overlay，SOS 仍在列表中）
        sosAutoDowngradeTimer?.cancel()
        sosAutoDowngradeTimer = Timer().apply {
            schedule(object : java.util.TimerTask() {
                override fun run() {
                    _latestSOSVictim.value = null
                    AlarmPlayer.shared.stopAlarm()
                }
            }, 30_000L)
        }
    }

    fun dismissSOSAlert() {
        sosAutoDowngradeTimer?.cancel()
        sosAutoDowngradeTimer = null
        val victim = _latestSOSVictim.value
        if (victim != null) {
            _sosRecords.value = _sosRecords.value.map {
                if (it.victimID == victim.id && !it.isAcknowledged) it.copy(isAcknowledged = true) else it
            }
        }
        _latestSOSVictim.value = null
        AlarmPlayer.shared.stopAlarm()
    }

    // === 文字廣播 ===

    fun sendTextBroadcast(message: String, priority: String = "normal") {
        commandClient.sendTextBroadcast(message, _nodeStatus.value.nodeID, priority, _nodeStatus.value.nodeID)
    }

    fun dismissUrgentBroadcast() {
        _urgentBroadcast.value = null
    }

    // === 翻譯 ===

    fun requestTranslation(text: String, sourceLang: String = "auto", targetLang: String = "en") {
        if (!commandClient.isConnected.value) {
            _translationError.value = "未連線指揮中心，無法進行翻譯"
            _isTranslating.value = false
            return
        }
        _translationError.value = null
        _isTranslating.value = true
        _latestTranslation.value = null
        commandClient.sendTranslateRequest(text, sourceLang, targetLang, _nodeStatus.value.nodeID)
        // 逾時保護（15 秒）
        viewModelScope.launch {
            kotlinx.coroutines.delay(15_000)
            if (_isTranslating.value) {
                _isTranslating.value = false
                _translationError.value = "翻譯逾時，請稍後再試"
            }
        }
    }

    fun clearTranslationError() {
        _translationError.value = null
    }

    // === 傷患預警 ===

    fun dismissPatientWarning() {
        _activePatientWarning.value = null
    }

    // === TCP SOS 緊急呼叫 ===

    /** 發送 SOS，回傳 false 表示發送失敗（未連線或寫入失敗） */
    fun sendTCPSOS(message: String = ""): Boolean {
        if (!commandClient.isConnected.value) {
            android.util.Log.w("ViewModel", "SOS send failed: not connected to HQ")
            return false
        }
        val ns = _nodeStatus.value
        val sosId = java.util.UUID.randomUUID().toString().take(8)
        val iso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US)
            .format(java.util.Date())
        val payload = org.json.JSONObject().apply {
            put("type", "sos")
            put("device_id", ns.nodeID)
            put("timestamp", iso)
            put("data", org.json.JSONObject().apply {
                put("sos_id", sosId)
                put("sender_name", ns.nodeID)
                put("lat", lastGpsLat ?: 0.0)
                put("lon", lastGpsLon ?: 0.0)
                put("message", message)
            })
        }
        commandClient.sendRawJSON(payload) { ok ->
            viewModelScope.launch(kotlinx.coroutines.Dispatchers.Main.immediate) {
                if (ok) {
                    _tcpSOSId.value = sosId
                    _tcpSOSActive.value = true
                } else {
                    android.util.Log.e("ViewModel", "SOS send failed: TCP write error")
                    _tcpSOSActive.value = false
                }
            }
        }
        return true
    }

    fun cancelTCPSOS() {
        val sosId = _tcpSOSId.value
        val ns = _nodeStatus.value
        if (sosId != null && commandClient.isConnected.value) {
            val iso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US)
                .format(java.util.Date())
            val payload = org.json.JSONObject().apply {
                put("type", "sos_cancel")
                put("device_id", ns.nodeID)
                put("timestamp", iso)
                put("data", org.json.JSONObject().apply {
                    put("sos_id", sosId)
                    put("sender_name", ns.nodeID)
                })
            }
            commandClient.sendRawJSON(payload)
        }
        _tcpSOSActive.value = false
        _tcpSOSId.value = null
    }

    fun dismissIncomingTCPSOS() {
        _incomingTCPSOS.value = null
        AlarmPlayer.shared.stopAlarm()
    }

    // === 指揮中心命令引擎 ===

    private fun startCommandEngine() {
        scheduleNextCommand()
    }

    private fun stopCommandEngine() {
        commandTimer?.cancel()
        commandTimer = null
    }

    private fun scheduleNextCommand() {
        val interval = commandEngine.nextInterval()
        commandTimer = Timer().also {
            it.schedule(object : TimerTask() {
                override fun run() {
                    receiveCommand()
                    scheduleNextCommand()
                }
            }, interval)
        }
    }

    private fun receiveCommand() {
        val order = commandEngine.generateRandomCommand()
        _commandOrders.value = listOf(order) + _commandOrders.value

        notificationManager.sendCommandNotification(order)

        if (order.priority == CommandPriority.CRITICAL) {
            _latestCriticalCommand.value = order
            AlarmPlayer.shared.playAlarm(getApplication())
        }
    }

    fun dismissCommandAlert() {
        val cmd = _latestCriticalCommand.value
        if (cmd != null) {
            _commandOrders.value = _commandOrders.value.map {
                if (it.id == cmd.id) it.copy(isRead = true) else it
            }
        }
        _latestCriticalCommand.value = null
        AlarmPlayer.shared.stopAlarm()
    }

    fun markCommandAsRead(order: CommandOrder) {
        _commandOrders.value = _commandOrders.value.map {
            if (it.id == order.id) it.copy(isRead = true) else it
        }
    }

    fun markAllCommandsAsRead() {
        _commandOrders.value = _commandOrders.value.map { it.copy(isRead = true) }
    }

    // === WiFi 命令處理 ===

    private fun handleWiFiCommand(wifiCmd: WiFiCommand) {
        val order = wifiCmd.toCommandOrder()
        if (_commandOrders.value.any { it.id == order.id }) return

        _commandOrders.value = listOf(order) + _commandOrders.value
        notificationManager.sendCommandNotification(order)

        if (order.priority == CommandPriority.CRITICAL) {
            _latestCriticalCommand.value = order
            AlarmPlayer.shared.playAlarm(getApplication())
        }
    }

    // === 傷員回報 ===

    fun submitPatientReport(report: PatientReport) {
        val deviceID = _nodeStatus.value.nodeID
        commandClient.sendPatientReport(report, deviceID)
        // 持久化到本地
        _localPatients.value = _localPatients.value + report
        saveLocalPatients()
    }

    private fun saveLocalPatients() {
        val arr = org.json.JSONArray()
        _localPatients.value.forEach { p ->
            arr.put(org.json.JSONObject().apply {
                put("patientId", p.patientId)
                put("location", p.location)
                put("breathingRate", p.breathingRate)
                put("capillaryRefill", p.capillaryRefill)
                put("canFollowCommands", p.canFollowCommands)
                put("gpsLat", p.gpsLat ?: org.json.JSONObject.NULL)
                put("gpsLon", p.gpsLon ?: org.json.JSONObject.NULL)
                put("notes", p.notes)
            })
        }
        persistence.saveArray("localPatients", arr)
    }

    private fun loadLocalPatients() {
        val arr = persistence.loadArray("localPatients") ?: return
        try {
            val list = mutableListOf<PatientReport>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                list.add(PatientReport(
                    patientId = o.getString("patientId"),
                    location = o.getString("location"),
                    breathingRate = o.getInt("breathingRate"),
                    capillaryRefill = o.getDouble("capillaryRefill"),
                    canFollowCommands = o.getBoolean("canFollowCommands"),
                    gpsLat = if (o.isNull("gpsLat")) null else o.getDouble("gpsLat"),
                    gpsLon = if (o.isNull("gpsLon")) null else o.getDouble("gpsLon"),
                    notes = o.optString("notes", "")
                ))
            }
            _localPatients.value = list
        } catch (e: Exception) {
            Log.e("ViewModel", "載入傷患資料失敗: ${e.message}")
        }
    }

    // === 增援操作 ===

    fun sendReinforcementRequest(message: String, location: String) {
        val dept = _nodeStatus.value.deptCode
        val req = ReinforcementRequest(
            fromTeam = dept,
            message = message,
            location = location,
            isFromSelf = true
        )
        _reinforcementRequests.value = listOf(req) + _reinforcementRequests.value
        // WiFi 優先
        if (commandClient.isConnected.value) {
            commandClient.sendReinforcementRequest(req)
        }
        // BLE 備援
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendReinforcement(message, location)
        }
    }

    fun acceptReinforcement(request: ReinforcementRequest) {
        val dept = _nodeStatus.value.deptCode
        _reinforcementRequests.value = _reinforcementRequests.value.map {
            if (it.id == request.id) {
                it.copy(status = ReinforcementStatus.ACCEPTED).also { r ->
                    r.respondedBy.add(dept)
                }
            } else it
        }
        // WiFi 優先
        val updated = _reinforcementRequests.value.firstOrNull { it.id == request.id }
        if (updated != null && commandClient.isConnected.value) {
            commandClient.sendReinforcementReply(updated)
        }
        // BLE 備援
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendReinforcementReply(request.fromTeam, true)
        }
    }

    fun declineReinforcement(request: ReinforcementRequest) {
        _reinforcementRequests.value = _reinforcementRequests.value.map {
            if (it.id == request.id) it.copy(status = ReinforcementStatus.DECLINED) else it
        }
        // WiFi 優先
        val updated = _reinforcementRequests.value.firstOrNull { it.id == request.id }
        if (updated != null && commandClient.isConnected.value) {
            commandClient.sendReinforcementReply(updated)
        }
        // BLE 備援
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendReinforcementReply(request.fromTeam, false)
        }
    }

    fun dismissReinforcementAlert() {
        _latestReinforcementRequest.value = null
    }

    // === 聊天 ===

    fun sendChat(text: String) {
        val content = text.trim()
        if (content.isEmpty()) return
        val status = _nodeStatus.value
        val mentions = parseMentionsFromText(content)
        val chat = ChatMessage(
            senderID = status.nodeID,
            senderName = "${status.deptCode}-${status.nodeID}",
            content = content,
            mentions = mentions
        )
        _chatMessages.value = _chatMessages.value + chat
        commandClient.sendChatMessage(chat)
    }

    /** 從 @ 提及 token 對比 personnel.nickname/name/id 與 team.nickname/id 返回 id 列表 */
    private fun parseMentionsFromText(text: String): List<String> {
        if (!text.contains('@')) return emptyList()
        val tokens = Regex("@([\\u4e00-\\u9fa5A-Za-z0-9_\\-]{1,20})").findAll(text).map { it.groupValues[1] }.toList()
        if (tokens.isEmpty()) return emptyList()
        val plist = _personnelAssignments.value
        val tlist = _teamMembers.value
        val out = mutableListOf<String>()
        for (tok in tokens) {
            val pid = plist.firstOrNull { it.nickname == tok }?.id
                ?: plist.firstOrNull { it.name == tok }?.id
                ?: plist.firstOrNull { it.id == tok }?.id
                ?: plist.firstOrNull { it.id.endsWith(tok) && tok.length >= 3 }?.id
                ?: tlist.firstOrNull { it.nickname == tok }?.id
                ?: tlist.firstOrNull { it.id == tok }?.id
                ?: tlist.firstOrNull { it.id.endsWith(tok) && tok.length >= 3 }?.id
            if (pid != null && pid !in out) out.add(pid)
        }
        return out
    }

    // === 通知管理 ===

    fun markNotificationAsRead(id: String) {
        _personalNotifications.value = _personalNotifications.value.map {
            if (it.id == id) it.copy(isRead = true) else it
        }
        _unreadNotificationCount.value = _personalNotifications.value.count { !it.isRead }
    }

    // === 團隊操作 ===

    fun sendTeamPing() {
        if (bluetoothManager.isConnected.value) {
            bluetoothManager.sendTeamPing()
        }
    }

    // === WiFi 狀態回報 ===

    private fun sendStatusReport() {
        if (!commandClient.isConnected.value) return

        val batteryManager = getApplication<Application>()
            .getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val bleBattery = _nodeStatus.value.battery
        val currentBattery = if (bleBattery > 0) bleBattery
            else batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).coerceAtLeast(0)
        val currentBLE = bluetoothManager.isConnected.value
        val currentVictimCount = _victims.value.size
        val currentSOSCount = sosVictimCount

        // 差異上報：無變化則跳過
        if (lastReportedBattery >= 0 &&
            kotlin.math.abs(currentBattery - lastReportedBattery) < 5 &&
            lastReportedBLE == currentBLE &&
            lastReportedVictimCount == currentVictimCount &&
            lastReportedSOSCount == currentSOSCount) {
            return
        }
        lastReportedBattery = currentBattery
        lastReportedBLE = currentBLE
        lastReportedVictimCount = currentVictimCount
        lastReportedSOSCount = currentSOSCount

        val victimSummaries = _victims.value.map {
            VictimSummary(
                id = it.id, heartRate = it.heartRate, battery = it.battery,
                rssi = it.rssi, isSOS = it.isSOS, isOnline = it.isOnline
            )
        }
        val teamSummaries = _teamMembers.value.map {
            TeamSummary(
                id = it.id, deptCode = it.deptCode, battery = it.battery,
                rssi = it.rssi, isOnline = it.isOnline, victimCount = it.victimCount
            )
        }

        val report = FieldStatusReport(
            deviceID = _nodeStatus.value.nodeID,
            deptCode = _nodeStatus.value.deptCode,
            battery = currentBattery,
            bleConnected = currentBLE,
            victims = victimSummaries,
            teamMembers = teamSummaries,
            sosCount = currentSOSCount,
            timestamp = System.currentTimeMillis() / 1000.0
        )
        commandClient.sendStatusReport(report)
    }

    // === 定期 GPS 回報 ===

    @android.annotation.SuppressLint("MissingPermission")
    private fun startLocationTimer() {
        locationTimer?.cancel()
        locationTimer = Timer().also {
            it.scheduleAtFixedRate(object : TimerTask() {
                override fun run() { sendLocationUpdate() }
            }, locationIntervalMs, locationIntervalMs)
        }
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun sendLocationUpdate() {
        if (!commandClient.isConnected.value) return
        val app = getApplication<Application>()
        val hasPerm = ContextCompat.checkSelfPermission(
            app, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPerm) return

        val fusedClient = LocationServices.getFusedLocationProviderClient(app)
        fusedClient.lastLocation.addOnSuccessListener { loc ->
            if (loc == null) return@addOnSuccessListener

            val lat = loc.latitude
            val lon = loc.longitude

            // 靜止偵測：距離 < 10m 連續 3 次 → 延長到 60s
            val prevLat = lastGpsLat
            val prevLon = lastGpsLon
            if (prevLat != null && prevLon != null) {
                val results = FloatArray(1)
                android.location.Location.distanceBetween(prevLat, prevLon, lat, lon, results)
                val distance = results[0]

                if (distance < stationaryThresholdMeters) {
                    stationaryCount++
                    if (stationaryCount >= stationaryCountThreshold && locationIntervalMs < 60_000L) {
                        locationIntervalMs = 60_000L
                        startLocationTimer()
                        Log.d("ViewModel", "GPS 靜止模式：60s 間隔")
                        return@addOnSuccessListener
                    }
                } else {
                    if (stationaryCount >= stationaryCountThreshold && locationIntervalMs > 30_000L) {
                        locationIntervalMs = 30_000L
                        startLocationTimer()
                        Log.d("ViewModel", "GPS 移動偵測：恢復 30s 間隔")
                    }
                    stationaryCount = 0
                }
            }

            lastGpsLat = lat
            lastGpsLon = lon

            // GPS 城市反查（首次或城市未知時）
            if (_gpsCity.value == null) {
                resolveGpsCityFromLocation(lat, lon)
            }

            val node = _nodeStatus.value
            commandClient.sendLocation(
                lat = lat,
                lon = lon,
                accuracy = loc.accuracy,
                role = node.deptCode,
                name = node.nodeID,
                deviceID = node.nodeID
            )
        }
    }

    // === 快速狀態回報 ===

    fun sendQuickStatus(type: QuickStatusType, zone: String = "", note: String = "") {
        val status = QuickStatus(
            type = type.key,
            senderID = _nodeStatus.value.nodeID,
            senderName = _nodeStatus.value.nodeID,
            zone = zone,
            note = note
        )
        val current = _quickStatuses.value
        _quickStatuses.value = listOf(status) + current
        commandClient.sendQuickStatus(status)
    }

    // === 任務管理 ===

    fun updateTaskStatus(taskID: String, newStatus: TaskStatus) {
        _tasks.value = _tasks.value.map {
            if (it.id == taskID) it.copy(status = newStatus.key) else it
        }
        val updated = _tasks.value.firstOrNull { it.id == taskID } ?: return
        commandClient.sendTaskUpdate(updated)
    }

    // === 倒數計時器 ===

    private fun startCountdownRefresh() {
        if (countdownRefreshTimer != null) return
        countdownRefreshTimer = Timer().also {
            it.scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    val expired = _countdownTimers.value.filter { t -> t.isExpired }
                    if (expired.isNotEmpty()) {
                        _countdownTimers.value = _countdownTimers.value.filter { t -> !t.isExpired }
                    }
                    if (_countdownTimers.value.isEmpty()) {
                        countdownRefreshTimer?.cancel()
                        countdownRefreshTimer = null
                    }
                }
            }, 1000, 1000)
        }
    }

    // === 危險標記 ===

    fun reportHazard(type: HazardType, description: String = "", zone: String = "", severity: HazardSeverity = HazardSeverity.MEDIUM) {
        val report = HazardReport(
            hazardType = type.key,
            description = description,
            reporterID = _nodeStatus.value.nodeID,
            reporterName = _nodeStatus.value.nodeID,
            zone = zone,
            severity = severity.key
        )
        _hazardReports.value = listOf(report) + _hazardReports.value
        commandClient.sendHazardReport(report)
    }

    // === 交班摘要 ===

    fun generateHandoverSummary(): String {
        val sb = StringBuilder()
        sb.appendLine("═══ 交班摘要 ═══")
        sb.appendLine("時間：${java.text.SimpleDateFormat("yyyy/MM/dd HH:mm", java.util.Locale.getDefault()).format(java.util.Date())}")
        sb.appendLine("裝置：${_nodeStatus.value.nodeID}")
        sb.appendLine()
        sb.appendLine("【受困者】共 ${_victims.value.size} 人，線上 $onlineVictimCount，SOS $sosVictimCount")
        for (v in _victims.value.filter { it.isSOS }) {
            sb.appendLine("  [!] ${v.id} - HR:${v.heartRate} BAT:${v.battery}%")
        }
        sb.appendLine()
        sb.appendLine("【團隊】共 ${_teamMembers.value.size} 人，線上 $onlineTeamCount")
        sb.appendLine()
        sb.appendLine("【未完成任務】${activeTaskCount} 項")
        for (t in _tasks.value.filter { it.isActive }) {
            sb.appendLine("  - ${t.title}（${t.taskStatus.label}）")
        }
        sb.appendLine()
        sb.appendLine("【危險標記】${_hazardReports.value.size} 筆")
        for (h in _hazardReports.value.take(5)) {
            sb.appendLine("  - ${h.hazard?.label ?: h.hazardType}（${h.severityLevel.label}）${h.zone}")
        }
        sb.appendLine()
        sb.appendLine("【計時器】${_countdownTimers.value.size} 個進行中")
        sb.appendLine("═══════════════")
        return sb.toString()
    }

    // === NFC 操作 ===

    fun setNfcAvailable(available: Boolean) {
        _isNfcAvailable.value = available
    }

    fun onNfcScanned(result: NfcScanResult) {
        _nfcScanResult.value = result
        addActivity(ActivityKind.DEVICE_ALERT, "NFC 掃描完成", result.rawText.take(60))
    }

    fun clearNfcScan() {
        _nfcScanResult.value = null
    }

    fun applyNfcToPatientForm(result: NfcScanResult) {
        // Pre-fill is done in PatientFormScreen by reading nfcScanResult StateFlow
        // This function keeps the result available for the form screen to read
        _nfcScanResult.value = result
    }

    // === AI 助理操作 ===

    fun sendAIMessage(text: String, includeContext: Boolean = true) {
        if (_isAISending.value) return
        val userMsg = FieldAIMessage(role = "user", content = text)
        _aiChatMessages.update { it + userMsg }
        _isAISending.value = true

        val hqHost = commandClient.serverHost
        if (hqHost.isEmpty()) {
            val errMsg = FieldAIMessage(
                role = "assistant", content = "尚未連接到 AI 伺服器，無法處理請求。",
                isError = true
            )
            _aiChatMessages.update { it + errMsg }
            _isAISending.value = false
            return
        }

        // Build history (last 10 pairs)
        val history = _aiChatMessages.value.takeLast(20).map {
            org.json.JSONObject().apply {
                put("role", it.role)
                put("content", it.content)
            }
        }

        // Optional context injection
        val systemPrompt = if (includeContext) buildContextPrompt() else ""

        val body = org.json.JSONObject().apply {
            put("message", text)
            put("history", org.json.JSONArray(history))
            if (systemPrompt.isNotEmpty()) put("system_prompt", systemPrompt)
        }

        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val client = okhttp3.OkHttpClient.Builder()
                    .connectTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                    .readTimeout(120, java.util.concurrent.TimeUnit.SECONDS)
                    .build()
                val mediaType = "application/json; charset=utf-8".toMediaType()
                val request = okhttp3.Request.Builder()
                    .url("http://$hqHost:8001/chat")
                    .post(body.toString().toRequestBody(mediaType))
                    .build()
                val response = client.newCall(request).execute()
                val responseBody = response.body?.string() ?: ""
                val json = org.json.JSONObject(responseBody)
                val data = json.optJSONObject("data") ?: json
                val reply = data.optString("reply", "（無回覆）")
                val model = data.optString("model", "gemma4")
                val elapsedMs = if (data.has("elapsed_ms")) data.getInt("elapsed_ms") else null

                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    val aiMsg = FieldAIMessage(
                        role = "assistant",
                        content = reply,
                        model = model,
                        elapsedMs = elapsedMs
                    )
                    _aiChatMessages.update { it + aiMsg }
                    _isAISending.value = false
                    addActivity(ActivityKind.HQ_DECISION, "AI 助理回覆", reply.take(80))
                    saveAIChatHistory()
                }
            } catch (e: Exception) {
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    val errMsg = FieldAIMessage(
                        role = "assistant",
                        content = "連線錯誤：${e.localizedMessage ?: "未知錯誤"}",
                        isError = true
                    )
                    _aiChatMessages.update { it + errMsg }
                    _isAISending.value = false
                }
            }
        }
    }

    private fun buildContextPrompt(): String {
        val site = _disasterSite.value
        val patients = _localPatients.value
        val hazards = _hazardReports.value
        val sb = StringBuilder()
        sb.appendLine("【現場狀況】")
        if (site != null) {
            sb.appendLine("災害地點：${site.buildingName.ifBlank { "未命名" }} ${site.address}")
        }
        sb.appendLine("傷患數：${patients.size}，受困者：${_victims.value.size}，SOS：$sosVictimCount")
        if (hazards.isNotEmpty()) sb.appendLine("危險標記：${hazards.take(3).joinToString { it.hazard?.label ?: it.hazardType }}")
        patients.take(3).forEach { p ->
            sb.appendLine("傷患 ${p.patientId}：呼吸${p.breathingRate}次，${if (p.canFollowCommands) "意識清醒" else "意識不清"}，CRT ${p.capillaryRefill}s")
        }
        return sb.toString().trim()
    }

    fun clearAIChat() {
        _aiChatMessages.value = emptyList()
        persistence.delete("field_ai_chat_history")
    }

    private fun saveAIChatHistory() {
        val arr = org.json.JSONArray()
        _aiChatMessages.value.takeLast(50).forEach { msg ->
            arr.put(org.json.JSONObject().apply {
                put("id", msg.id)
                put("role", msg.role)
                put("content", msg.content)
                put("timestamp", msg.timestamp)
                put("model", msg.model ?: org.json.JSONObject.NULL)
                put("elapsedMs", msg.elapsedMs ?: org.json.JSONObject.NULL)
                put("isError", msg.isError)
            })
        }
        persistence.saveArray("field_ai_chat_history", arr)
    }

    private fun loadAIChatHistory() {
        val arr = persistence.loadArray("field_ai_chat_history") ?: return
        try {
            val list = mutableListOf<FieldAIMessage>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                list.add(FieldAIMessage(
                    id = o.optString("id", java.util.UUID.randomUUID().toString()),
                    role = o.getString("role"),
                    content = o.getString("content"),
                    timestamp = o.optLong("timestamp", System.currentTimeMillis()),
                    model = if (o.isNull("model")) null else o.optString("model"),
                    elapsedMs = if (o.isNull("elapsedMs")) null else o.optInt("elapsedMs"),
                    isError = o.optBoolean("isError", false)
                ))
            }
            _aiChatMessages.value = list
        } catch (_: Exception) {}
    }

    // === 活動日誌 ===

    private fun addActivity(kind: ActivityKind, title: String, summary: String) {
        val entry = ActivityLogEntry(kind = kind, title = title, summary = summary)
        _activityLog.update { listOf(entry) + it.take(199) }
    }

    // === 快速狀態回報（字串重載，供 USARRoleScreen 使用） ===

    fun sendQuickStatus(type: String, zone: String = "", note: String = "") {
        val status = QuickStatus(
            type = type,
            senderID = _nodeStatus.value.nodeID,
            senderName = _nodeStatus.value.nodeID,
            zone = zone,
            note = note
        )
        _quickStatuses.update { listOf(status) + it }
        if (commandClient.isConnected.value) commandClient.sendQuickStatus(status)
        addActivity(ActivityKind.QUICK_STATUS, "狀態回報：$type", zone.ifBlank { note })
    }

    // === 任務接受（班長操作） ===

    fun acceptTask(taskID: String) {
        updateTaskStatus(taskID, TaskStatus.ACCEPTED)
    }

    // === 人員 CRUD ===

    fun addPersonnelAssignment(name: String, role: PersonnelRole, zone: String, floor: String) {
        val assignment = PersonnelAssignment(name = name, role = role, assignedZone = zone, assignedFloor = floor)
        _personnelAssignments.update { listOf(assignment) + it }
        addActivity(ActivityKind.TASK, "新增人員配置：$name", "${role.label} - $zone")
    }

    fun updatePersonnelAssignment(updated: PersonnelAssignment) {
        _personnelAssignments.update { current ->
            current.map { if (it.id == updated.id) updated else it }
        }
    }

    // === GPS 城市反查（供醫院目錄使用） ===

    private fun resolveGpsCityFromLocation(lat: Double, lon: Double) {
        try {
            val geocoder = android.location.Geocoder(getApplication(), java.util.Locale.getDefault())
            @Suppress("DEPRECATION")
            val addresses = geocoder.getFromLocation(lat, lon, 1)
            val city = addresses?.firstOrNull()?.let {
                it.adminArea ?: it.subAdminArea
            }
            if (city != null) _gpsCity.value = city
        } catch (_: Exception) {}
    }
}

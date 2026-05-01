package com.linkguard.app.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.linkguard.app.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.*
import java.net.Socket

class CommandClient(private val context: Context) {

    companion object {
        private const val TAG = "CommandClient"
        private const val SERVICE_TYPE = "_linkguard-hq._tcp."
    }

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _serverName = MutableStateFlow("")
    val serverName: StateFlow<String> = _serverName
    val serverHost: String get() = lastHost ?: _serverName.value.split(":").firstOrNull() ?: ""

    var onCommand: ((WiFiCommand) -> Unit)? = null
    var onChatMessage: ((ChatMessage) -> Unit)? = null
    var onDisasterUpdate: ((DisasterSite) -> Unit)? = null
    var onPersonnelAssignment: ((PersonnelAssignment) -> Unit)? = null
    var onPWSAlert: ((PWSAlert) -> Unit)? = null
    var onBriefing: ((BriefingReport) -> Unit)? = null
    var onPersonalNotification: ((PersonalNotification) -> Unit)? = null
    var onQuickStatus: ((QuickStatus) -> Unit)? = null
    var onTaskAssignment: ((TaskAssignment) -> Unit)? = null
    var onTimerSync: ((CountdownTimerModel) -> Unit)? = null
    var onTimerCancel: ((String) -> Unit)? = null
    var onHazardReport: ((HazardReport) -> Unit)? = null
    var onReinforcementRequest: ((ReinforcementRequest) -> Unit)? = null
    var onReinforcementReply: ((ReinforcementRequest) -> Unit)? = null
    var onDecision: ((HQDecision) -> Unit)? = null
    var onReportSummary: ((RadioReportSummary) -> Unit)? = null
    var onRadioControl: ((RadioControlPayload) -> Unit)? = null
    var onSOSAlert: ((JSONObject) -> Unit)? = null
    var onSOSCancelAlert: ((JSONObject) -> Unit)? = null
    var onPhotoAlert: ((JSONObject) -> Unit)? = null
    var onResourceUpdate: ((JSONObject) -> Unit)? = null
    var onStatsUpdate: ((JSONObject) -> Unit)? = null
    var onTextBroadcast: ((JSONObject) -> Unit)? = null
    var onPatientWarning: ((JSONObject) -> Unit)? = null
    var onTranslateResult: ((JSONObject) -> Unit)? = null
    var onReadStatus: ((JSONObject) -> Unit)? = null

    private var nsdManager: NsdManager? = null
    @Volatile private var socket: Socket? = null
    @Volatile private var writer: BufferedWriter? = null
    private var receiveThread: Thread? = null
    private var isBrowsing = false
    private var reconnectThread: Thread? = null
    private var pingTimer: java.util.Timer? = null

    private val discoveryListener = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(serviceType: String) {
            Log.d(TAG, "NSD discovery started")
        }

        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            Log.d(TAG, "NSD service found: ${serviceInfo.serviceName}")
            // 每次 resolve 必須建立新的 ResolveListener 實例
            val listener = object : NsdManager.ResolveListener {
                override fun onResolveFailed(si: NsdServiceInfo, errorCode: Int) {
                    Log.e(TAG, "NSD resolve failed: $errorCode")
                }
                override fun onServiceResolved(si: NsdServiceInfo) {
                    Log.d(TAG, "NSD resolved: ${si.host?.hostAddress}:${si.port}")
                    val host = si.host ?: return
                    val port = si.port
                    _serverName.value = si.serviceName
                    connectToServer(host.hostAddress ?: return, port)
                }
            }
            nsdManager?.resolveService(serviceInfo, listener)
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            Log.d(TAG, "NSD service lost: ${serviceInfo.serviceName}")
        }

        override fun onDiscoveryStopped(serviceType: String) {
            Log.d(TAG, "NSD discovery stopped")
        }

        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "NSD start discovery failed: $errorCode")
            isBrowsing = false
        }

        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "NSD stop discovery failed: $errorCode")
        }
    }

    fun startBrowsing() {
        if (isBrowsing) return
        nsdManager = (context.getSystemService(Context.NSD_SERVICE) as? NsdManager) ?: return
        nsdManager?.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        isBrowsing = true
    }

    /** 手動連線到指定 IP:Port */
    fun connectToIP(host: String, port: Int) {
        stop()
        _serverName.value = "$host:$port"
        connectToServer(host, port)
    }

    fun stop() {
        isBrowsing = false
        stopPing()
        try { nsdManager?.stopServiceDiscovery(discoveryListener) } catch (_: Exception) {}
        disconnect()
    }

    private var lastHost: String? = null
    private var lastPort: Int = 0

    private fun connectToServer(host: String, port: Int) {
        if (_isConnected.value) return
        lastHost = host
        lastPort = port

        Thread {
            try {
                val s = Socket()
                s.connect(java.net.InetSocketAddress(host, port), 5000)
                s.soTimeout = 0
                // OS-level keepalive：當對端機器斷電/網路突死時，由 OS 在 ~2 小時後送 probe；
                // 配合 startPing() 的應用層 ping 提供更快的死連線偵測
                try { s.keepAlive = true } catch (_: Exception) {}
                try { s.tcpNoDelay = true } catch (_: Exception) {}
                socket = s
                writer = BufferedWriter(OutputStreamWriter(s.getOutputStream(), Charsets.UTF_8))
                _isConnected.value = true
                reconnectAttempt = 0  // 連線成功重置重試計數
                Log.d(TAG, "Connected to HQ: $host:$port")

                startPing()
                startReceiving(s)
            } catch (e: Exception) {
                Log.e(TAG, "Connection failed: ${e.message}")
                _isConnected.value = false
                scheduleReconnect(host, port)
            }
        }.start()
    }

    private fun startReceiving(socket: Socket) {
        receiveThread = Thread {
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            val buffer = StringBuilder()
            try {
                val charBuf = CharArray(4096)
                while (!Thread.currentThread().isInterrupted) {
                    val bytesRead = reader.read(charBuf)
                    if (bytesRead == -1) break
                    buffer.append(charBuf, 0, bytesRead)

                    while (true) {
                        val nlIdx = buffer.indexOf('\n')
                        if (nlIdx < 0) break
                        val line = buffer.substring(0, nlIdx).trim()
                        buffer.delete(0, nlIdx + 1)
                        if (line.isNotEmpty()) processLine(line)
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Receive ended: ${e.message}")
            } finally {
                _isConnected.value = false
                Log.d(TAG, "Disconnected from HQ")
                // 自動重連
                val h = lastHost
                val p = lastPort
                if (h != null && p > 0) {
                    scheduleReconnect(h, p)
                }
            }
        }
        receiveThread?.start()
    }

    private fun processLine(line: String) {
        try {
            val json = JSONObject(line)
            // 支援兩種格式：LGAP (msgType/payload) 和伺服器廣播 (type/data)
            var msgType = json.optString("msgType", "")
            var payload = json.optString("payload", "")
            if (msgType.isEmpty()) {
                msgType = json.optString("type", "")
                val dataObj = json.opt("data")
                payload = if (dataObj is JSONObject) dataObj.toString()
                          else if (dataObj != null) dataObj.toString()
                          else ""
            }

            when (msgType) {
                "command" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onCommand?.invoke(WiFiCommand(
                            id = c.optString("id", ""), type = c.optString("type", ""),
                            priority = c.optInt("priority", 0), title = c.optString("title", ""),
                            detail = c.optString("detail", ""), sender = c.optString("sender", ""),
                            timestamp = c.optDouble("timestamp", 0.0)
                        ))
                    }
                }
                "chat_message" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        val mentionsList = mutableListOf<String>()
                        c.optJSONArray("mentions")?.let { arr ->
                            for (i in 0 until arr.length()) mentionsList.add(arr.optString(i))
                        }
                        onChatMessage?.invoke(ChatMessage(
                            id = c.optString("id", ""), senderID = c.optString("senderID", ""),
                            senderName = c.optString("senderName", ""),
                            recipientID = c.optString("recipientID", null),
                            content = c.optString("content", ""),
                            timestamp = c.optDouble("timestamp", 0.0),
                            isRead = c.optBoolean("isRead", false),
                            mentions = mentionsList
                        ))
                    }
                }
                "disaster_update" -> {
                    if (payload.isNotEmpty()) {
                        onDisasterUpdate?.invoke(parseDisasterSite(JSONObject(payload)))
                    }
                }
                "personnel_assignment" -> {
                    if (payload.isNotEmpty()) {
                        val trimmed = payload.trimStart()
                        if (trimmed.startsWith("[")) {
                            // iOS HQ 廣播陣列格式
                            val arr = JSONArray(payload)
                            for (i in 0 until arr.length()) {
                                val c = arr.getJSONObject(i)
                                onPersonnelAssignment?.invoke(PersonnelAssignment(
                                    id = c.optString("id", ""),
                                    name = c.optString("name", ""),
                                    role = PersonnelRole.fromKey(c.optString("role", "")),
                                    assignedZone = c.optString("assignedZone", ""),
                                    assignedFloor = c.optString("assignedFloor", ""),
                                    timestamp = c.optDouble("timestamp", 0.0)
                                ))
                            }
                        } else {
                            // 單一物件格式
                            val c = JSONObject(payload)
                            onPersonnelAssignment?.invoke(PersonnelAssignment(
                                id = c.optString("id", ""),
                                name = c.optString("name", ""),
                                role = PersonnelRole.fromKey(c.optString("role", "")),
                                assignedZone = c.optString("assignedZone", ""),
                                assignedFloor = c.optString("assignedFloor", ""),
                                timestamp = c.optDouble("timestamp", 0.0)
                            ))
                        }
                    }
                }
                "pws_alert" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onPWSAlert?.invoke(PWSAlert(
                            id = c.optString("id", ""),
                            alertType = PWSAlertType.fromKey(c.optString("alertType", "")),
                            severity = PWSSeverity.fromKey(c.optString("severity", "")),
                            title = c.optString("title", ""), content = c.optString("content", ""),
                            publisher = c.optString("publisher", "HQ"), publishTime = c.optDouble("publishTime", 0.0),
                            isActive = c.optBoolean("isActive", true)
                        ))
                    }
                }
                "briefing" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        val sections = mutableListOf<BriefingSection>()
                        val sArr = c.optJSONArray("sections")
                        if (sArr != null) {
                            for (i in 0 until sArr.length()) {
                                val s = sArr.getJSONObject(i)
                                sections.add(BriefingSection(
                                    title = s.optString("title", ""),
                                    content = s.optString("content", "")
                                ))
                            }
                        }
                        onBriefing?.invoke(BriefingReport(
                            id = c.optString("id", ""),
                            type = BriefingType.fromKey(c.optString("type", "")),
                            title = c.optString("title", ""), author = c.optString("author", ""),
                            sections = sections, timestamp = c.optDouble("timestamp", 0.0)
                        ))
                    }
                }
                "personal_notification" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onPersonalNotification?.invoke(PersonalNotification(
                            id = c.optString("id", ""), targetDeviceID = c.optString("targetDeviceID", ""),
                            title = c.optString("title", ""), content = c.optString("content", ""),
                            timestamp = c.optDouble("timestamp", 0.0),
                            isRead = c.optBoolean("isRead", false)
                        ))
                    }
                }
                "quick_status" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onQuickStatus?.invoke(QuickStatus(
                            id = c.optString("id", ""), type = c.optString("type", ""),
                            senderID = c.optString("senderID", ""), senderName = c.optString("senderName", ""),
                            zone = c.optString("zone", ""), note = c.optString("note", ""),
                            timestamp = c.optDouble("timestamp", 0.0)
                        ))
                    }
                }
                "task_assignment" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onTaskAssignment?.invoke(TaskAssignment(
                            id = c.optString("id", ""), title = c.optString("title", ""),
                            detail = c.optString("detail", ""), assigneeID = c.optString("assigneeID", ""),
                            assigneeName = c.optString("assigneeName", ""), zone = c.optString("zone", ""),
                            priority = c.optInt("priority", 0), status = c.optString("status", "pending"),
                            createdAt = c.optDouble("createdAt", 0.0),
                            dueTime = if (c.has("dueTime") && !c.isNull("dueTime")) c.optDouble("dueTime", 0.0) else null
                        ))
                    }
                }
                "timer_sync" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onTimerSync?.invoke(CountdownTimerModel(
                            id = c.optString("id", ""), title = c.optString("title", ""),
                            durationSeconds = c.optInt("durationSeconds", 0), startedAt = c.optDouble("startedAt", 0.0),
                            isBroadcast = c.optBoolean("isBroadcast", true),
                            targetDeviceID = c.optString("targetDeviceID", "")
                        ))
                    }
                }
                "timer_cancel" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onTimerCancel?.invoke(c.optString("id", ""))
                    }
                }
                "hazard_report" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onHazardReport?.invoke(HazardReport(
                            id = c.optString("id", ""), hazardType = c.optString("hazardType", ""),
                            description = c.optString("description", ""),
                            reporterID = c.optString("reporterID", ""), reporterName = c.optString("reporterName", ""),
                            zone = c.optString("zone", ""), severity = c.optString("severity", "medium"),
                            timestamp = c.optDouble("timestamp", 0.0)
                        ))
                    }
                }
                "reinforcement_request" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        val statusStr = c.optString("status", "\u5f85\u56de\u8986")
                        val status = ReinforcementStatus.fromChinese(statusStr)
                        val respondedBy = mutableListOf<String>()
                        val rArr = c.optJSONArray("respondedBy")
                        if (rArr != null) { for (i in 0 until rArr.length()) respondedBy.add(rArr.getString(i)) }
                        onReinforcementRequest?.invoke(ReinforcementRequest(
                            id = c.optString("id", ""), fromTeam = c.optString("fromTeam", ""),
                            message = c.optString("message", ""),
                            location = c.optString("location", ""),
                            time = (c.optDouble("timestamp", 0.0) * 1000).toLong(),
                            status = status, respondedBy = respondedBy
                        ))
                    }
                }
                "reinforcement_reply" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        val statusStr = c.optString("status", "\u5f85\u56de\u8986")
                        val status = ReinforcementStatus.fromChinese(statusStr)
                        val respondedBy = mutableListOf<String>()
                        val rArr = c.optJSONArray("respondedBy")
                        if (rArr != null) { for (i in 0 until rArr.length()) respondedBy.add(rArr.getString(i)) }
                        onReinforcementReply?.invoke(ReinforcementRequest(
                            id = c.optString("id", ""), fromTeam = c.optString("fromTeam", ""),
                            message = c.optString("message", ""),
                            location = c.optString("location", ""),
                            time = (c.optDouble("timestamp", 0.0) * 1000).toLong(),
                            status = status, respondedBy = respondedBy
                        ))
                    }
                }
                "decision" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        val patients = mutableListOf<PatientDecisionEntry>()
                        val pArr = c.optJSONArray("patients")
                        if (pArr != null) {
                            for (i in 0 until pArr.length()) {
                                val p = pArr.getJSONObject(i)
                                val gpsObj = p.optJSONObject("gps")
                                val gps = if (gpsObj != null) GPSCoord(
                                    lat = gpsObj.optDouble("lat", 0.0),
                                    lon = gpsObj.optDouble("lon", 0.0)
                                ) else null
                                patients.add(PatientDecisionEntry(
                                    id = p.optString("id", ""),
                                    location = p.optString("location", ""),
                                    priority = p.optString("priority", ""),
                                    reason = p.optString("reason", ""),
                                    gps = gps
                                ))
                            }
                        }
                        val weatherObj = c.optJSONObject("weather")
                        val weather = if (weatherObj != null) WeatherSnapshot(
                            temp = if (weatherObj.has("temperature")) weatherObj.getDouble("temperature") else null,
                            humidity = if (weatherObj.has("humidity")) weatherObj.getDouble("humidity") else null,
                            wind = if (weatherObj.has("wind_speed")) weatherObj.getDouble("wind_speed") else null,
                            rainfall = if (weatherObj.has("rainfall")) weatherObj.getDouble("rainfall") else null
                        ) else null
                        onDecision?.invoke(HQDecision(
                            decisionId = c.optString("decision_id", ""),
                            decision = c.optString("decision", ""),
                            patients = patients,
                            timestamp = c.optString("timestamp", ""),
                            trigger = c.optString("trigger", ""),
                            weather = weather
                        ))
                    }
                }
                "report_summary" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        val wObj = c.optJSONObject("weather")
                        val w = if (wObj != null) WeatherSnapshot(
                            temp = if (wObj.has("temperature")) wObj.getDouble("temperature") else null,
                            humidity = if (wObj.has("humidity")) wObj.getDouble("humidity") else null,
                            wind = if (wObj.has("wind_speed")) wObj.getDouble("wind_speed") else null,
                            rainfall = if (wObj.has("rainfall")) wObj.getDouble("rainfall") else null
                        ) else null
                        onReportSummary?.invoke(RadioReportSummary(
                            reportId = c.optString("report_id", c.optString("reportId", "")),
                            senderName = c.optString("sender_name", c.optString("senderName", "")),
                            transcription = c.optString("transcription", ""),
                            timestamp = c.optDouble("timestamp", 0.0),
                            locationDesc = c.optString("location_desc", c.optString("location", "")),
                            patientsCount = c.optInt("patients_count", 0),
                            audioUrl = c.optString("audio_url", ""),
                            weather = w
                        ))
                    }
                }
                "radio_control" -> {
                    if (payload.isNotEmpty()) {
                        val c = JSONObject(payload)
                        onRadioControl?.invoke(RadioControlPayload(
                            action = c.optString("action", ""),
                            senderName = c.optString("sender_name", c.optString("senderName", ""))
                        ))
                    }
                }
                "pong" -> { /* heartbeat reply, ignore */ }
                "sos_alert" -> {
                    if (payload.isNotEmpty()) {
                        onSOSAlert?.invoke(JSONObject(payload))
                    }
                }
                "sos_cancel_alert" -> {
                    if (payload.isNotEmpty()) {
                        onSOSCancelAlert?.invoke(JSONObject(payload))
                    }
                }
                "photo_alert" -> {
                    if (payload.isNotEmpty()) {
                        onPhotoAlert?.invoke(JSONObject(payload))
                    }
                }
                "resource_update" -> {
                    if (payload.isNotEmpty()) {
                        onResourceUpdate?.invoke(JSONObject(payload))
                    }
                }
                "stats_update" -> {
                    if (payload.isNotEmpty()) {
                        onStatsUpdate?.invoke(JSONObject(payload))
                    }
                }
                "text_broadcast_rx" -> {
                    if (payload.isNotEmpty()) {
                        onTextBroadcast?.invoke(JSONObject(payload))
                    }
                }
                "patient_warning" -> {
                    if (payload.isNotEmpty()) {
                        onPatientWarning?.invoke(JSONObject(payload))
                    }
                }
                "translate_result" -> {
                    if (payload.isNotEmpty()) {
                        onTranslateResult?.invoke(JSONObject(payload))
                    }
                }
                "read_status" -> {
                    if (payload.isNotEmpty()) {
                        onReadStatus?.invoke(JSONObject(payload))
                    }
                }
                else -> {
                    // fallback: try direct WiFiCommand
                    if (json.has("id") && json.has("type") && json.has("title")) {
                        onCommand?.invoke(WiFiCommand(
                            id = json.optString("id", ""), type = json.optString("type", ""),
                            priority = json.optInt("priority", 0), title = json.optString("title", ""),
                            detail = json.optString("detail", ""), sender = json.optString("sender", ""),
                            timestamp = json.optDouble("timestamp", 0.0)
                        ))
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse error: ${e.message}")
        }
    }

    private fun parseDisasterSite(j: JSONObject): DisasterSite {
        val floors = mutableListOf<FloorStatus>()
        val fArr = j.optJSONArray("floors")
        if (fArr != null) {
            for (i in 0 until fArr.length()) {
                val f = fArr.getJSONObject(i)
                floors.add(FloorStatus(
                    id = f.optString("id", ""),
                    condition = FloorCondition.fromKey(f.optString("condition", "")),
                    note = f.optString("note", "")
                ))
            }
        }
        val zones = mutableListOf<RescueZone>()
        val zArr = j.optJSONArray("zones")
        if (zArr != null) {
            for (i in 0 until zArr.length()) {
                val z = zArr.getJSONObject(i)
                zones.add(RescueZone(
                    id = z.optString("id", ""), name = z.optString("name", ""),
                    status = ZoneStatus.fromKey(z.optString("status", "")),
                    assignedPersonnel = mutableListOf<String>().apply {
                        val pa = z.optJSONArray("assignedPersonnel")
                        if (pa != null) { for (pi in 0 until pa.length()) add(pa.getString(pi)) }
                    },
                    note = z.optString("note", "")
                ))
            }
        }
        val hazards = mutableListOf<HazardType>()
        val hArr = j.optJSONArray("hazards")
        if (hArr != null) {
            for (i in 0 until hArr.length()) {
                HazardType.fromKey(hArr.getString(i))?.let { hazards.add(it) }
            }
        }
        val entries = mutableListOf<EntryPoint>()
        val eArr = j.optJSONArray("entryPoints")
        if (eArr != null) {
            for (i in 0 until eArr.length()) {
                val e = eArr.getJSONObject(i)
                entries.add(EntryPoint(
                    id = e.optString("id", ""), name = e.optString("name", ""),
                    description = e.optString("description", ""),
                    isAccessible = e.optBoolean("isAccessible", false)
                ))
            }
        }
        return DisasterSite(
            buildingName = j.optString("buildingName", ""),
            address = j.optString("address", ""),
            collapseType = CollapseType.fromKey(j.optString("collapseType", "unknown")),
            aboveGroundFloors = j.optInt("aboveGroundFloors", 1),
            undergroundFloors = j.optInt("undergroundFloors", 0),
            floors = floors, zones = zones, hazards = hazards,
            entryPoints = entries, rallyPoint = j.optString("rallyPoint", ""),
            note = j.optString("note", "")
        )
    }

    fun sendChatMessage(chat: ChatMessage) {
        Thread {
            try {
                val payload = JSONObject().apply {
                    put("id", chat.id)
                    put("senderID", chat.senderID)
                    put("senderName", chat.senderName)
                    if (chat.recipientID != null) put("recipientID", chat.recipientID)
                    put("content", chat.content)
                    put("timestamp", chat.timestamp)
                    put("isRead", chat.isRead)
                    put("mentions", JSONArray().apply { chat.mentions.forEach { put(it) } })
                }
                val msg = JSONObject().apply {
                    put("msgType", "chat_message")
                    put("device_id", deviceID)
                    put("payload", payload.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) {
                Log.e(TAG, "Send chat failed: ${e.message}")
            }
        }.start()
    }

    fun sendStatusReport(report: FieldStatusReport) {
        Thread {
            try {
                val victimsArr = JSONArray()
                for (v in report.victims) {
                    victimsArr.put(JSONObject().apply {
                        put("id", v.id)
                        put("heartRate", v.heartRate)
                        put("battery", v.battery)
                        put("rssi", v.rssi)
                        put("isSOS", v.isSOS)
                        put("isOnline", v.isOnline)
                    })
                }
                val teamArr = JSONArray()
                for (t in report.teamMembers) {
                    teamArr.put(JSONObject().apply {
                        put("id", t.id)
                        put("deptCode", t.deptCode)
                        put("battery", t.battery)
                        put("rssi", t.rssi)
                        put("isOnline", t.isOnline)
                        put("victimCount", t.victimCount)
                    })
                }
                val payload = JSONObject().apply {
                    put("device_id", report.deviceID)
                    put("deviceID", report.deviceID)
                    put("deptCode", report.deptCode)
                    put("battery", report.battery)
                    put("bleConnected", report.bleConnected)
                    put("victims", victimsArr)
                    put("teamMembers", teamArr)
                    put("sosCount", report.sosCount)
                    put("timestamp", report.timestamp)
                }
                val msg = JSONObject().apply {
                    put("msgType", "status_report")
                    put("device_id", deviceID)
                    put("payload", payload.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) {
                Log.e(TAG, "Send status report failed: ${e.message}")
            }
        }.start()
    }

    fun sendQuickStatus(status: QuickStatus) {
        Thread {
            try {
                val payload = JSONObject().apply {
                    put("id", status.id); put("type", status.type)
                    put("senderID", status.senderID); put("senderName", status.senderName)
                    put("zone", status.zone); put("note", status.note)
                    put("timestamp", status.timestamp)
                }
                val msg = JSONObject().apply {
                    put("msgType", "quick_status"); put("device_id", deviceID); put("payload", payload.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) { Log.e(TAG, "Send quick status failed: ${e.message}") }
        }.start()
    }

    fun sendTaskUpdate(task: TaskAssignment) {
        Thread {
            try {
                val payload = JSONObject().apply {
                    put("id", task.id); put("title", task.title); put("detail", task.detail)
                    put("assigneeID", task.assigneeID); put("assigneeName", task.assigneeName)
                    put("zone", task.zone); put("priority", task.priority)
                    put("status", task.status); put("createdAt", task.createdAt)
                    if (task.dueTime != null) put("dueTime", task.dueTime)
                }
                val msg = JSONObject().apply {
                    put("msgType", "task_update"); put("device_id", deviceID); put("payload", payload.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) { Log.e(TAG, "Send task update failed: ${e.message}") }
        }.start()
    }

    fun sendHazardReport(report: HazardReport) {
        Thread {
            try {
                val payload = JSONObject().apply {
                    put("id", report.id); put("hazardType", report.hazardType)
                    put("description", report.description)
                    put("reporterID", report.reporterID); put("reporterName", report.reporterName)
                    put("zone", report.zone); put("severity", report.severity)
                    put("timestamp", report.timestamp)
                }
                val msg = JSONObject().apply {
                    put("msgType", "hazard_report"); put("device_id", deviceID); put("payload", payload.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) { Log.e(TAG, "Send hazard report failed: ${e.message}") }
        }.start()
    }

    fun sendReinforcementRequest(request: ReinforcementRequest) {
        Thread {
            try {
                val respondedBy = JSONArray().apply {
                    request.respondedBy.forEach { put(it) }
                }
                val payload = JSONObject().apply {
                    put("id", request.id); put("fromTeam", request.fromTeam)
                    put("message", request.message); put("location", request.location)
                    put("timestamp", request.time / 1000.0)
                    put("status", request.status.chinese); put("respondedBy", respondedBy)
                }
                val msg = JSONObject().apply {
                    put("msgType", "reinforcement_request"); put("device_id", deviceID); put("payload", payload.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) { Log.e(TAG, "Send reinforcement request failed: ${e.message}") }
        }.start()
    }

    fun sendReinforcementReply(request: ReinforcementRequest) {
        Thread {
            try {
                val respondedBy = JSONArray().apply {
                    request.respondedBy.forEach { put(it) }
                }
                val payload = JSONObject().apply {
                    put("id", request.id); put("fromTeam", request.fromTeam)
                    put("message", request.message); put("location", request.location)
                    put("timestamp", request.time / 1000.0)
                    put("status", request.status.chinese); put("respondedBy", respondedBy)
                }
                val msg = JSONObject().apply {
                    put("msgType", "reinforcement_reply"); put("device_id", deviceID); put("payload", payload.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) { Log.e(TAG, "Send reinforcement reply failed: ${e.message}") }
        }.start()
    }

    fun sendPatientReport(report: PatientReport, deviceID: String) {
        Thread {
            try {
                val dataObj = JSONObject().apply {
                    put("id", report.patientId)
                    put("national_id", report.nationalId)
                    put("name", report.name)
                    put("birth_date", report.birthDate)
                    if (report.age != null) put("age", report.age)
                    put("location", report.location)
                    put("breathing_rate", report.breathingRate)
                    put("capillary_refill", report.capillaryRefill)
                    put("can_follow_commands", report.canFollowCommands)
                    put("notes", report.notes)
                    put("device_id", deviceID)
                    if (report.gpsLat != null && report.gpsLon != null) {
                        put("gps", JSONObject().apply {
                            put("lat", report.gpsLat)
                            put("lon", report.gpsLon)
                        })
                    }
                }
                val msg = JSONObject().apply {
                    put("msgType", "patient"); put("device_id", deviceID); put("payload", dataObj.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) { Log.e(TAG, "Send patient report failed: ${e.message}") }
        }.start()
    }

    fun sendLocation(lat: Double, lon: Double, accuracy: Float, role: String, name: String, deviceID: String) {
        Thread {
            try {
                val dataObj = JSONObject().apply {
                    put("lat", lat); put("lon", lon); put("accuracy", accuracy.toDouble())
                    put("role", role); put("name", name)
                }
                val inner = JSONObject().apply {
                    put("type", "location")
                    put("data", dataObj)
                    put("device_id", deviceID)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US).format(java.util.Date()))
                }
                val msg = JSONObject().apply {
                    put("msgType", "location"); put("device_id", deviceID); put("payload", inner.toString())
                }
                sendRaw(msg.toString())
            } catch (e: Exception) { Log.e(TAG, "Send location failed: ${e.message}") }
        }.start()
    }

    fun sendRadioControl(action: String, senderName: String) {
        Thread {
            try {
                val payload = JSONObject().apply {
                    put("action", action)
                    put("senderName", senderName)   // camelCase for Mac/iOS HQ
                    put("sender_name", senderName)   // snake_case for Android HQ
                    put("device_id", senderName)
                }
                val msg = JSONObject().apply {
                    put("msgType", "radio_control"); put("device_id", deviceID); put("payload", payload.toString())
                }
                sendRaw(msg.toString())
                Log.d(TAG, "Sent radio_control: action=$action sender=$senderName")
            } catch (e: Exception) { Log.e(TAG, "Send radio control failed: ${e.message}") }
        }.start()
    }

    /** 發送原始 JSON（SOS / 照片等直接封包），回傳是否成功 */
    fun sendRawJSON(json: JSONObject, onResult: ((Boolean) -> Unit)? = null) {
        Thread {
            try {
                val ok = sendRaw(json.toString())
                onResult?.invoke(ok)
            } catch (e: Exception) {
                Log.e(TAG, "SendRawJSON failed: ${e.message}")
                onResult?.invoke(false)
            }
        }.start()
    }

    fun sendMessageAck(messageId: String, messageType: String, deviceID: String) {
        Thread {
            try {
                val dataObj = JSONObject().apply {
                    put("message_id", messageId)
                    put("message_type", messageType)
                }
                val msg = JSONObject().apply {
                    put("type", "message_ack")
                    put("device_id", deviceID)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US).format(java.util.Date()))
                    put("data", dataObj)
                }
                sendRawJSON(msg)
            } catch (e: Exception) { Log.e(TAG, "Send message_ack failed: ${e.message}") }
        }.start()
    }

    fun sendTextBroadcast(message: String, senderName: String, priority: String = "normal", deviceID: String) {
        Thread {
            try {
                val dataObj = JSONObject().apply {
                    put("message", message)
                    put("sender_name", senderName)
                    put("priority", priority)
                }
                val msg = JSONObject().apply {
                    put("type", "text_broadcast")
                    put("device_id", deviceID)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US).format(java.util.Date()))
                    put("data", dataObj)
                }
                sendRawJSON(msg)
            } catch (e: Exception) { Log.e(TAG, "Send text_broadcast failed: ${e.message}") }
        }.start()
    }

    fun sendTranslateRequest(text: String, sourceLang: String = "auto", targetLang: String = "en", deviceID: String) {
        Thread {
            try {
                val dataObj = JSONObject().apply {
                    put("text", text)
                    put("source_lang", sourceLang)
                    put("target_lang", targetLang)
                    put("context", "medical")
                }
                val msg = JSONObject().apply {
                    put("type", "translate_request")
                    put("device_id", deviceID)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US).format(java.util.Date()))
                    put("data", dataObj)
                }
                sendRawJSON(msg)
            } catch (e: Exception) { Log.e(TAG, "Send translate_request failed: ${e.message}") }
        }.start()
    }

    fun sendSOS(senderName: String, deviceID: String) {
        Thread {
            try {
                val msg = JSONObject().apply {
                    put("type", "sos")
                    put("device_id", deviceID)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US).format(java.util.Date()))
                    put("data", JSONObject().apply {
                        put("sender_name", senderName)
                    })
                }
                sendRawJSON(msg)
            } catch (e: Exception) { Log.e(TAG, "Send SOS failed: ${e.message}") }
        }.start()
    }

    fun sendSOSCancel(senderName: String, deviceID: String) {
        Thread {
            try {
                val msg = JSONObject().apply {
                    put("type", "sos_cancel")
                    put("device_id", deviceID)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US).format(java.util.Date()))
                    put("data", JSONObject().apply {
                        put("sender_name", senderName)
                    })
                }
                sendRawJSON(msg)
            } catch (e: Exception) { Log.e(TAG, "Send SOS cancel failed: ${e.message}") }
        }.start()
    }

    fun sendPatientWarning(patientId: String, warningType: String, deviceID: String) {
        Thread {
            try {
                val msg = JSONObject().apply {
                    put("type", "patient_warning")
                    put("device_id", deviceID)
                    put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US).format(java.util.Date()))
                    put("data", JSONObject().apply {
                        put("patient_id", patientId)
                        put("warning_type", warningType)
                    })
                }
                sendRawJSON(msg)
            } catch (e: Exception) { Log.e(TAG, "Send patient_warning failed: ${e.message}") }
        }.start()
    }

    private fun sendRaw(data: String): Boolean {
        val w = writer
        if (w == null) {
            Log.w(TAG, "Send failed: writer is null")
            _isConnected.value = false
            return false
        }
        return try {
            w.write(data)
            w.write("\n")
            w.flush()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Send failed: ${e.message}")
            _isConnected.value = false
            false
        }
    }

    private fun disconnect() {
        stopPing()
        receiveThread?.interrupt()
        receiveThread = null
        reconnectThread?.interrupt()
        reconnectThread = null
        try { writer?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        writer = null
        socket = null
        _isConnected.value = false
    }

    private var reconnectAttempt = 0
    private val maxReconnectDelay = 30_000L  // 最大 30 秒

    private fun scheduleReconnect(host: String, port: Int) {
        reconnectThread = Thread {
            try {
                val delay = (3000L * (1L shl reconnectAttempt.coerceAtMost(4)))
                    .coerceAtMost(maxReconnectDelay)  // 3s, 6s, 12s, 24s, 30s
                reconnectAttempt++
                Log.d(TAG, "Reconnect attempt $reconnectAttempt in ${delay}ms")
                var waited = 0L
                while (waited < delay) {
                    if (Thread.currentThread().isInterrupted) return@Thread
                    Thread.sleep(200)
                    waited += 200
                }
                connectToServer(host, port)
            } catch (_: InterruptedException) {}
        }
        reconnectThread?.start()
    }

    /** 設定裝置 ID（用於 ping 識別） */
    var deviceID: String = "unknown"

    private fun startPing() {
        stopPing()
        pingTimer = java.util.Timer().also {
            it.scheduleAtFixedRate(object : java.util.TimerTask() {
                override fun run() {
                    try {
                        val msg = org.json.JSONObject().apply {
                            put("msgType", "ping")
                            put("device_id", deviceID)
                            put("payload", org.json.JSONObject().apply {
                                put("ts", System.currentTimeMillis() / 1000.0)
                                put("device_id", deviceID)
                            }.toString())
                        }
                        sendRaw(msg.toString())
                    } catch (e: Exception) {
                        Log.d(TAG, "Ping failed: ${e.message}")
                    }
                }
            }, 30000, 30000)
        }
    }

    private fun stopPing() {
        pingTimer?.cancel()
        pingTimer = null
    }
}

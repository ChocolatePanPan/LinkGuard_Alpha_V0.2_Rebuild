package com.linkguard.hq.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import com.linkguard.hq.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.*
import java.net.Socket
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * HQ Peer 用戶端
 * 以 "hq_peer" 角色透過 WiFi 連線到另一台裝置的 HQCommandServer，
 * 同步命令、聊天、災害狀態等，並可透過 hq_command 送出命令。
 */
class HQPeerClient(private val context: Context) {

    companion object {
        private const val TAG = "HQPeerClient"
        private const val PORT = 8930
        private const val SERVICE_TYPE = "_linkguard-hq._tcp."
    }

    // 狀態
    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching

    private val _connectedServerName = MutableStateFlow("")
    val connectedServerName: StateFlow<String> = _connectedServerName

    private val _discoveredServers = MutableStateFlow<List<DiscoveredHQServer>>(emptyList())
    val discoveredServers: StateFlow<List<DiscoveredHQServer>> = _discoveredServers

    // 從伺服器同步的狀態
    private val _sentCommands = MutableStateFlow<List<WiFiCommand>>(emptyList())
    val sentCommands: StateFlow<List<WiFiCommand>> = _sentCommands

    private val _chatMessages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages

    private val _disasterSite = MutableStateFlow<DisasterSite?>(null)
    val disasterSite: StateFlow<DisasterSite?> = _disasterSite

    private val _pwsAlerts = MutableStateFlow<List<PWSAlert>>(emptyList())
    val pwsAlerts: StateFlow<List<PWSAlert>> = _pwsAlerts

    private val _personnelAssignments = MutableStateFlow<List<PersonnelAssignment>>(emptyList())
    val personnelAssignments: StateFlow<List<PersonnelAssignment>> = _personnelAssignments

    private val _briefings = MutableStateFlow<List<BriefingReport>>(emptyList())
    val briefings: StateFlow<List<BriefingReport>> = _briefings

    // 本機身份
    var myID: String = "HQ-Peer"
    var myName: String = "HQ 指揮官"

    private var nsdManager: NsdManager? = null
    private var socket: Socket? = null
    private var writer: BufferedWriter? = null
    private var readThread: Thread? = null
    private val running = AtomicBoolean(false)

    // MARK: - 發現 HQ 伺服器（NSD Browse）

    @Volatile private var activeListener: NsdManager.DiscoveryListener? = null

    fun startBrowsing() {
        // 先安全停止任何殘留的 discovery
        stopBrowsing()
        _discoveredServers.value = emptyList()

        try {
            val mgr = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
            if (mgr == null) {
                Log.e(TAG, "NSD service not available")
                return
            }
            nsdManager = mgr
            // 每次建立新 listener 避免 "listener already in use" 例外
            val listener = createDiscoveryListener()
            activeListener = listener
            mgr.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            _isSearching.value = true
        } catch (e: Exception) {
            Log.e(TAG, "startBrowsing failed: ${e.message}")
            _isSearching.value = false
            nsdManager = null
        }
    }

    fun stopBrowsing() {
        val listener = activeListener
        activeListener = null
        try { nsdManager?.stopServiceDiscovery(listener ?: return) } catch (_: Exception) {}
        _isSearching.value = false
        nsdManager = null
    }

    private fun createDiscoveryListener() = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(serviceType: String) {
            Log.d(TAG, "Discovery started")
        }
        override fun onDiscoveryStopped(serviceType: String) {
            _isSearching.value = false
        }
        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "Discovery failed: $errorCode")
            _isSearching.value = false
        }
        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "Stop discovery failed: $errorCode")
        }

        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            try {
                // 解析服務以取得 host/port
                nsdManager?.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        Log.e(TAG, "Resolve failed: $errorCode")
                    }
                    override fun onServiceResolved(info: NsdServiceInfo) {
                        try {
                            val host = info.host?.hostAddress ?: return
                            val server = DiscoveredHQServer(
                                name = info.serviceName,
                                host = host,
                                port = info.port
                            )
                            val current = _discoveredServers.value.toMutableList()
                            if (current.none { it.host == host }) {
                                current.add(server)
                                _discoveredServers.value = current
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "onServiceResolved error: ${e.message}")
                        }
                    }
                })
            } catch (e: Exception) {
                Log.e(TAG, "onServiceFound error: ${e.message}")
            }
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            try {
                _discoveredServers.value = _discoveredServers.value
                    .filter { it.name != serviceInfo.serviceName }
            } catch (e: Exception) {
                Log.e(TAG, "onServiceLost error: ${e.message}")
            }
        }
    }

    // MARK: - 連線

    fun connect(server: DiscoveredHQServer) {
        disconnect()
        running.set(true)
        Thread {
            try {
                val s = Socket(server.host, server.port)
                socket = s
                writer = BufferedWriter(OutputStreamWriter(s.getOutputStream(), Charsets.UTF_8))
                _isConnected.value = true
                _connectedServerName.value = server.name
                Log.d(TAG, "Connected to ${server.name} @ ${server.host}:${server.port}")

                sendHello()
                readLoop(s)
            } catch (e: Exception) {
                Log.e(TAG, "Connection error: ${e.message}")
                _isConnected.value = false
                _connectedServerName.value = ""
            }
        }.also { readThread = it }.start()
    }

    fun disconnect() {
        running.set(false)
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        writer = null
        readThread?.interrupt()
        readThread = null
        _isConnected.value = false
        _connectedServerName.value = ""
    }

    // MARK: - 握手

    private fun sendHello() {
        val payload = JSONObject().apply {
            put("role", "hq_peer")
            put("id", myID)
            put("name", myName)
        }.toString()
        send(buildWiFiMessage("hello", payload))
    }

    // MARK: - 送出命令

    fun sendCommand(cmd: WiFiCommand) {
        val payload = JSONObject().apply {
            put("id", cmd.id)
            put("type", cmd.type)
            put("priority", cmd.priority)
            put("title", cmd.title)
            put("detail", cmd.detail)
            put("sender", cmd.sender)
            put("timestamp", cmd.timestamp)
        }.toString()
        send(buildWiFiMessage("hq_command", payload))
    }

    fun sendChat(chat: ChatMessage) {
        val payload = JSONObject().apply {
            put("id", chat.id)
            put("senderID", chat.senderID)
            put("senderName", chat.senderName)
            if (chat.recipientID != null) put("recipientID", chat.recipientID)
            put("content", chat.content)
            put("timestamp", chat.timestamp)
            put("mentions", JSONArray().apply { chat.mentions.forEach { put(it) } })
        }.toString()
        send(buildWiFiMessage("chat_message", payload))
        val list = _chatMessages.value.toMutableList()
        list.add(chat)
        _chatMessages.value = if (list.size > 500) list.takeLast(300) else list
    }

    /** 以任意 msgType 送出原始 JSON（如 patient 回報）*/
    fun sendRaw(msgType: String, payloadJson: String) {
        send(buildWiFiMessage(msgType, payloadJson))
    }

    /** 任務指派中繼 */
    fun sendTaskAssignment(task: TaskAssignment) {
        val payload = JSONObject().apply {
            put("id", task.id)
            put("title", task.title)
            put("detail", task.detail)
            put("assignedDeviceID", task.assignedDeviceID)
            put("assignedName", task.assignedName)
            put("priority", task.priority.value)
            put("timestamp", task.timestamp)
        }.toString()
        send(buildWiFiMessage("task_assignment", payload))
    }

    /** 計時器啟動中繼 */
    fun sendTimerStart(id: String, label: String, durationSeconds: Int) {
        val payload = JSONObject().apply {
            put("id", id)
            put("label", label)
            put("durationSeconds", durationSeconds)
        }.toString()
        send(buildWiFiMessage("timer_sync", payload))
    }

    /** 計時器取消中繼 */
    fun sendTimerCancel(timerId: String) {
        val payload = JSONObject().apply {
            put("id", timerId)
        }.toString()
        send(buildWiFiMessage("timer_cancel", payload))
    }

    // MARK: - 接收迴圈

    private fun readLoop(s: Socket) {
        val buffer = StringBuilder()
        try {
            val reader = BufferedReader(InputStreamReader(s.getInputStream(), Charsets.UTF_8))
            val charBuf = CharArray(4096)
            while (running.get() && !s.isClosed) {
                val bytesRead = reader.read(charBuf)
                if (bytesRead == -1) break
                buffer.append(charBuf, 0, bytesRead)
                while (true) {
                    val nlIdx = buffer.indexOf('\n')
                    if (nlIdx < 0) break
                    val line = buffer.substring(0, nlIdx).trim()
                    buffer.delete(0, nlIdx + 1)
                    if (line.isNotEmpty()) handleMessage(line)
                }
            }
        } catch (e: Exception) {
            if (running.get()) Log.d(TAG, "Read loop ended: ${e.message}")
        } finally {
            _isConnected.value = false
        }
    }

    private fun handleMessage(line: String) {
        try {
            val json = JSONObject(line)
            val msgType = json.optString("msgType", "")
            val payload = json.optString("payload", "")

            when (msgType) {
                "command" -> {
                    val c = JSONObject(payload)
                    val cmd = WiFiCommand(
                        id = c.optString("id", UUID.randomUUID().toString()),
                        type = c.optString("type", ""),
                        priority = c.optInt("priority", 0),
                        title = c.optString("title", ""),
                        detail = c.optString("detail", ""),
                        sender = c.optString("sender", "")
                    )
                    val list = _sentCommands.value.toMutableList()
                    if (list.none { it.id == cmd.id }) {
                        list.add(0, cmd)
                        _sentCommands.value = if (list.size > 100) list.take(100) else list
                    }
                }
                "chat_message" -> {
                    val c = JSONObject(payload)
                    val mentionsList = mutableListOf<String>()
                    c.optJSONArray("mentions")?.let { arr ->
                        for (i in 0 until arr.length()) mentionsList.add(arr.optString(i))
                    }
                    val chat = ChatMessage(
                        id = c.optString("id", UUID.randomUUID().toString()),
                        senderID = c.optString("senderID", ""),
                        senderName = c.optString("senderName", ""),
                        content = c.optString("content", ""),
                        timestamp = c.optDouble("timestamp", System.currentTimeMillis() / 1000.0),
                        mentions = mentionsList
                    )
                    val list = _chatMessages.value.toMutableList()
                    if (list.none { it.id == chat.id }) {
                        list.add(chat)
                        _chatMessages.value = if (list.size > 500) list.takeLast(300) else list
                    }
                }
                "pws_alert" -> {
                    // 簡單序列化: 只保留 isActive/title
                    val a = JSONObject(payload)
                    val alert = PWSAlert(
                        id = a.optString("id", UUID.randomUUID().toString()),
                        alertType = PWSAlertType.entries.find { it.key == a.optString("alertType") }
                            ?: PWSAlertType.EARTHQUAKE,
                        severity = PWSSeverity.entries.find { it.key == a.optString("severity") }
                            ?: PWSSeverity.INFO,
                        title = a.optString("title", ""),
                        content = a.optString("content", ""),
                        publisher = a.optString("publisher", ""),
                        publishTime = a.optDouble("publishTime", System.currentTimeMillis() / 1000.0),
                        isActive = a.optBoolean("isActive", true)
                    )
                    val list = _pwsAlerts.value.toMutableList()
                    val idx = list.indexOfFirst { it.id == alert.id }
                    if (idx >= 0) list[idx] = alert else list.add(0, alert)
                    _pwsAlerts.value = list
                }
                else -> { /* 其他類型後續可擴充 */ }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Message parse error: ${e.message}")
        }
    }

    // MARK: - 工具

    private fun send(data: String) {
        try {
            synchronized(writer ?: return) {
                writer?.write(data)
                writer?.flush()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Send error: ${e.message}")
        }
    }

    private fun buildWiFiMessage(msgType: String, payloadJson: String): String =
        JSONObject().apply { put("msgType", msgType); put("payload", payloadJson) }.toString() + "\n"
}

// MARK: - 已發現的 HQ 伺服器
data class DiscoveredHQServer(
    val name: String,
    val host: String,
    val port: Int
)

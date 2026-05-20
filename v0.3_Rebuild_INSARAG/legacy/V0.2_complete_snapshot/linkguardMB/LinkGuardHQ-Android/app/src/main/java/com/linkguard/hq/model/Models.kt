package com.linkguard.hq.model

import androidx.compose.ui.graphics.Color

// === 災害狀態模型 ===

enum class CollapseType(val key: String, val label: String) {
    PARTIAL("partial", "部分倒塌"), PANCAKE("pancake", "層疊式倒塌"), LEAN("lean", "傾斜倒塌"),
    V_SHAPE("vShape", "V型倒塌"), NONE("none", "未倒塌"), UNKNOWN("unknown", "未知");

    companion object {
        fun fromKey(key: String): CollapseType = entries.firstOrNull { it.key == key } ?: UNKNOWN
    }
}

enum class FloorCondition(val key: String, val label: String) {
    COLLAPSED("collapsed", "完全倒塌"), PARTIAL("partial", "部分倒塌"), ACCESSIBLE("accessible", "可進入"),
    CLEARED("cleared", "已清除"), RESTRICTED("restricted", "限制進入"), UNKNOWN("unknown", "未知");

    companion object {
        fun fromKey(key: String): FloorCondition = entries.firstOrNull { it.key == key } ?: UNKNOWN
    }

    val color: Color get() = when (this) {
        COLLAPSED  -> Color(0xFFD13838)
        PARTIAL    -> Color(0xFFB8941F)
        ACCESSIBLE -> Color(0xFF14B840)
        CLEARED    -> Color(0xFF1AAD8C)
        RESTRICTED -> Color(0xFFD18014)
        UNKNOWN    -> Color.Gray
    }
}

enum class ZoneStatus(val key: String, val label: String) {
    ACTIVE("active", "搜救中"), STANDBY("standby", "待命"), CLEARED("cleared", "已清除"),
    DANGEROUS("dangerous", "危險區"), RESTRICTED("restricted", "限制區");

    companion object {
        fun fromKey(key: String): ZoneStatus = entries.firstOrNull { it.key == key } ?: STANDBY
    }

    val color: Color get() = when (this) {
        ACTIVE     -> Color(0xFF14B840)
        STANDBY    -> Color(0xFFB8941F)
        CLEARED    -> Color(0xFF1AAD8C)
        DANGEROUS  -> Color(0xFFD13838)
        RESTRICTED -> Color(0xFFD18014)
    }
}

enum class HazardType(val key: String, val label: String, val icon: String) {
    GAS_LEAK("gasLeak", "瓦斯洩漏", "GAS"), FIRE("fire", "火災", "FIR"), FLOODING("flooding", "淹水", "FLD"),
    STRUCTURAL("structural", "結構不穩", "STR"), ELECTRICAL("electrical", "電氣危害", "ELC"), CHEMICAL("chemical", "化學品洩漏", "CHM");

    companion object {
        fun fromKey(key: String): HazardType? = entries.firstOrNull { it.key == key }
    }
}

data class FloorStatus(
    val id: String,
    var condition: FloorCondition = FloorCondition.UNKNOWN,
    var assignedTeam: String = "",
    var note: String = ""
)

data class RescueZone(
    val id: String = java.util.UUID.randomUUID().toString(),
    var name: String,
    var status: ZoneStatus = ZoneStatus.STANDBY,
    var assignedPersonnel: List<String> = emptyList(),
    var hazards: List<HazardType> = emptyList(),
    var note: String = ""
)

data class EntryPoint(
    val id: String = java.util.UUID.randomUUID().toString(),
    var name: String,
    var description: String = "",
    var isAccessible: Boolean = true
)

data class DisasterSite(
    var buildingName: String = "",
    var address: String = "",
    var aboveGroundFloors: Int = 1,
    var undergroundFloors: Int = 0,
    var collapseType: CollapseType = CollapseType.UNKNOWN,
    var floors: List<FloorStatus> = emptyList(),
    var zones: List<RescueZone> = emptyList(),
    var hazards: List<HazardType> = emptyList(),
    var entryPoints: List<EntryPoint> = emptyList(),
    var rallyPoint: String = "",
    var note: String = "",
    var lastUpdated: Double = System.currentTimeMillis() / 1000.0
)

// === 人員配置 ===

enum class PersonnelRole(val key: String, val label: String, val icon: String) {
    SEARCH("search", "搜索", "[搜索]"), RESCUE("rescue", "救援", "[救援]"), MEDICAL("medical", "醫療", "[醫療]"),
    LOGISTICS("logistics", "後勤", "[後勤]"), SAFETY("safety", "安全官", "[安全]"), COMMANDER("commander", "指揮", "[指揮]"), SUPPORT("support", "支援", "[支援]");

    companion object {
        fun fromKey(key: String): PersonnelRole = entries.firstOrNull { it.key == key } ?: SEARCH
    }
}

data class PersonnelAssignment(
    val id: String = java.util.UUID.randomUUID().toString(),
    var name: String,
    var nickname: String? = null,
    var assignedZone: String = "",
    var assignedFloor: String = "",
    var role: PersonnelRole = PersonnelRole.SEARCH,
    var timestamp: Double = System.currentTimeMillis() / 1000.0
) {
    /** 顯示名稱：暱稱(ID) 或 名字(ID) */
    val displayLabel: String get() = "${nickname?.takeIf { it.isNotBlank() } ?: name} (${id.takeLast(8)})"
}

// === 通訊 ===

data class ChatMessage(
    val id: String = java.util.UUID.randomUUID().toString(),
    val senderID: String,
    val senderName: String,
    val recipientID: String? = null,
    val content: String,
    val timestamp: Double = System.currentTimeMillis() / 1000.0,
    var isRead: Boolean = false,
    val mentions: List<String> = emptyList()
) {
    val isBroadcast: Boolean get() = recipientID == null
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === PWS 警報 ===

enum class PWSAlertType(val key: String, val label: String, val icon: String) {
    EARTHQUAKE("earthquake", "地震", "EQ"), AFTERSHOCK("aftershock", "餘震", "AS"), TSUNAMI("tsunami", "海嘯", "TN"),
    TYPHOON("typhoon", "颱風", "TY"), FLOOD("flood", "洪水", "FL"), LANDSLIDE("landslide", "土石流", "LS"), OTHER("other", "其他", "!!");

    companion object {
        fun fromKey(key: String): PWSAlertType = entries.firstOrNull { it.key == key } ?: OTHER
    }
}

enum class PWSSeverity(val key: String, val value: Int, val label: String) {
    INFO("info", 0, "資訊"), MINOR("minor", 1, "輕微"), MODERATE("moderate", 2, "中等"),
    SEVERE("severe", 3, "嚴重"), EXTREME("extreme", 4, "極端");

    companion object {
        fun fromKey(key: String): PWSSeverity = entries.firstOrNull { it.key == key } ?: INFO
    }

    val color: Color get() = when (this) {
        INFO     -> Color(0xFF1AAD8C)
        MINOR    -> Color(0xFF14B840)
        MODERATE -> Color(0xFFB8941F)
        SEVERE   -> Color(0xFFD18014)
        EXTREME  -> Color(0xFFD13838)
    }
}

data class PWSAlert(
    val id: String = java.util.UUID.randomUUID().toString(),
    var alertType: PWSAlertType,
    var title: String,
    var content: String,
    var severity: PWSSeverity,
    var publisher: String = "HQ",
    var publishTime: Double = System.currentTimeMillis() / 1000.0,
    var expireTime: Double? = null,
    var isActive: Boolean = true
)

// === 會報 ===

enum class BriefingType(val key: String, val label: String) {
    INITIAL("initial", "初期報告"), PROGRESS("progress", "進度報告"), SHIFT("shift", "交接報告"), FINAL("final", "結案報告");

    companion object {
        fun fromKey(key: String): BriefingType = entries.firstOrNull { it.key == key } ?: PROGRESS
    }
}

data class BriefingSection(
    val id: String = java.util.UUID.randomUUID().toString(),
    var title: String,
    var content: String = ""
)

data class BriefingReport(
    val id: String = java.util.UUID.randomUUID().toString(),
    var title: String,
    var type: BriefingType = BriefingType.PROGRESS,
    var author: String = "HQ",
    var timestamp: Double = System.currentTimeMillis() / 1000.0,
    var sections: List<BriefingSection> = emptyList()
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("MM/dd HH:mm", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === 個人通知 ===

data class PersonalNotification(
    val id: String = java.util.UUID.randomUUID().toString(),
    var targetDeviceID: String,
    var title: String,
    var content: String,
    var timestamp: Double = System.currentTimeMillis() / 1000.0,
    var isRead: Boolean = false
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === 命令優先級 ===
enum class CommandPriority(val value: Int, val label: String) {
    ROUTINE(0, "一般"),
    URGENT(1, "緊急"),
    CRITICAL(2, "最高");

    val color: Color get() = when (this) {
        ROUTINE  -> Color(0xFF1AAD8C)
        URGENT   -> Color(0xFFB8941F)
        CRITICAL -> Color(0xFFD13838)
    }
}

// === 命令類型 ===
enum class CommandType(val label: String, val key: String) {
    SEARCH_AREA("搜索區域指派", "search"),
    STANDBY("原地待命", "standby"),
    SUPPORT("支援請求", "support"),
    STATUS_REPORT("狀態回報", "report"),
    EVACUATION("撤離命令", "evacuation");

    val icon: String get() = when (this) {
        SEARCH_AREA   -> "[搜索]"
        STANDBY       -> "[待命]"
        SUPPORT       -> "[支援]"
        STATUS_REPORT -> "[回報]"
        EVACUATION    -> "[撤離]"
    }
}

// === WiFi 命令 ===
data class WiFiCommand(
    val id: String = java.util.UUID.randomUUID().toString(),
    val type: String,
    val priority: Int,
    val title: String,
    val detail: String,
    val sender: String,
    val timestamp: Double = System.currentTimeMillis() / 1000.0
)

// === WiFi 消息封包 ===
data class WiFiMessage(
    val msgType: String,
    val payload: String
)

// === 已發送命令記錄 ===
data class SentCommand(
    val id: String = java.util.UUID.randomUUID().toString(),
    val type: CommandType,
    val priority: CommandPriority,
    val title: String,
    val detail: String,
    val sender: String,
    val time: Long = System.currentTimeMillis()
) {
    val timeText: String
        get() {
            val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            return sdf.format(java.util.Date(time))
        }
}

// === HQ 同伴資訊（其他指揮中心裝置）===
data class HQPeerInfo(
    val id: String,          // clientId（連線識別碼）
    val peerID: String,      // 對端裝置 ID
    val peerName: String,    // 顯示名稱
    val connectedAt: Long = System.currentTimeMillis()
)

// === 連線的外勤單位 ===
data class ConnectedFieldUnit(
    val id: String,
    var deviceID: String = "--",
    var deptCode: String = "--",
    var battery: Int = 0,
    var bleConnected: Boolean = false,
    var lastReport: Long = System.currentTimeMillis(),
    var victims: List<VictimSummary> = emptyList(),
    var teamMembers: List<TeamSummary> = emptyList(),
    var sosCount: Int = 0
) {
    val isOnline: Boolean
        get() = (System.currentTimeMillis() - lastReport) < 45000

    val lastReportText: String
        get() {
            val interval = (System.currentTimeMillis() - lastReport) / 1000
            return when {
                interval < 5    -> "剛剛"
                interval < 60   -> "${interval} 秒前"
                interval < 3600 -> "${interval / 60} 分鐘前"
                else            -> "${interval / 3600} 小時前"
            }
        }
}

// === 外勤回報的受困者摘要 ===
data class VictimSummary(
    val id: String,
    val heartRate: Int,
    val battery: Int,
    val rssi: Double,
    val isSOS: Boolean,
    val isOnline: Boolean
)

// === 受困者處置狀態 ===
enum class VictimStatus(val value: Int, val label: String) {
    PENDING(0, "未處理"),
    ON_SCENE(1, "現場處理中"),
    WAITING_AMBULANCE(2, "等待救護車"),
    EN_ROUTE(3, "送醫途中"),
    HOSPITALIZED(4, "已送醫"),
    RESCUED(5, "已脫困"),
    DECEASED(6, "死亡確認");
}

// === 受困者優先級（HQ 設定） ===
enum class VictimPriority(val value: Int, val label: String) {
    UNSET(0, "未設定"),
    LOW(1, "低"),
    MEDIUM(2, "中"),
    HIGH(3, "高"),
    CRITICAL(4, "緊急");
}

data class HQVictimRecord(
    val id: String,
    var heartRate: Int,
    var battery: Int,
    var rssi: Double,
    var isSOS: Boolean,
    var isOnline: Boolean,
    var sourceDeviceID: String,
    var sourceDeptCode: String,
    var priority: VictimPriority = VictimPriority.UNSET,
    var status: VictimStatus = VictimStatus.PENDING,
    var note: String = "",
    var description: String = "",
    var patientName: String = "",
    var location: String = "",
    var hasPatientReport: Boolean = false
)

// === 外勤回報的團隊摘要 ===
data class TeamSummary(
    val id: String,
    val deptCode: String,
    val battery: Int,
    val rssi: Double,
    val isOnline: Boolean,
    val victimCount: Int
)

// === 快捷命令 ===
data class QuickCommand(
    val type: CommandType,
    val priority: CommandPriority,
    val title: String,
    val detail: String
)

val defaultQuickCommands = listOf(
    QuickCommand(CommandType.SEARCH_AREA, CommandPriority.ROUTINE, "開始搜索", "請全體搜索隊伍開始展開各分區搜索作業"),
    QuickCommand(CommandType.STANDBY, CommandPriority.ROUTINE, "原地待命", "暫停所有作業，等待進一步指令"),
    QuickCommand(CommandType.EVACUATION, CommandPriority.CRITICAL, "全員撤離", "發布撤離命令，所有人員立即撤離至集結點"),
    QuickCommand(CommandType.STATUS_REPORT, CommandPriority.ROUTINE, "回報現況", "各隊伍請回報目前人員位置及搜索進度"),
    QuickCommand(CommandType.SUPPORT, CommandPriority.URGENT, "請求醫療支援", "需要醫療人員至指定地點進行傷患處理"),
    QuickCommand(CommandType.SUPPORT, CommandPriority.URGENT, "請求重機具", "需要吊車或破碎機至現場協助排除障礙"),
    QuickCommand(CommandType.STANDBY, CommandPriority.ROUTINE, "輪替休息", "外圍待命隊接手，前線隊伍後撤休息補水"),
    QuickCommand(CommandType.STATUS_REPORT, CommandPriority.ROUTINE, "集合點報", "全體人員至集結點集合進行人員清點"),
    QuickCommand(CommandType.SUPPORT, CommandPriority.URGENT, "危險警告", "偵測到結構不穩/瓦斯外洩，請注意安全"),
    QuickCommand(CommandType.SEARCH_AREA, CommandPriority.ROUTINE, "通訊測試", "各隊伍確認通訊是否正常，依序回報")
)

// === 傷員表單 ===

data class PatientReport(
    val patient_id: String = "P${System.currentTimeMillis()}",
    val national_id: String = "",
    val name: String = "",
    val birth_date: String = "",
    val age: Int? = null,
    val location: String,
    val breathing_rate: Int,       // -1 代表無呼吸
    val capillary_refill: Double,  // -1 代表無脈搏
    val can_follow_commands: Boolean,
    val gps_lat: Double? = null,
    val gps_lon: Double? = null,
    val notes: String = ""
)

// === 指揮決策 ===

data class PatientDecisionEntry(
    val id: String,
    val location: String = "",
    val priority: String = "",
    val reason: String = "",
    val totalScore: Double = 0.0,
    val startBonus: Int = 0,
    val rank: Int = 0
)

data class HQDecision(
    val decision: String,
    val patients: List<PatientDecisionEntry>,
    val timestamp: String,
    val trigger: String = "",
    val receivedAt: Long = System.currentTimeMillis(),
    val model: String = "",
    val escalated: Boolean = false
)

// === 事件日誌 ===

enum class TimelineEventType(val key: String, val label: String, val icon: String) {
    COMMAND("command", "命令", "📢"),
    DISASTER("disaster", "災情", "🏚️"),
    PERSONNEL("personnel", "人員", "👤"),
    VICTIM("victim", "受困者", "🆘"),
    SYSTEM("system", "系統", "⚙️"),
    CHAT("chat", "通訊", "💬"),
    DECISION("decision", "決策", "🎯");

    val color: Color get() = when (this) {
        COMMAND   -> Color(0xFFB8941F)
        DISASTER  -> Color(0xFFD13838)
        PERSONNEL -> Color(0xFF4066B8)
        VICTIM    -> Color(0xFF14B840)
        SYSTEM    -> Color(0xFF888888)
        CHAT      -> Color(0xFF1AAD8C)
        DECISION  -> Color(0xFFD18014)
    }

    companion object {
        fun fromKey(key: String): TimelineEventType = entries.firstOrNull { it.key == key } ?: SYSTEM
    }
}

data class TimelineEvent(
    val id: String = java.util.UUID.randomUUID().toString(),
    val eventType: TimelineEventType,
    val title: String,
    val detail: String = "",
    val timestamp: Long = System.currentTimeMillis()
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
}

// === 會報儀表板（電台報告）===

data class RadioReport(
    val id: String = java.util.UUID.randomUUID().toString(),
    val senderName: String,
    val senderDeviceID: String = "",
    val transcription: String = "",
    val timestamp: Long = System.currentTimeMillis()
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("MM/dd HH:mm", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
}

// === 任務指派 ===

enum class TaskStatus(val key: String, val label: String) {
    PENDING("pending", "待接受"),
    ACCEPTED("accepted", "已接受"),
    IN_PROGRESS("inProgress", "執行中"),
    COMPLETED("completed", "已完成"),
    CANCELLED("cancelled", "已取消");

    companion object {
        fun fromKey(key: String): TaskStatus = entries.firstOrNull { it.key == key } ?: PENDING
    }

    val color: Color get() = when (this) {
        PENDING     -> Color(0xFFB8941F)
        ACCEPTED    -> Color(0xFF4066B8)
        IN_PROGRESS -> Color(0xFFD18014)
        COMPLETED   -> Color(0xFF14B840)
        CANCELLED   -> Color(0xFFD13838)
    }
}

data class TaskAssignment(
    val id: String = java.util.UUID.randomUUID().toString(),
    var title: String,
    var detail: String = "",
    var assignedDeviceID: String = "",
    var assignedName: String = "",
    var priority: CommandPriority = CommandPriority.ROUTINE,
    var status: TaskStatus = TaskStatus.PENDING,
    var timestamp: Double = System.currentTimeMillis() / 1000.0
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === 倒數計時器 ===

data class CountdownTimerModel(
    val id: String = java.util.UUID.randomUUID().toString(),
    var label: String,
    var durationSeconds: Int,
    var remainingSeconds: Int = durationSeconds,
    var targetDeviceID: String? = null,
    var isRunning: Boolean = false
)

// === SOS 緊急警報 ===

data class SOSAlert(
    val id: String = java.util.UUID.randomUUID().toString(),
    val deviceID: String,
    val senderName: String = "",
    val lat: Double = 0.0,
    val lon: Double = 0.0,
    val timestamp: Long = System.currentTimeMillis(),
    var isAcknowledged: Boolean = false
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
}

// === 文字廣播（含已讀回條）===

data class HQTextBroadcast(
    val id: String = java.util.UUID.randomUUID().toString(),
    val message: String,
    val senderName: String = "指揮中心",
    val priority: String = "normal",
    val timestamp: Double = System.currentTimeMillis() / 1000.0,
    val readBy: MutableSet<String> = mutableSetOf(),
    val targetDeviceIDs: List<String>? = null
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === 傷患警告 ===

data class HQPatientWarning(
    val id: String = java.util.UUID.randomUUID().toString(),
    val patientID: String,
    val deviceID: String = "",
    val triageLevel: String = "",
    val timestamp: Long = System.currentTimeMillis()
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }

    val triageColor: Color get() = when (triageLevel.lowercase()) {
        "red"    -> Color(0xFFD13838)
        "yellow" -> Color(0xFFB8941F)
        "green"  -> Color(0xFF14B840)
        "black"  -> Color(0xFF333333)
        else     -> Color.Gray
    }
}

// === 電台控制 ===

data class RadioControlPayload(
    val action: String,
    val senderName: String = "",
    val deviceID: String = ""
)

// === 電台報告摘要 ===

data class RadioReportSummary(
    val reportID: String = "",
    val senderName: String = "",
    val transcription: String = "",
    val locationDesc: String = "",
    val weatherSnapshot: String = "",
    val timestamp: Long = System.currentTimeMillis()
)

// === HQ 電台報告（含來源類型）===

enum class RadioSourceType(val key: String, val label: String) {
    LIVE("live", "即時"), BRIEFING("briefing", "會報");
    companion object {
        fun fromKey(key: String): RadioSourceType = entries.firstOrNull { it.key == key } ?: LIVE
    }
}

data class HQRadioReport(
    val id: String = java.util.UUID.randomUUID().toString(),
    val senderName: String,
    val senderDeviceID: String = "",
    val sourceType: RadioSourceType = RadioSourceType.LIVE,
    val transcription: String = "",
    val timestamp: Long = System.currentTimeMillis()
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("MM/dd HH:mm", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
}

// === 危害報告 ===

enum class HazardSeverity(val key: String, val label: String) {
    LOW("low", "低"), MEDIUM("medium", "中"), HIGH("high", "高"), CRITICAL("critical", "嚴重");
    companion object {
        fun fromKey(key: String): HazardSeverity = entries.firstOrNull { it.key == key } ?: MEDIUM
    }
    val color: Color get() = when (this) {
        LOW      -> Color(0xFF14B840)
        MEDIUM   -> Color(0xFFB8941F)
        HIGH     -> Color(0xFFD18014)
        CRITICAL -> Color(0xFFD13838)
    }
}

data class HazardReport(
    val id: String = java.util.UUID.randomUUID().toString(),
    val deviceID: String = "",
    val hazardType: HazardType? = null,
    val severity: HazardSeverity = HazardSeverity.MEDIUM,
    val description: String = "",
    val lat: Double = 0.0,
    val lon: Double = 0.0,
    val timestamp: Long = System.currentTimeMillis()
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
}

// === 增援請求 ===

enum class ReinforcementStatus(val key: String, val label: String) {
    PENDING("pending", "待回覆"), ACCEPTED("accepted", "已接受"), DECLINED("declined", "已拒絕");
    companion object {
        fun fromKey(key: String): ReinforcementStatus = entries.firstOrNull { it.key == key } ?: PENDING
    }
}

data class ReinforcementRequest(
    val id: String = java.util.UUID.randomUUID().toString(),
    val fromDeviceID: String = "",
    val fromTeam: String = "",
    val message: String = "",
    val location: String = "",
    var status: ReinforcementStatus = ReinforcementStatus.PENDING,
    val respondedBy: MutableList<String> = mutableListOf(),
    val timestamp: Long = System.currentTimeMillis()
)

// === 翻譯結果 ===

data class HQTranslationResult(
    val original: String,
    val translated: String,
    val sourceLang: String = "",
    val targetLang: String = "",
    val timestamp: Long = System.currentTimeMillis()
)

// === 快速狀態 ===

enum class QuickStatusType(val key: String, val label: String, val icon: String) {
    AREA_CLEAR("area_clear", "區域安全", "✅"),
    NEED_SUPPORT("need_support", "需要支援", "🆘"),
    VICTIM_FOUND("victim_found", "發現受困者", "🔍"),
    RETREATING("retreating", "撤退中", "🏃");

    companion object {
        fun fromKey(key: String): QuickStatusType = entries.firstOrNull { it.key == key } ?: AREA_CLEAR
    }
}

data class QuickStatus(
    val id: String = java.util.UUID.randomUUID().toString(),
    val deviceID: String = "",
    val type: QuickStatusType,
    val zone: String = "",
    val note: String = "",
    val timestamp: Long = System.currentTimeMillis()
)

// === 照片警報 ===

data class PhotoAlert(
    val id: String = java.util.UUID.randomUUID().toString(),
    val photoID: String = "",
    val senderID: String = "",
    val senderName: String = "",
    val thumbnailUrl: String = "",
    val fullUrl: String = "",
    val caption: String = "",
    val lat: Double = 0.0,
    val lon: Double = 0.0,
    val timestamp: Long = System.currentTimeMillis()
)

// === 後台自動發現 ===

data class DiscoveredBackend(
    val name: String,
    val host: String,
    val port: Int,
    val discoveredAt: Long = System.currentTimeMillis()
)

// === 物資項目 ===

data class ResourceItem(
    val id: String = java.util.UUID.randomUUID().toString(),
    var name: String,
    var total: Int = 0,
    var available: Int = 0
)

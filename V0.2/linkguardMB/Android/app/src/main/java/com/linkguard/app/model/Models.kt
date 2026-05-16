package com.linkguard.app.model

import androidx.compose.ui.graphics.Color
import kotlin.math.pow

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
    SEARCH("search", "搜索", "SCH"), RESCUE("rescue", "救援", "RSC"), MEDICAL("medical", "醫療", "MED"),
    LOGISTICS("logistics", "後勤", "LOG"), SAFETY("safety", "安全官", "SAF"), COMMANDER("commander", "指揮", "CMD"), SUPPORT("support", "支援", "SUP");

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

// === LoRa 檔位（對應韌體 profiles[0..8]）===

data class LoRaProfile(
    val level: Int,
    val sf: Int,
    val bw: Double,
    val cr: Int,
    val label: String
)

val loraProfiles = listOf(
    LoRaProfile(0, 7,  500.0, 5, "L0:極速"),
    LoRaProfile(1, 7,  250.0, 5, "L1:高速"),
    LoRaProfile(2, 8,  250.0, 5, "L2:敏捷"),
    LoRaProfile(3, 9,  250.0, 6, "L3:平衡"),
    LoRaProfile(4, 9,  125.0, 6, "L4:標準"),
    LoRaProfile(5, 10, 125.0, 7, "L5:穿透"),
    LoRaProfile(6, 10, 62.5,  8, "L6:強穿"),
    LoRaProfile(7, 11, 62.5,  8, "L7:極限"),
    LoRaProfile(8, 12, 62.5,  8, "L8:最遠"),
)

// === 受困者資料（對應韌體 VictimNode）===

data class VictimNode(
    val id: String,
    var heartRate: Int = 0,
    var battery: Int = 0,
    var rssi: Double = 0.0,
    var snr: Double = 0.0,
    var isSOS: Boolean = false,
    var lastSeen: Long = System.currentTimeMillis(),
    var isOnline: Boolean = true
) {
    val estimatedDistance: Double
        get() {
            val n = 2.7
            val a = -30.0
            return 10.0.pow((a - rssi) / (10.0 * n))
        }

    val distanceText: String
        get() {
            val d = estimatedDistance
            return when {
                d < 0.1  -> "<0.1m"
                d < 10   -> "%.1fm".format(d)
                d < 1000 -> "${d.toInt()}m"
                else     -> "%.1fkm".format(d / 1000)
            }
        }

    val heartRateText: String
        get() = if (heartRate > 0) "$heartRate bpm" else "-- bpm"

    val lastSeenText: String
        get() {
            val interval = (System.currentTimeMillis() - lastSeen) / 1000
            return when {
                interval < 5    -> "剛剛"
                interval < 60   -> "${interval} 秒前"
                interval < 3600 -> "${interval / 60} 分鐘前"
                else            -> "${interval / 3600} 小時前"
            }
        }
}

// === 搜救節點自身狀態 ===

data class RescueNodeStatus(
    var nodeID: String = "--",  // 由 ViewModel 啟動時覆寫為持久化 ID
    var deptCode: String = "EMT",
    var battery: Int = 0,
    var loraLevel: Int = 4,
    var isConnected: Boolean = false,
    var pairCode: String = "0000",
    var gpsLat: Double = 0.0,
    var gpsLon: Double = 0.0
) {
    val loraProfile: LoRaProfile
        get() = loraProfiles[loraLevel.coerceIn(0, 8)]
}

// === SOS 警報紀錄 ===

data class SOSRecord(
    val id: String = java.util.UUID.randomUUID().toString(),
    val victimID: String,
    val heartRate: Int,
    val rssi: Double,
    val distance: String,
    val battery: Int,
    val time: Long = System.currentTimeMillis(),
    var isAcknowledged: Boolean = false
) {
    val timeText: String
        get() {
            val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            return sdf.format(java.util.Date(time))
        }
}

// === 韌體 JSON 解析用 ===

data class FirmwareVictim(
    val id: String,
    val hr: Int,
    val bat: Int,
    val rssi: Double,
    val dist: String? = null,
    val snr: Double? = null,
    val sos: Boolean,
    val online: Boolean
)

data class FirmwareTeamNode(
    val id: String,
    val dept: String,
    val bat: Int,
    val rssi: Double,
    val vc: Int,
    val online: Boolean
)

data class FirmwareReinforcement(
    val from: String,
    val msg: String,
    val loc: String,
    val ago: Int
)

data class FirmwareStatusResponse(
    val id: String? = null,
    val dept: String? = null,
    val bat: Int,
    val vbat: Double? = null,
    val lvl: Int,
    val pair: String?,
    val victims: List<FirmwareVictim>,
    val team: List<FirmwareTeamNode>? = null,
    val rf: List<FirmwareReinforcement>? = null
)

// === 指揮中心命令 ===

enum class CommandPriority(val value: Int, val label: String) {
    ROUTINE(0, "一般"),
    URGENT(1, "緊急"),
    CRITICAL(2, "最高");

    val color: Color get() = when (this) {
        ROUTINE  -> Color(0xFF1AAD8C)  // NV.info
        URGENT   -> Color(0xFFB8941F)  // NV.warning
        CRITICAL -> Color(0xFFD13838)  // NV.danger
    }

    val icon: String get() = when (this) {
        ROUTINE  -> "[i]"
        URGENT   -> "[!]"
        CRITICAL -> "[!!]"
    }
}

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

    companion object {
        fun fromKey(key: String): CommandType? =
            entries.firstOrNull { it.key == key || it.label == key }
    }
}

data class CommandOrder(
    val id: String = java.util.UUID.randomUUID().toString(),
    val type: CommandType,
    val priority: CommandPriority,
    val title: String,
    val detail: String,
    val sender: String,
    val time: Long = System.currentTimeMillis(),
    var isRead: Boolean = false
) {
    val timeText: String
        get() {
            val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            return sdf.format(java.util.Date(time))
        }
}

// === 增援請求 ===

enum class ReinforcementStatus(val label: String) {
    PENDING("待回覆"),
    ACCEPTED("已加入"),
    DECLINED("已拒絕"),
    EXPIRED("已過期");

    val chinese: String get() = label

    val color: Color get() = when (this) {
        PENDING  -> Color(0xFFB8941F)
        ACCEPTED -> Color(0xFF14B840)
        DECLINED -> Color(0xFFD13838)
        EXPIRED  -> Color.Gray
    }

    companion object {
        private val englishMap = mapOf(
            "pending" to PENDING,
            "joined" to ACCEPTED, "accepted" to ACCEPTED,
            "rejected" to DECLINED, "declined" to DECLINED,
            "expired" to EXPIRED
        )
        fun fromChinese(s: String): ReinforcementStatus =
            entries.firstOrNull { it.label == s }
                ?: englishMap[s.lowercase()]
                ?: PENDING
    }
}

data class ReinforcementRequest(
    val id: String = java.util.UUID.randomUUID().toString(),
    val fromTeam: String,
    val message: String,
    val location: String,
    val time: Long = System.currentTimeMillis(),
    var status: ReinforcementStatus = ReinforcementStatus.PENDING,
    var respondedBy: MutableList<String> = mutableListOf(),
    val isFromSelf: Boolean = false
) {
    val timeText: String
        get() {
            val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            return sdf.format(java.util.Date(time))
        }
}

// === 團隊成員 ===

data class TeamMember(
    val id: String,
    var deptCode: String,
    var battery: Int,
    var rssi: Double,
    var lastSeen: Long = System.currentTimeMillis(),
    var isOnline: Boolean = true,
    var victimCount: Int = 0,
    var nickname: String? = null
) {
    val displayLabel: String get() = "${nickname?.takeIf { it.isNotBlank() } ?: id} ($deptCode)"
    val lastSeenText: String
        get() {
            val interval = (System.currentTimeMillis() - lastSeen) / 1000
            return when {
                interval < 5    -> "剛剛"
                interval < 60   -> "${interval} 秒前"
                interval < 3600 -> "${interval / 60} 分鐘前"
                else            -> "${interval / 3600} 小時前"
            }
        }

    val signalColor: Color
        get() {
            if (!isOnline) return Color.Gray
            return when {
                rssi > -70 -> Color(0xFF4CAF50)
                rssi > -85 -> Color(0xFFFF9800)
                else       -> Color(0xFFFF5252)
            }
        }
}

// === WiFi 命令協議 ===

data class WiFiCommand(
    val id: String,
    val type: String,
    val priority: Int,
    val title: String,
    val detail: String,
    val sender: String,
    val timestamp: Double
) {
    fun toCommandOrder(): CommandOrder {
        val cmdType = CommandType.fromKey(type) ?: CommandType.STATUS_REPORT
        val cmdPri = CommandPriority.entries.firstOrNull { it.value == priority } ?: CommandPriority.ROUTINE
        return CommandOrder(
            id = id,
            type = cmdType,
            priority = cmdPri,
            title = title,
            detail = detail,
            sender = sender,
            time = (timestamp * 1000).toLong(),
            isRead = false
        )
    }
}

data class WiFiMessage(
    val msgType: String,
    val payload: String
)

// === 韌體轉發的 LoRa 指揮命令格式 ===

data class FirmwareLoRaCommand(
    val cmd_id: String,
    val type: String,
    val pri: Int,
    val title: String,
    val detail: String,
    val sender: String
) {
    fun toCommandOrder(): CommandOrder {
        val cmdType = CommandType.fromKey(type) ?: CommandType.STATUS_REPORT
        val cmdPri = CommandPriority.entries.firstOrNull { it.value == pri } ?: CommandPriority.ROUTINE
        return CommandOrder(
            id = cmd_id,
            type = cmdType,
            priority = cmdPri,
            title = title,
            detail = detail,
            sender = sender,
            time = System.currentTimeMillis(),
            isRead = false
        )
    }
}

data class FieldStatusReport(
    val deviceID: String,
    val deptCode: String,
    val battery: Int,
    val bleConnected: Boolean,
    val victims: List<VictimSummary>,
    val teamMembers: List<TeamSummary>,
    val sosCount: Int,
    val timestamp: Double
)

data class VictimSummary(
    val id: String,
    val heartRate: Int,
    val battery: Int,
    val rssi: Double,
    val isSOS: Boolean,
    val isOnline: Boolean
)

data class TeamSummary(
    val id: String,
    val deptCode: String,
    val battery: Int,
    val rssi: Double,
    val isOnline: Boolean,
    val victimCount: Int
)

// === 快速狀態回報 ===

enum class QuickStatusType(val key: String, val label: String, val icon: String) {
    AREA_CLEAR("area_clear", "區域清除", "OK"),
    NEED_SUPPORT("need_support", "需要支援", "!!"),
    VICTIM_FOUND("victim_found", "發現受困者", "VF"),
    RETREATING("retreating", "撤退中", "RT");

    val color: Color get() = when (this) {
        AREA_CLEAR   -> Color(0xFF14B840)
        NEED_SUPPORT -> Color(0xFFB8941F)
        VICTIM_FOUND -> Color(0xFF1AAD8C)
        RETREATING   -> Color(0xFFD13838)
    }

    companion object {
        fun fromKey(key: String): QuickStatusType? = entries.firstOrNull { it.key == key }
    }
}

data class QuickStatus(
    val id: String = java.util.UUID.randomUUID().toString(),
    val type: String,
    val senderID: String,
    val senderName: String,
    val zone: String = "",
    val note: String = "",
    val timestamp: Double = System.currentTimeMillis() / 1000.0
) {
    val statusType: QuickStatusType? get() = QuickStatusType.fromKey(type)
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === 任務指派 ===

enum class TaskStatus(val key: String, val label: String) {
    PENDING("pending", "待接受"),
    ACCEPTED("accepted", "已接受"),
    IN_PROGRESS("in_progress", "執行中"),
    COMPLETED("completed", "已完成"),
    CANCELLED("cancelled", "已取消");

    val color: Color get() = when (this) {
        PENDING     -> Color(0xFFFF9800)
        ACCEPTED    -> Color(0xFF00D9A6)
        IN_PROGRESS -> Color(0xFF4CAF50)
        COMPLETED   -> Color.Gray
        CANCELLED   -> Color(0xFFFF5252)
    }

    companion object {
        fun fromKey(key: String): TaskStatus = entries.firstOrNull { it.key == key } ?: PENDING
    }
}

data class TaskAssignment(
    val id: String = java.util.UUID.randomUUID().toString(),
    val title: String,
    val detail: String = "",
    val assigneeID: String,
    val assigneeName: String,
    val zone: String = "",
    val priority: Int = 0,
    val status: String = TaskStatus.PENDING.key,
    val createdAt: Double = System.currentTimeMillis() / 1000.0,
    val dueTime: Double? = null
) {
    val taskStatus: TaskStatus get() = TaskStatus.fromKey(status)
    val taskPriority: CommandPriority get() = CommandPriority.entries.firstOrNull { it.value == priority } ?: CommandPriority.ROUTINE
    val isActive: Boolean get() = taskStatus == TaskStatus.PENDING || taskStatus == TaskStatus.ACCEPTED || taskStatus == TaskStatus.IN_PROGRESS
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("M/d HH:mm", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((createdAt * 1000).toLong()))
    }
}

// === 倒數計時器 ===

data class CountdownTimerModel(
    val id: String = java.util.UUID.randomUUID().toString(),
    val title: String,
    val durationSeconds: Int,
    val startedAt: Double = System.currentTimeMillis() / 1000.0,
    val isBroadcast: Boolean = true,
    val targetDeviceID: String = ""
) {
    val endTime: Double get() = startedAt + durationSeconds
    val remainingSeconds: Int get() = maxOf(0, (endTime - System.currentTimeMillis() / 1000.0).toInt())
    val isExpired: Boolean get() = remainingSeconds <= 0
    val remainingText: String get() {
        val m = remainingSeconds / 60; val s = remainingSeconds % 60
        return "%02d:%02d".format(m, s)
    }
}

// === 危險標記 ===

enum class HazardSeverity(val key: String, val label: String) {
    LOW("low", "低"), MEDIUM("medium", "中"), HIGH("high", "高"), CRITICAL("critical", "極高");

    val color: Color get() = when (this) {
        LOW      -> Color(0xFF00D9A6)
        MEDIUM   -> Color(0xFFFF9800)
        HIGH     -> Color(0xFFFF5252)
        CRITICAL -> Color(0xFFFF5252)
    }

    companion object {
        fun fromKey(key: String): HazardSeverity = entries.firstOrNull { it.key == key } ?: MEDIUM
    }
}

data class HazardReport(
    val id: String = java.util.UUID.randomUUID().toString(),
    val hazardType: String,
    val description: String = "",
    val reporterID: String,
    val reporterName: String,
    val zone: String = "",
    val severity: String = HazardSeverity.MEDIUM.key,
    val timestamp: Double = System.currentTimeMillis() / 1000.0
) {
    val hazard: HazardType? get() = HazardType.fromKey(hazardType)
    val severityLevel: HazardSeverity get() = HazardSeverity.fromKey(severity)
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === 預設訊息模板 ===

data class PresetMessage(val text: String, val icon: String)

val presetMessages = listOf(
    PresetMessage("收到", "[V]"),
    PresetMessage("已到達", "[位]"),
    PresetMessage("請求確認", "[?]"),
    PresetMessage("了解，執行中", "[>]"),
    PresetMessage("任務完成", "[V]"),
    PresetMessage("需要更多人力", "[人]"),
    PresetMessage("情況緊急", "[!]"),
    PresetMessage("安全撤離完成", "[<]"),
)

// === 通用座標 / 氣象 ===

data class GPSCoord(
    val lat: Double,
    val lon: Double
)

data class WeatherSnapshot(
    val temp: Double? = null,
    val humidity: Double? = null,
    val wind: Double? = null,
    val rainfall: Double? = null
)

// === HQ 決策 ===

data class PatientDecisionEntry(
    val id: String,
    val location: String,
    val priority: String,
    val reason: String = "",
    val gps: GPSCoord? = null
)

data class HQDecision(
    val id: String = java.util.UUID.randomUUID().toString(),
    val decisionId: String = "",
    val decision: String,
    val patients: List<PatientDecisionEntry>,
    val timestamp: String,
    val trigger: String = "",
    val weather: WeatherSnapshot? = null,
    val receivedAt: Long = System.currentTimeMillis()
)

// === 傷員回報 ===

data class PatientReport(
    val patientId: String = "P${System.currentTimeMillis() / 1000}",
    val nationalId: String = "",
    val name: String = "",
    val birthDate: String = "",
    val age: Int? = null,
    val location: String,
    val breathingRate: Int,
    val capillaryRefill: Double,
    val canFollowCommands: Boolean,
    val gpsLat: Double? = null,
    val gpsLon: Double? = null,
    val notes: String = ""
)

// === 電台 / 會報 ===

data class RadioReport(
    val id: String = java.util.UUID.randomUUID().toString(),
    val senderName: String,
    val timestamp: Long = System.currentTimeMillis(),
    val transcription: String,
    val locationDesc: String = "",
    val reportId: String,
    val patientsCount: Int = 0,
    val audioUrl: String = "",
    val weather: WeatherSnapshot? = null
) {
    // 向後相容
    val location: String get() = locationDesc
}

data class RadioReportSummary(
    val reportId: String,
    val senderName: String,
    val transcription: String,
    val timestamp: Double,
    val locationDesc: String = "",
    val patientsCount: Int = 0,
    val audioUrl: String = "",
    val weather: WeatherSnapshot? = null
) {
    val location: String get() = locationDesc
}

data class RadioControlPayload(
    val action: String,   // "start" or "stop"
    val senderName: String
)

// === TCP SOS 警報 ===

data class TCPSOSAlert(
    val id: String,
    val senderID: String,
    val senderName: String,
    val lat: Double,
    val lon: Double,
    val message: String,
    val timestamp: Long = System.currentTimeMillis()
)

// === 資源狀態 ===

data class ResourceStatus(
    val ambulanceTotal: Int = 0,
    val ambulanceAvailable: Int = 0,
    val medicalKitTotal: Int = 0,
    val medicalKitAvailable: Int = 0,
    val personnelTotal: Int = 0,
    val personnelAvailable: Int = 0
) {
    val ambulanceText: String get() = "救護車 $ambulanceAvailable/$ambulanceTotal 可用"
    val medicalKitText: String get() = "醫療包 $medicalKitAvailable/$medicalKitTotal 可用"
    val personnelText: String get() = "人員 $personnelAvailable/$personnelTotal 可用"
}

// === 照片回報 ===

data class PhotoReport(
    val id: String,
    val senderName: String,
    val lat: Double,
    val lon: Double,
    val locationDesc: String,
    val caption: String,
    val thumbnailURL: String,
    val fullURL: String,
    val timestamp: Long = System.currentTimeMillis()
)

// === 文字廣播 ===

data class TextBroadcast(
    val id: String = java.util.UUID.randomUUID().toString(),
    val broadcastId: String,
    val message: String,
    val senderName: String,
    val priority: String = "normal",
    val timestamp: Double = System.currentTimeMillis() / 1000.0
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date((timestamp * 1000).toLong()))
    }
}

// === 傷患惡化預警 ===

data class PatientWarning(
    val patientId: String,
    val priority: String,
    val location: String,
    val minutesSinceTriage: Int,
    val warningLevel: String,
    val message: String,
    val timestamp: Double = System.currentTimeMillis() / 1000.0
)

// === 翻譯結果 ===

data class TranslationResult(
    val original: String,
    val translated: String,
    val detectedLang: String = "",
    val targetLang: String = ""
)

// === NFC 讀取 ===

data class NfcScanResult(
    val rawText: String,
    val scannedAt: Long = System.currentTimeMillis()
) {
    /** 嘗試從掃描文字中解析出 key=value 格式欄位 */
    val fields: Map<String, String> get() {
        val result = mutableMapOf<String, String>()
        rawText.lines().forEach { line ->
            val idx = line.indexOf(':')
            if (idx > 0) {
                val k = line.substring(0, idx).trim()
                val v = line.substring(idx + 1).trim()
                if (k.isNotEmpty()) result[k] = v
            }
        }
        return result
    }
    /** 嘗試提取 location 欄位（key: location / loc / 位置） */
    val location: String get() = fields["location"] ?: fields["loc"] ?: fields["位置"] ?: ""
    /** 嘗試提取 notes / 備註 */
    val notes: String get() = fields["notes"] ?: fields["note"] ?: fields["備註"] ?: rawText
}

// === 醫院目錄 ===

enum class HospitalLevel(val key: String, val label: String) {
    REGIONAL("regional", "區域醫院"),
    DISTRICT("district", "地區醫院"),
    CLINIC("clinic", "診所"),
    RESCUE_CENTER("rescue", "救援中心"),
    FIRE("fire", "消防單位");
}

data class Hospital(
    val id: String = java.util.UUID.randomUUID().toString(),
    val name: String,
    val address: String,
    val phone: String = "",
    val level: HospitalLevel,
    val city: String,
    val region: String,
    val icuBeds: Int = 0,
    val orRooms: Int = 0,
    val totalBeds: Int = 0
) {
    val levelColor: Color get() = when (level) {
        HospitalLevel.REGIONAL      -> Color(0xFFD13838)
        HospitalLevel.DISTRICT      -> Color(0xFFB8941F)
        HospitalLevel.CLINIC        -> Color(0xFF1AAD8C)
        HospitalLevel.RESCUE_CENTER -> Color(0xFF4B8BEC)
        HospitalLevel.FIRE          -> Color(0xFFE07D20)
    }
}

// === AI 助理訊息 ===

data class FieldAIMessage(
    val id: String = java.util.UUID.randomUUID().toString(),
    val role: String,        // "user" | "assistant"
    val content: String,
    val timestamp: Long = System.currentTimeMillis(),
    val model: String? = null,
    val elapsedMs: Int? = null,
    val isError: Boolean = false
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
}

// === USAR 操作狀態 ===

enum class OperationalStatus(val key: String, val label: String) {
    ARRIVED("arrived", "已到達"),
    ASSESSING("assessing", "評估中"),
    SEARCHING("searching", "搜索中"),
    TREATING("treating", "處置傷患"),
    EXTRACTING("extracting", "移出傷患"),
    STANDBY("standby", "待命"),
    WITHDRAWING("withdrawing", "後撤中");

    val color: Color get() = when (this) {
        ARRIVED     -> Color(0xFF1AAD8C)
        ASSESSING   -> Color(0xFFB8941F)
        SEARCHING   -> Color(0xFF4B8BEC)
        TREATING    -> Color(0xFFD13838)
        EXTRACTING  -> Color(0xFFE07D20)
        STANDBY     -> Color.Gray
        WITHDRAWING -> Color(0xFF8957E5)
    }
}

// === 統一活動日誌 ===

enum class ActivityKind(val label: String, val icon: String) {
    SENT_MESSAGE("已送出訊息",    "MSG_OUT"),
    RECEIVED_MESSAGE("收到訊息",  "MSG_IN"),
    PERSONAL_NOTIFICATION("個人通知", "NOTIF"),
    COMMAND("指揮命令",           "CMD"),
    HQ_DECISION("HQ 決策",       "AI"),
    PWS_ALERT("公共警報",         "PWS"),
    BRIEFING("情況會報",          "BRIEF"),
    BROADCAST("廣播",             "BCAST"),
    SOS("SOS 警報",               "SOS"),
    REINFORCEMENT("增援",         "RF"),
    HAZARD("危險標記",            "HAZ"),
    PATIENT_WARNING("傷患預警",   "PAT_W"),
    DEVICE_ALERT("裝置警報",      "DEV"),
    TASK("任務指派",              "TASK"),
    PATIENT_REPORT("傷員回報",    "PAT"),
    QUICK_STATUS("快速狀態",      "QS"),
    PHOTO("照片回報",             "PHOTO");

    val color: Color get() = when (this) {
        SOS, HAZARD          -> Color(0xFFD13838)
        COMMAND, BROADCAST   -> Color(0xFF4B8BEC)
        HQ_DECISION          -> Color(0xFF8957E5)
        PWS_ALERT            -> Color(0xFFB8941F)
        REINFORCEMENT        -> Color(0xFFE07D20)
        PATIENT_WARNING      -> Color(0xFFCF5B5B)
        PATIENT_REPORT       -> Color(0xFF1AAD8C)
        BRIEFING             -> Color(0xFF2D9CDB)
        else                 -> Color(0xFF2EA043)
    }
}

data class ActivityLogEntry(
    val id: String = java.util.UUID.randomUUID().toString(),
    val kind: ActivityKind,
    val title: String,
    val summary: String,
    val timestamp: Long = System.currentTimeMillis()
) {
    val timeText: String get() {
        val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
    val dateText: String get() {
        val sdf = java.text.SimpleDateFormat("M/d", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(timestamp))
    }
}

// === USAR 指揮角色（由人員配置自動判定） ===

enum class UsarRole(val key: String, val label: String) {
    SECTOR_COMMANDER("sector_commander", "區段指揮官"),
    WORKSITE_MANAGER("worksite_manager", "現場管理員"),
    SQUAD_LEADER("squad_leader", "班長");

    companion object {
        /** 根據當前用戶在 personnelAssignments 中的角色推斷 USAR 角色 */
        fun fromPersonnelRole(role: PersonnelRole): UsarRole = when (role) {
            PersonnelRole.COMMANDER -> SECTOR_COMMANDER
            PersonnelRole.RESCUE    -> WORKSITE_MANAGER
            else                    -> SQUAD_LEADER
        }
    }
}

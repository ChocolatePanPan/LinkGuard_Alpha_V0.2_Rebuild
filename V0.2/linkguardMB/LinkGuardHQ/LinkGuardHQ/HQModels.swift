import Foundation
import SwiftUI

// MARK: - 共用 DateFormatter 快取
// DateFormatter 初始化昂貴，集中宣告為 static 避免在每個 computed property 重複建立。

private enum HQDateFormatters {
    static let hhmmss: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f
    }()
    static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f
    }()
    static let mmddhhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f
    }()
    static let mddhhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f
    }()
}

// MARK: - LinkGuard 傷患編號配置

struct PatientIDConfig: Codable, Equatable {
    var systemCode: String = "LG"
    var eventDateCode: String = Self.todayEventDateCode()
    var cityCode: String = "TAO"
    var cityName: String = "桃園"
    var districtCode: String = "ZL"
    var districtName: String = "中壢"
    var eventCode: String = "E01"
    var siteCode: String = "S03"
    var buildingCode: String = "B02"
    var floorCode: String = "F02"
    var zoneCode: String = "A"
    var nextPatientSerial: Int = 1
    var nfcURLBase: String = "https://linkguard.tw/p/"

    static let recommendedCityCodes: [String: String] = [
        "TPE": "台北", "NTP": "新北", "TAO": "桃園", "HSZ": "新竹",
        "TXG": "台中", "TNN": "台南", "KHH": "高雄", "HUA": "花蓮", "TTT": "台東"
    ]

    static let recommendedTaoyuanDistrictCodes: [String: String] = ["ZL": "中壢"]

    private static let checksumAlphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let displayComponentLengths = [2, 6, 3, 2, 3, 3, 3, 3, 1, 4, 1]

    var displayPrefix: String {
        baseDisplayComponents.joined(separator: "-")
    }

    func displayID(serial: Int? = nil) -> String {
        let serialText = patientSerialText(serial ?? nextPatientSerial)
        let core = compactCore(serialText: serialText)
        return (baseDisplayComponents + [serialText, Self.checksum(for: core)]).joined(separator: "-")
    }

    func compactID(serial: Int? = nil) -> String {
        let serialText = patientSerialText(serial ?? nextPatientSerial)
        let core = compactCore(serialText: serialText)
        return core + Self.checksum(for: core)
    }

    func nfcURL(serial: Int? = nil) -> String {
        nfcURLBase + compactID(serial: serial)
    }

    func nfcURL(for idText: String) -> String {
        guard let compact = Self.extractCompactID(from: idText) else { return nfcURL() }
        return nfcURLBase + compact
    }

    func displayID(from idText: String) -> String? {
        guard let compact = Self.extractCompactID(from: idText) else { return nil }
        return Self.displayID(fromCompact: compact)
    }

    func isValidChecksum(_ idText: String) -> Bool {
        guard let compact = Self.extractCompactID(from: idText), compact.count > 1 else { return false }
        let core = String(compact.dropLast())
        return compact.last.map { String($0) } == Self.checksum(for: core)
    }

    static func displayID(fromCompact compactID: String) -> String {
        let compact = compactID.uppercased().filter { $0.isLetter || $0.isNumber }
        if let components = split(compact, lengths: displayComponentLengths) {
            return components.joined(separator: "-")
        }
        return compact
    }

    static func extractCompactID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if let url = URL(string: trimmed), let host = url.host?.lowercased(), host.contains("linkguard.tw") {
            candidate = url.lastPathComponent
        } else if let markerRange = trimmed.range(of: "/p/", options: [.caseInsensitive]) {
            candidate = String(trimmed[markerRange.upperBound...])
        } else {
            candidate = trimmed
        }

        let normalized = candidate.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.hasPrefix("LG"), normalized.contains("P") else { return nil }
        return normalized
    }

    static func checksum(for compactCore: String) -> String {
        let total = compactCore.uppercased().reduce(17) { partial, character in
            partial + checksumValue(for: character)
        }
        return String(checksumAlphabet[total % checksumAlphabet.count])
    }

    static func todayEventDateCode(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: date)
    }

    private var baseDisplayComponents: [String] {
        [systemCode, eventDateCode, cityCode, districtCode, eventCode, siteCode, buildingCode, floorCode, zoneCode]
            .map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var compactBase: String { baseDisplayComponents.joined() }

    private func compactCore(serialText: String) -> String {
        compactBase + serialText.uppercased()
    }

    private func patientSerialText(_ serial: Int) -> String {
        String(format: "P%03d", max(1, serial))
    }

    private static func checksumValue(for character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        switch scalar.value {
        case 48...57: return Int(scalar.value - 48)
        case 65...90: return Int(scalar.value - 55)
        default: return 0
        }
    }

    private static func split(_ compact: String, lengths: [Int]) -> [String]? {
        var result: [String] = []
        var index = compact.startIndex
        for length in lengths {
            guard let nextIndex = compact.index(index, offsetBy: length, limitedBy: compact.endIndex) else { return nil }
            result.append(String(compact[index..<nextIndex]))
            index = nextIndex
        }
        return index == compact.endIndex ? result : nil
    }
}

// MARK: - 事件日誌模型

/// 事件類型
enum TimelineEventType: String, Codable, CaseIterable {
    case command      = "命令"
    case statusReport = "狀態回報"
    case chat         = "通訊"
    case pwsAlert     = "PWS 警報"
    case personnel    = "人員配置"
    case disaster     = "災害狀態"
    case briefing     = "會報"
    case notification = "通知"
    case zoneUpdate   = "分區更新"
    case system       = "系統"

    var icon: String {
        switch self {
        case .command:      return "megaphone.fill"
        case .statusReport: return "antenna.radiowaves.left.and.right"
        case .chat:         return "bubble.left.and.bubble.right.fill"
        case .pwsAlert:     return "exclamationmark.triangle.fill"
        case .personnel:    return "person.3.fill"
        case .disaster:     return "building.2"
        case .briefing:     return "doc.text.fill"
        case .notification: return "bell.fill"
        case .zoneUpdate:   return "map.fill"
        case .system:       return "gear"
        }
    }

    var color: Color {
        switch self {
        case .command:      return NV.command
        case .statusReport: return NV.green
        case .chat:         return NV.team
        case .pwsAlert:     return NV.danger
        case .personnel:    return NV.info
        case .disaster:     return NV.warning
        case .briefing:     return NV.reinforce
        case .notification: return NV.reinforce
        case .zoneUpdate:   return NV.green
        case .system:       return .gray
        }
    }
}

/// 事件日誌條目
struct TimelineEvent: Codable, Identifiable {
    let id: String
    let eventType: TimelineEventType
    let title: String
    let detail: String
    let source: String
    let timestamp: Double

    init(id: String = UUID().uuidString, eventType: TimelineEventType, title: String,
         detail: String = "", source: String = "HQ") {
        self.id = id
        self.eventType = eventType
        self.title = title
        self.detail = detail
        self.source = source
        self.timestamp = Date().timeIntervalSince1970
    }

    var timeText: String {
        HQDateFormatters.hhmmss.string(from: Date(timeIntervalSince1970: timestamp))
    }

    var relativeTimeText: String {
        let seconds = Int(Date().timeIntervalSince1970 - timestamp)
        if seconds < 60 { return L("剛剛") }
        if seconds < 3600 { return "\(seconds / 60) 分鐘前" }
        if seconds < 86400 { return "\(seconds / 3600) 小時前" }
        return timeText
    }
}

// MARK: - 災害狀態模型

/// 倒塌類型
enum CollapseType: String, Codable, CaseIterable {
    case partial, pancake, lean, vShape, none, unknown

    var label: String {
        switch self {
        case .partial: return L("部分倒塌"); case .pancake: return L("層疊式倒塌")
        case .lean:    return L("傾斜倒塌"); case .vShape:  return L("V型倒塌")
        case .none:    return L("未倒塌");   case .unknown: return L("未知")
        }
    }
}

/// 樓層狀態
enum FloorCondition: String, Codable, CaseIterable {
    case collapsed, partial, accessible, cleared, restricted, unknown

    var label: String {
        switch self {
        case .collapsed:  return L("完全倒塌"); case .partial:    return L("部分倒塌")
        case .accessible: return L("可進入");   case .cleared:    return L("已清除")
        case .restricted: return L("限制進入"); case .unknown:    return L("未知")
        }
    }

    var color: Color {
        switch self {
        case .collapsed:  return NV.danger
        case .partial:    return NV.warning
        case .accessible: return NV.green
        case .cleared:    return NV.info
        case .restricted: return NV.reinforce
        case .unknown:    return .gray
        }
    }
}

/// 分區狀態
enum ZoneStatus: String, Codable, CaseIterable {
    case active, standby, cleared, dangerous, restricted

    var label: String {
        switch self {
        case .active:     return L("搜救中");  case .standby:    return L("待命")
        case .cleared:    return L("已清除");  case .dangerous:  return L("危險區")
        case .restricted: return L("限制區")
        }
    }

    var color: Color {
        switch self {
        case .active:     return NV.green
        case .standby:    return NV.warning
        case .cleared:    return NV.info
        case .dangerous:  return NV.danger
        case .restricted: return NV.reinforce
        }
    }
}

/// 危害類型
enum HazardType: String, Codable, CaseIterable {
    case gasLeak, fire, flooding, structural, electrical, chemical

    var label: String {
        switch self {
        case .gasLeak:    return L("瓦斯洩漏"); case .fire:       return L("火災")
        case .flooding:   return L("淹水");     case .structural: return L("結構不穩")
        case .electrical: return L("電氣危害"); case .chemical:   return L("化學品洩漏")
        }
    }

    var icon: String {
        switch self {
        case .gasLeak:    return "flame.fill"
        case .fire:       return "flame.circle.fill"
        case .flooding:   return "drop.triangle.fill"
        case .structural: return "building.2.fill"
        case .electrical: return "bolt.trianglebadge.exclamationmark.fill"
        case .chemical:   return "testtube.2"
        }
    }

    var color: Color {
        switch self {
        case .gasLeak:    return NV.warning
        case .fire:       return NV.danger
        case .flooding:   return NV.command
        case .structural: return NV.reinforce
        case .electrical: return NV.warning
        case .chemical:   return NV.simulation
        }
    }
}

/// 樓層狀態
struct FloorStatus: Codable, Identifiable {
    let id: String           // 如 "1F", "B1"
    var condition: FloorCondition
    var assignedTeam: String
    var note: String

    init(id: String, condition: FloorCondition = .unknown, assignedTeam: String = "", note: String = "") {
        self.id = id
        self.condition = condition
        self.assignedTeam = assignedTeam
        self.note = note
    }
}

/// 救援分區
struct RescueZone: Codable, Identifiable {
    let id: String
    var name: String
    var status: ZoneStatus
    var assignedPersonnel: [String]
    var hazards: [HazardType]
    var note: String

    init(id: String = UUID().uuidString, name: String, status: ZoneStatus = .standby,
         assignedPersonnel: [String] = [], hazards: [HazardType] = [], note: String = "") {
        self.id = id
        self.name = name
        self.status = status
        self.assignedPersonnel = assignedPersonnel
        self.hazards = hazards
        self.note = note
    }
}

/// 出入口
struct EntryPoint: Codable, Identifiable {
    let id: String
    var name: String
    var description: String
    var isAccessible: Bool

    init(id: String = UUID().uuidString, name: String, description: String = "", isAccessible: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.isAccessible = isAccessible
    }
}

/// 災害現場
struct DisasterSite: Codable {
    var buildingName: String
    var address: String
    var aboveGroundFloors: Int
    var undergroundFloors: Int
    var collapseType: CollapseType
    var floors: [FloorStatus]
    var zones: [RescueZone]
    var hazards: [HazardType]
    var entryPoints: [EntryPoint]
    var rallyPoint: String
    var note: String
    var lastUpdated: Double

    init(buildingName: String = "", address: String = "", aboveGroundFloors: Int = 1,
         undergroundFloors: Int = 0, collapseType: CollapseType = .unknown,
         floors: [FloorStatus] = [], zones: [RescueZone] = [],
         hazards: [HazardType] = [], entryPoints: [EntryPoint] = [],
         rallyPoint: String = "", note: String = "") {
        self.buildingName = buildingName
        self.address = address
        self.aboveGroundFloors = aboveGroundFloors
        self.undergroundFloors = undergroundFloors
        self.collapseType = collapseType
        self.floors = floors
        self.zones = zones
        self.hazards = hazards
        self.entryPoints = entryPoints
        self.rallyPoint = rallyPoint
        self.note = note
        self.lastUpdated = Date().timeIntervalSince1970
    }

    /// 根據樓層數自動生成樓層列表
    mutating func generateFloors() {
        var list: [FloorStatus] = []
        for i in (1...undergroundFloors).reversed() {
            list.append(FloorStatus(id: "B\(i)"))
        }
        for i in 1...aboveGroundFloors {
            list.append(FloorStatus(id: "\(i)F"))
        }
        floors = list
    }
}

// MARK: - 人員配置模型

/// 人員角色
enum PersonnelRole: String, Codable, CaseIterable {
    case search, rescue, medical, logistics, safety, commander, support

    var label: String {
        switch self {
        case .search:    return L("搜索");   case .rescue:    return L("救援")
        case .medical:   return L("醫療");   case .logistics: return L("後勤")
        case .safety:    return L("安全官"); case .commander: return L("指揮")
        case .support:   return L("支援")
        }
    }

    var icon: String {
        switch self {
        case .search:    return "magnifyingglass"
        case .rescue:    return "figure.climbing"
        case .medical:   return "cross.case.fill"
        case .logistics: return "shippingbox.fill"
        case .safety:    return "shield.checkered"
        case .commander: return "star.fill"
        case .support:   return "wrench.and.screwdriver.fill"
        }
    }
}

/// 人員指派
struct PersonnelAssignment: Codable, Identifiable {
    let id: String
    var name: String
    var nickname: String?
    var assignedZone: String
    var assignedFloor: String
    var role: PersonnelRole
    var timestamp: Double

    init(id: String = UUID().uuidString, name: String, nickname: String? = nil,
         assignedZone: String = "",
         assignedFloor: String = "", role: PersonnelRole = .search) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.assignedZone = assignedZone
        self.assignedFloor = assignedFloor
        self.role = role
        self.timestamp = Date().timeIntervalSince1970
    }

    var displayLabel: String {
        let head = (nickname?.isEmpty == false) ? nickname! : name
        return "\(head) (\(String(id.suffix(8))))"
    }
}

// MARK: - 內置通訊模型

/// 聊天訊息
struct ChatMessage: Codable, Identifiable {
    let id: String
    let senderID: String
    let senderName: String
    var recipientID: String?     // nil = 廣播
    let content: String
    let timestamp: Double
    var isRead: Bool
    var mentions: [String]

    enum CodingKeys: String, CodingKey {
        case id, senderID, senderName, recipientID, content, timestamp, isRead, mentions
    }
    private enum AltKeys: String, CodingKey {
        case sender_id, sender_name, recipient_id, is_read
    }

    init(id: String = UUID().uuidString, senderID: String, senderName: String,
         recipientID: String? = nil, content: String, isRead: Bool = false,
         mentions: [String] = []) {
        self.id = id
        self.senderID = senderID
        self.senderName = senderName
        self.recipientID = recipientID
        self.content = content
        self.timestamp = Date().timeIntervalSince1970
        self.isRead = isRead
        self.mentions = mentions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let a = try decoder.container(keyedBy: AltKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        senderID = try (c.decodeIfPresent(String.self, forKey: .senderID)
                        ?? a.decodeIfPresent(String.self, forKey: .sender_id)) ?? ""
        senderName = try (c.decodeIfPresent(String.self, forKey: .senderName)
                          ?? a.decodeIfPresent(String.self, forKey: .sender_name)) ?? ""
        recipientID = try c.decodeIfPresent(String.self, forKey: .recipientID)
                       ?? a.decodeIfPresent(String.self, forKey: .recipient_id)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp) ?? Date().timeIntervalSince1970
        isRead = try (c.decodeIfPresent(Bool.self, forKey: .isRead)
                      ?? a.decodeIfPresent(Bool.self, forKey: .is_read)) ?? false
        mentions = try c.decodeIfPresent([String].self, forKey: .mentions) ?? []
    }

    var timeText: String {
        HQDateFormatters.hhmmss.string(from: Date(timeIntervalSince1970: timestamp))
    }

    var isBroadcast: Bool { recipientID == nil }
}

// MARK: - PWS 警報模型

/// PWS 警報類型
enum PWSAlertType: String, Codable, CaseIterable {
    case earthquake, aftershock, tsunami, typhoon, flood, landslide, other

    var label: String {
        switch self {
        case .earthquake: return L("地震"); case .aftershock: return L("餘震"); case .tsunami: return L("海嘯")
        case .typhoon: return L("颱風"); case .flood: return L("洪水")
        case .landslide: return L("土石流"); case .other: return L("其他")
        }
    }

    var icon: String {
        switch self {
        case .earthquake: return "waveform.path.ecg"
        case .aftershock: return "waveform.badge.exclamationmark"
        case .tsunami:    return "water.waves"
        case .typhoon:    return "tropicalstorm"
        case .flood:      return "cloud.heavyrain.fill"
        case .landslide:  return "mountain.2.fill"
        case .other:      return "exclamationmark.triangle.fill"
        }
    }
}

/// PWS 嚴重度
enum PWSSeverity: String, Codable, CaseIterable, Comparable {
    case info, minor, moderate, severe, extreme

    var value: Int {
        switch self {
        case .info: return 0; case .minor: return 1; case .moderate: return 2
        case .severe: return 3; case .extreme: return 4
        }
    }

    static func < (lhs: PWSSeverity, rhs: PWSSeverity) -> Bool {
        lhs.value < rhs.value
    }

    var label: String {
        switch self {
        case .info:     return L("資訊")
        case .minor:    return L("輕微")
        case .moderate: return L("中等")
        case .severe:   return L("嚴重")
        case .extreme:  return L("極端")
        }
    }

    var color: Color {
        switch self {
        case .info:     return NV.info
        case .minor:    return NV.green
        case .moderate: return NV.warning
        case .severe:   return NV.reinforce
        case .extreme:  return NV.danger
        }
    }
}

/// PWS 警報
struct PWSAlert: Codable, Identifiable {
    let id: String
    var alertType: PWSAlertType
    var title: String
    var content: String
    var severity: PWSSeverity
    var publisher: String
    var publishTime: Double
    var expireTime: Double?
    var isActive: Bool

    init(id: String = UUID().uuidString, alertType: PWSAlertType, title: String,
         content: String, severity: PWSSeverity, publisher: String = "HQ",
         expireTime: Double? = nil) {
        self.id = id
        self.alertType = alertType
        self.title = title
        self.content = content
        self.severity = severity
        self.publisher = publisher
        self.publishTime = Date().timeIntervalSince1970
        self.expireTime = expireTime
        self.isActive = true
    }
}

// MARK: - 會報模型

/// 會報類型
enum BriefingType: String, Codable, CaseIterable {
    case initial, progress, shift
    case final_ = "final"

    var label: String {
        switch self {
        case .initial:  return L("初期報告"); case .progress: return L("進度報告")
        case .shift:    return L("交接報告"); case .final_:   return L("結案報告")
        }
    }

    var icon: String {
        switch self {
        case .initial:  return "doc.badge.plus"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .shift:    return "arrow.triangle.2.circlepath"
        case .final_:   return "checkmark.seal.fill"
        }
    }
}

/// 會報章節
struct BriefingSection: Codable, Identifiable {
    let id: String
    var title: String
    var content: String

    init(id: String = UUID().uuidString, title: String, content: String = "") {
        self.id = id
        self.title = title
        self.content = content
    }
}

/// 會報
struct BriefingReport: Codable, Identifiable {
    let id: String
    var title: String
    var type: BriefingType
    var author: String
    var timestamp: Double
    var sections: [BriefingSection]

    init(id: String = UUID().uuidString, title: String, type: BriefingType = .progress,
         author: String = "HQ", sections: [BriefingSection] = []) {
        self.id = id
        self.title = title
        self.type = type
        self.author = author
        self.timestamp = Date().timeIntervalSince1970
        self.sections = sections
    }

    var timeText: String {
        HQDateFormatters.mmddhhmm.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

// MARK: - 個人通知

/// 個人通知（HQ→特定前線裝置）
struct PersonalNotification: Codable, Identifiable {
    let id: String
    var targetDeviceID: String
    var title: String
    var content: String
    var timestamp: Double
    var isRead: Bool

    init(id: String = UUID().uuidString, targetDeviceID: String, title: String,
         content: String) {
        self.id = id
        self.targetDeviceID = targetDeviceID
        self.title = title
        self.content = content
        self.timestamp = Date().timeIntervalSince1970
        self.isRead = false
    }

    var timeText: String {
        HQDateFormatters.hhmmss.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

// MARK: - WiFi 命令協議（JSON 格式，與前線 App 共用）

/// WiFi 傳輸用的命令結構
struct WiFiCommand: Codable, Identifiable {
    let id: String
    let type: String        // search, standby, support, report, evacuation
    let priority: Int       // 0=routine, 1=urgent, 2=critical
    let title: String
    let detail: String
    let sender: String
    let timestamp: Double

    func toCommandOrder() -> CommandOrder {
        let cmdType = CommandType.fromKey(type) ?? .statusReport
        let cmdPri = CommandPriority(rawValue: priority) ?? .routine
        return CommandOrder(
            id: UUID(uuidString: id) ?? UUID(),
            type: cmdType, priority: cmdPri,
            title: title, detail: detail, sender: sender,
            time: Date(timeIntervalSince1970: timestamp), isRead: false
        )
    }
}

// MARK: - WiFi 雙向訊息協議

/// 包裝所有 WiFi 雙向通訊的訊息類型
struct WiFiMessage: Codable {
    let msgType: String     // "command", "status_report", "command_history"
    let deviceID: String?   // 發送方裝置 ID（可選，向下相容舊版前線 app）
    let payload: String     // JSON 編碼的 payload

    init(msgType: String, deviceID: String? = nil, payload: String) {
        self.msgType = msgType
        self.deviceID = deviceID
        self.payload = payload
    }
}

/// 前線 App → HQ：NFC 傷患標籤寫入完成紀錄
struct NFCTagWriteRecord: Codable, Identifiable {
    let id: String
    let patientId: String
    let compactPatientId: String
    let format: String
    let payload: String
    let tagCapacity: Int
    let payloadLength: Int
    let deviceID: String
    let senderName: String
    let timestamp: Double
}

/// 前線 App → 指揮中心：裝置狀態報告
struct FieldStatusReport: Codable {
    let deviceID: String
    let deptCode: String
    let battery: Int
    let bleConnected: Bool
    let victims: [VictimSummary]
    let teamMembers: [TeamSummary]
    let sosCount: Int
    let timestamp: Double
    let selfPersonnel: PersonnelAssignment?
}

struct VictimSummary: Codable, Identifiable {
    let id: String
    let heartRate: Int
    let battery: Int
    let rssi: Double
    let isSOS: Bool
    let isOnline: Bool
}

struct TeamSummary: Codable, Identifiable {
    let id: String
    let deptCode: String
    let battery: Int
    let rssi: Double
    let isOnline: Bool
    let victimCount: Int
}

// MARK: - 受困者優先級（HQ 設定）

enum VictimPriority: Int, CaseIterable, Comparable, Codable {
    case unset    = 0
    case low      = 1
    case medium   = 2
    case high     = 3
    case critical = 4

    static func < (lhs: VictimPriority, rhs: VictimPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .unset:    return L("未設定")
        case .low:      return L("低")
        case .medium:   return L("中")
        case .high:     return L("高")
        case .critical: return L("緊急")
        }
    }

    var color: Color {
        switch self {
        case .unset:    return .gray
        case .low:      return .green
        case .medium:   return .yellow
        case .high:     return .orange
        case .critical: return .red
        }
    }

    var icon: String {
        switch self {
        case .unset:    return "minus.circle"
        case .low:      return "arrow.down.circle"
        case .medium:   return "equal.circle"
        case .high:     return "arrow.up.circle.fill"
        case .critical: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - 受困者處置狀態

enum VictimStatus: Int, CaseIterable, Codable {
    case pending           = 0   // 未處理
    case onScene           = 1   // 現場處理中
    case waitingAmbulance  = 2   // 等待救護車
    case enRoute           = 3   // 送醫途中
    case hospitalized      = 4   // 已送醫
    case rescued           = 5   // 已脫困
    case deceased          = 6   // 死亡確認

    var label: String {
        switch self {
        case .pending:          return L("未處理")
        case .onScene:          return L("現場處理中")
        case .waitingAmbulance: return L("等待救護車")
        case .enRoute:          return L("送醫途中")
        case .hospitalized:     return L("已送醫")
        case .rescued:          return L("已脫困")
        case .deceased:         return L("死亡確認")
        }
    }

    var icon: String {
        switch self {
        case .pending:          return "clock"
        case .onScene:          return "cross.case"
        case .waitingAmbulance: return "car.side"
        case .enRoute:          return "arrow.right.circle"
        case .hospitalized:     return "building.2"
        case .rescued:          return "checkmark.shield"
        case .deceased:         return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending:          return .gray
        case .onScene:          return .orange
        case .waitingAmbulance: return .yellow
        case .enRoute:          return .blue
        case .hospitalized:     return .cyan
        case .rescued:          return .green
        case .deceased:         return .red
        }
    }
}

struct HQVictimRecord: Identifiable {
    let id: String
    var heartRate: Int
    var battery: Int
    var rssi: Double
    var isSOS: Bool
    var isOnline: Bool
    var sourceDeviceID: String
    var sourceDeptCode: String
    var priority: VictimPriority = .unset
    var status: VictimStatus = .pending
    var note: String = ""
    var description: String = ""
    // 從 PatientReport 合併的資料
    var patientName: String = ""
    var location: String = ""
    var hasPatientReport: Bool = false
}

// MARK: - 指揮中心命令

enum CommandPriority: Int, CaseIterable, Comparable, Codable {
    case routine  = 0
    case urgent   = 1
    case critical = 2

    static func < (lhs: CommandPriority, rhs: CommandPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .routine:  return L("一般")
        case .urgent:   return L("緊急")
        case .critical: return L("最高")
        }
    }

    var color: Color {
        switch self {
        case .routine:  return NV.info
        case .urgent:   return NV.warning
        case .critical: return NV.danger
        }
    }

    var icon: String {
        switch self {
        case .routine:  return "info.circle.fill"
        case .urgent:   return "exclamationmark.circle.fill"
        case .critical: return "bolt.circle.fill"
        }
    }
}

enum CommandType: String, CaseIterable, Codable {
    case searchArea   = "搜索區域指派"
    case standby      = "原地待命"
    case support      = "支援請求"
    case statusReport = "狀態回報"
    case evacuation   = "撤離命令"

    var key: String {
        switch self {
        case .searchArea:   return "search"
        case .standby:      return "standby"
        case .support:      return "support"
        case .statusReport: return "report"
        case .evacuation:   return "evacuation"
        }
    }

    static func fromKey(_ key: String) -> CommandType? {
        allCases.first { $0.key == key || $0.rawValue == key }
    }

    var icon: String {
        switch self {
        case .searchArea:   return "map.fill"
        case .standby:      return "pause.circle.fill"
        case .support:      return "hand.raised.fill"
        case .statusReport: return "doc.text.fill"
        case .evacuation:   return "arrow.uturn.backward.circle.fill"
        }
    }
}

struct CommandOrder: Identifiable {
    let id: UUID
    let type: CommandType
    let priority: CommandPriority
    let title: String
    let detail: String
    let sender: String
    let time: Date
    var isRead: Bool

    var timeText: String {
        HQDateFormatters.hhmmss.string(from: time)
    }
}

// MARK: - HQ Peer（多指揮中心 WiFi 同步）

/// 伺服器側記錄的已連線 HQ 同伴裝置（iPad / Android 平板 / Mac）
struct HQPeerInfo: Identifiable {
    let id: String           // connID
    let peerID: String       // 對端裝置 ID（如 "HQ-Alpha"）
    let peerName: String     // 顯示名稱
    let connectedAt: Date
}

/// hello 握手 payload
struct HQHelloPayload: Codable {
    let role: String    // "hq_peer" | "field_unit"
    let id: String      // 裝置 ID
    let name: String    // 顯示名稱
}

/// Mac 指揮中心伺服器狀態快照（同步給 HQ peer 及前線裝置）
struct HQServerStatusSnapshot: Codable {
    // 服務運行狀態
    var speechServerRunning: Bool
    var speechProcessedCount: Int
    var photoServerRunning: Bool
    var photoReceivedCount: Int
    var backendConnected: Bool
    var backendHost: String
    var aiServicePaused: Bool? = nil
    var aiServicePauseReason: String? = nil
    var audioStreamRunning: Bool?
    var udpServerRunning: Bool?
    // 即時轉錄同步（peer 用）
    var liveTranscriptions: [String: String]?
    var finalTranscriptions: [String: String]?
    var transcriptionStates: [String: String]?
    var audioStreamIsPlaying: Bool?
    var audioStreamCurrentSender: String?
    var udpConnectedClientCount: Int?
    // 前線裝置統計
    var fieldUnitCount: Int
    var onlineFieldUnitCount: Int
    var totalVictimCount: Int
    var onlineVictimCount: Int
    var sosCount: Int
    var teamCount: Int
    // 前線裝置清單
    var fieldUnits: [FieldUnitSummary]
    // NFC 寫卡紀錄（HQ peer 同步用）
    var nfcTagWrites: [NFCTagWriteRecord]? = nil
}

/// 前線裝置摘要（Codable 版本，用於 peer 同步）
struct FieldUnitSummary: Codable, Identifiable {
    let id: String
    var deviceID: String
    var deptCode: String
    var battery: Int
    var bleConnected: Bool
    var victimCount: Int
    var teamCount: Int
    var sosCount: Int
    var lastUpdate: TimeInterval
    var isOnline: Bool
}

// MARK: - 前線裝置追蹤（指揮中心用）

/// 指揮中心追蹤的已連線前線裝置
struct ConnectedFieldUnit: Identifiable {
    let id: String              // 連線識別碼
    var deviceID: String        // 前線裝置節點 ID
    var deptCode: String
    var battery: Int
    var bleConnected: Bool
    var victims: [VictimSummary]
    var teamMembers: [TeamSummary]
    var sosCount: Int
    var lastUpdate: Date
    var nickname: String?       // 使用者自訂暱稱（前線設定 → 我的暱稱）
    var isOnline: Bool { Date().timeIntervalSince(lastUpdate) < 45 }

    /// 顯示名稱：有暱稱優先，無則顯示節點 ID
    var displayName: String {
        if let nick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nick.isEmpty {
            return nick
        }
        return deviceID
    }
}

// MARK: - 快速狀態回報

enum QuickStatusType: String, Codable, CaseIterable {
    case areaClear = "area_clear"
    case needSupport = "need_support"
    case victimFound = "victim_found"
    case retreating = "retreating"

    var label: String {
        switch self {
        case .areaClear: return L("區域清除")
        case .needSupport: return L("需要支援")
        case .victimFound: return L("發現受困者")
        case .retreating: return L("撤退中")
        }
    }

    var icon: String {
        switch self {
        case .areaClear: return "checkmark.shield.fill"
        case .needSupport: return "exclamationmark.bubble.fill"
        case .victimFound: return "person.fill.questionmark"
        case .retreating: return "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .areaClear: return NV.green
        case .needSupport: return NV.warning
        case .victimFound: return NV.info
        case .retreating: return NV.danger
        }
    }
}

struct QuickStatus: Codable, Identifiable {
    let id: String
    let type: String
    let senderID: String
    let senderName: String
    var zone: String
    var note: String
    let timestamp: Double

    var statusType: QuickStatusType? { QuickStatusType(rawValue: type) }

    var timeText: String {
        let date = Date(timeIntervalSince1970: timestamp)
        return Calendar.current.isDateInToday(date)
            ? HQDateFormatters.hhmm.string(from: date)
            : HQDateFormatters.mddhhmm.string(from: date)
    }
}

// MARK: - 任務指派

enum TaskStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case accepted = "accepted"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"

    var label: String {
        switch self {
        case .pending: return L("待接受")
        case .accepted: return L("已接受")
        case .inProgress: return L("執行中")
        case .completed: return L("已完成")
        case .cancelled: return L("已取消")
        }
    }

    var color: Color {
        switch self {
        case .pending: return NV.warning
        case .accepted: return NV.info
        case .inProgress: return NV.green
        case .completed: return .gray
        case .cancelled: return NV.danger
        }
    }
}

struct TaskAssignment: Codable, Identifiable {
    let id: String
    var title: String
    var detail: String
    var assigneeID: String
    var assigneeName: String
    var zone: String
    var priority: Int
    var status: String
    let createdAt: Double
    var dueTime: Double?

    init(id: String = UUID().uuidString, title: String, detail: String = "", assigneeID: String, assigneeName: String, zone: String = "", priority: CommandPriority = .routine, status: TaskStatus = .pending, createdAt: Double = Date().timeIntervalSince1970, dueTime: Double? = nil) {
        self.id = id; self.title = title; self.detail = detail
        self.assigneeID = assigneeID; self.assigneeName = assigneeName
        self.zone = zone; self.priority = priority.rawValue
        self.status = status.rawValue; self.createdAt = createdAt; self.dueTime = dueTime
    }

    var taskStatus: TaskStatus { TaskStatus(rawValue: status) ?? .pending }
    var taskPriority: CommandPriority { CommandPriority(rawValue: priority) ?? .routine }
    var isActive: Bool { taskStatus == .pending || taskStatus == .accepted || taskStatus == .inProgress }

    var timeText: String {
        HQDateFormatters.mddhhmm.string(from: Date(timeIntervalSince1970: createdAt))
    }
}

// MARK: - 倒數計時器

struct CountdownTimerModel: Codable, Identifiable {
    let id: String
    var title: String
    var durationSeconds: Int
    let startedAt: Double
    var isBroadcast: Bool
    var targetDeviceID: String

    init(id: String = UUID().uuidString, title: String, durationSeconds: Int, startedAt: Double = Date().timeIntervalSince1970, isBroadcast: Bool = true, targetDeviceID: String = "") {
        self.id = id; self.title = title; self.durationSeconds = durationSeconds
        self.startedAt = startedAt; self.isBroadcast = isBroadcast; self.targetDeviceID = targetDeviceID
    }

    var endTime: Double { startedAt + Double(durationSeconds) }
    var remainingSeconds: Int { max(0, Int(endTime - Date().timeIntervalSince1970)) }
    var isExpired: Bool { remainingSeconds <= 0 }
    var remainingText: String {
        let m = remainingSeconds / 60; let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 危險標記

enum HazardSeverity: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var label: String {
        switch self {
        case .low: return L("低")
        case .medium: return L("中")
        case .high: return L("高")
        case .critical: return L("極高")
        }
    }

    var color: Color {
        switch self {
        case .low: return NV.info
        case .medium: return NV.warning
        case .high: return NV.danger
        case .critical: return NV.danger
        }
    }
}

struct HazardReport: Codable, Identifiable {
    let id: String
    var hazardType: String
    var description: String
    let reporterID: String
    let reporterName: String
    var zone: String
    var severity: String
    let timestamp: Double

    init(id: String = UUID().uuidString, hazardType: HazardType, description: String = "", reporterID: String, reporterName: String, zone: String = "", severity: HazardSeverity = .medium, timestamp: Double = Date().timeIntervalSince1970) {
        self.id = id; self.hazardType = hazardType.rawValue; self.description = description
        self.reporterID = reporterID; self.reporterName = reporterName
        self.zone = zone; self.severity = severity.rawValue; self.timestamp = timestamp
    }

    var hazard: HazardType? { HazardType(rawValue: hazardType) }
    var severityLevel: HazardSeverity { HazardSeverity(rawValue: severity) ?? .medium }

    var timeText: String {
        let date = Date(timeIntervalSince1970: timestamp)
        return Calendar.current.isDateInToday(date)
            ? HQDateFormatters.hhmm.string(from: date)
            : HQDateFormatters.mddhhmm.string(from: date)
    }
}

// MARK: - 隊伍能力概況

struct TeamCapabilityReport: Codable, Identifiable, Equatable {
    let id: String
    var teamName: String
    var unitCode: String
    var leaderName: String
    var contactPhone: String
    var currentLocation: String
    var stagingArea: String
    var missionStatus: String
    var totalMembers: Int
    var rescueMembers: Int
    var medicalMembers: Int
    var logisticsMembers: Int
    var availableInMinutes: Int
    var operationalHours: Int
    var selfSufficiencyHours: Int
    var ambulances: Int
    var rescueVehicles: Int
    var heavyEquipment: Int
    var boats: Int
    var drones: Int
    var radios: Int
    var capabilities: [String]
    var equipmentNotes: String
    var supportNeeds: String
    var remarks: String
    var reporterID: String
    var reporterName: String
    var timestamp: Double

    init(id: String = UUID().uuidString,
         teamName: String,
         unitCode: String,
         leaderName: String,
         contactPhone: String,
         currentLocation: String,
         stagingArea: String,
         missionStatus: String,
         totalMembers: Int,
         rescueMembers: Int,
         medicalMembers: Int,
         logisticsMembers: Int,
         availableInMinutes: Int,
         operationalHours: Int,
         selfSufficiencyHours: Int,
         ambulances: Int,
         rescueVehicles: Int,
         heavyEquipment: Int,
         boats: Int,
         drones: Int,
         radios: Int,
         capabilities: [String],
         equipmentNotes: String,
         supportNeeds: String,
         remarks: String,
         reporterID: String,
         reporterName: String,
         timestamp: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.teamName = teamName
        self.unitCode = unitCode
        self.leaderName = leaderName
        self.contactPhone = contactPhone
        self.currentLocation = currentLocation
        self.stagingArea = stagingArea
        self.missionStatus = missionStatus
        self.totalMembers = totalMembers
        self.rescueMembers = rescueMembers
        self.medicalMembers = medicalMembers
        self.logisticsMembers = logisticsMembers
        self.availableInMinutes = availableInMinutes
        self.operationalHours = operationalHours
        self.selfSufficiencyHours = selfSufficiencyHours
        self.ambulances = ambulances
        self.rescueVehicles = rescueVehicles
        self.heavyEquipment = heavyEquipment
        self.boats = boats
        self.drones = drones
        self.radios = radios
        self.capabilities = capabilities
        self.equipmentNotes = equipmentNotes
        self.supportNeeds = supportNeeds
        self.remarks = remarks
        self.reporterID = reporterID
        self.reporterName = reporterName
        self.timestamp = timestamp
    }

    var personnelSummary: String {
        "總員額 \(totalMembers) · 救援 \(rescueMembers) · 醫療 \(medicalMembers) · 後勤 \(logisticsMembers)"
    }

    var vehicleSummary: String {
        "救援車 \(rescueVehicles) · 救護車 \(ambulances) · 重機具 \(heavyEquipment) · 無人機 \(drones)"
    }

    var capabilitySummary: String {
        capabilities.isEmpty ? "未填寫能力項目" : capabilities.joined(separator: "、")
    }

    var timeText: String {
        HQDateFormatters.hhmmss.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

// MARK: - 增援請求

enum ReinforcementStatus: String, Codable {
    case pending  = "待回覆"
    case accepted = "已加入"
    case declined = "已拒絕"

    var label: String { rawValue }

    var color: Color {
        switch self {
        case .pending:  return NV.warning
        case .accepted: return NV.green
        case .declined: return NV.danger
        }
    }
}

struct ReinforcementRequest: Identifiable, Codable {
    let id: String
    var fromTeam: String
    var message: String
    var location: String
    var timestamp: Double
    var status: ReinforcementStatus
    var respondedBy: [String]

    init(id: String = UUID().uuidString, fromTeam: String, message: String, location: String = "",
         status: ReinforcementStatus = .pending, respondedBy: [String] = []) {
        self.id = id; self.fromTeam = fromTeam; self.message = message
        self.location = location; self.timestamp = Date().timeIntervalSince1970
        self.status = status; self.respondedBy = respondedBy
    }

    var timeText: String {
        HQDateFormatters.hhmmss.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

// MARK: - 通用座標 / 氣象

struct HQGPSCoord: Codable {
    let lat: Double
    let lon: Double
}

struct HQWeatherSnapshot: Codable {
    let temp: Double?
    let humidity: Double?
    let wind: Double?
    let rainfall: Double?

    init(temp: Double? = nil, humidity: Double? = nil, wind: Double? = nil, rainfall: Double? = nil) {
        self.temp = temp; self.humidity = humidity; self.wind = wind; self.rainfall = rainfall
    }
}

// MARK: - 傷員回報

struct PatientReport: Codable, Identifiable {
    var id: String { patientId }
    let patientId: String
    let nationalId: String
    let name: String
    let birthDate: String
    let age: Int?
    let location: String
    let breathingRate: Int
    let capillaryRefill: Double
    let canFollowCommands: Bool
    let gpsLat: Double?
    let gpsLon: Double?
    let notes: String
    let receivedAt: Double

    init(patientId: String, nationalId: String = "", name: String = "", birthDate: String = "", age: Int? = nil,
         location: String, breathingRate: Int, capillaryRefill: Double,
         canFollowCommands: Bool, gpsLat: Double? = nil, gpsLon: Double? = nil, notes: String = "") {
        self.patientId = patientId
        self.nationalId = nationalId; self.name = name
        self.birthDate = birthDate; self.age = age
        self.location = location
        self.breathingRate = breathingRate; self.capillaryRefill = capillaryRefill
        self.canFollowCommands = canFollowCommands
        self.gpsLat = gpsLat; self.gpsLon = gpsLon; self.notes = notes
        self.receivedAt = Date().timeIntervalSince1970
    }
}

// MARK: - HQ 決策

struct PatientDecisionEntry: Codable, Identifiable {
    let id: String
    let location: String
    let priority: String
    let reason: String
    let gps: HQGPSCoord?
    let totalScore: Double
    let startBonus: Int
    let rank: Int

    init(id: String, location: String, priority: String, reason: String = "", gps: HQGPSCoord? = nil,
         totalScore: Double = 0.0, startBonus: Int = 0, rank: Int = 0) {
        self.id = id; self.location = location; self.priority = priority
        self.reason = reason; self.gps = gps
        self.totalScore = totalScore; self.startBonus = startBonus; self.rank = rank
    }

    enum CodingKeys: String, CodingKey {
        case id, location, priority, reason, gps
        case totalScore = "total_score"
        case startBonus = "start_bonus"
        case rank
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        priority = try c.decodeIfPresent(String.self, forKey: .priority) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        gps = try c.decodeIfPresent(HQGPSCoord.self, forKey: .gps)
        totalScore = try c.decodeIfPresent(Double.self, forKey: .totalScore) ?? 0.0
        startBonus = try c.decodeIfPresent(Int.self, forKey: .startBonus) ?? 0
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
    }
}

struct HQDecisionPayload: Codable {
    let decision: String
    let patients: [PatientDecisionEntry]
    let trigger: String?
    let weather: HQWeatherSnapshot?
    let timestamp: String?
    let model: String?
    let escalated: Bool?
    // 雙模型升級欄位（V2，皆 optional）
    let request_id: String?
    let provisional: Bool?
    let escalation_status: String?
    let queue_position: Int?
    let estimated_wait_sec: Double?
    let small_model_time_ms: Int?
    let large_model_time_ms: Int?
    let error: String?

    init(decision: String, patients: [PatientDecisionEntry],
         trigger: String? = nil, weather: HQWeatherSnapshot? = nil, timestamp: String? = nil,
         model: String? = nil, escalated: Bool? = nil,
         requestId: String? = nil, provisional: Bool? = nil,
         escalationStatus: String? = nil, queuePosition: Int? = nil,
         estimatedWaitSec: Double? = nil,
         smallModelTimeMs: Int? = nil, largeModelTimeMs: Int? = nil,
         error: String? = nil) {
        self.decision = decision; self.patients = patients
        self.trigger = trigger; self.weather = weather; self.timestamp = timestamp
        self.model = model; self.escalated = escalated
        self.request_id = requestId
        self.provisional = provisional
        self.escalation_status = escalationStatus
        self.queue_position = queuePosition
        self.estimated_wait_sec = estimatedWaitSec
        self.small_model_time_ms = smallModelTimeMs
        self.large_model_time_ms = largeModelTimeMs
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decision = try c.decode(String.self, forKey: .decision)
        patients = try c.decodeIfPresent([PatientDecisionEntry].self, forKey: .patients) ?? []
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger)
        weather = try c.decodeIfPresent(HQWeatherSnapshot.self, forKey: .weather)
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        escalated = try c.decodeIfPresent(Bool.self, forKey: .escalated)
        request_id = try c.decodeIfPresent(String.self, forKey: .request_id)
        provisional = try c.decodeIfPresent(Bool.self, forKey: .provisional)
        escalation_status = try c.decodeIfPresent(String.self, forKey: .escalation_status)
        queue_position = try c.decodeIfPresent(Int.self, forKey: .queue_position)
        estimated_wait_sec = try c.decodeIfPresent(Double.self, forKey: .estimated_wait_sec)
        small_model_time_ms = try c.decodeIfPresent(Int.self, forKey: .small_model_time_ms)
        large_model_time_ms = try c.decodeIfPresent(Int.self, forKey: .large_model_time_ms)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - 電台會報

/// 電台報告來源類型
enum RadioSourceType: String {
    case live = "live"           // 即時 PTT 廣播
    case briefing = "briefing"   // 固定會報錄音
}

/// HQ 接收的電台會報報告
struct HQRadioReport: Identifiable {
    let id: UUID
    let senderName: String
    let timestamp: Date
    let transcription: String
    let locationDesc: String
    let reportId: String
    let audioURL: URL?
    let patientsCount: Int
    let weatherSnapshot: String
    let sourceType: RadioSourceType

    /// 向後相容
    var location: String { locationDesc }

    init(senderName: String, transcription: String, locationDesc: String, reportId: String,
         audioURL: URL? = nil, patientsCount: Int = 0, weatherSnapshot: String = "",
         sourceType: RadioSourceType = .live) {
        self.id = UUID()
        self.senderName = senderName
        self.timestamp = Date()
        self.transcription = transcription
        self.locationDesc = locationDesc
        self.reportId = reportId
        self.audioURL = audioURL
        self.patientsCount = patientsCount
        self.weatherSnapshot = weatherSnapshot
        self.sourceType = sourceType
    }
}

/// 電台控制 payload（PTT 開始/結束）
struct RadioControlPayload: Codable {
    let action: String
    let senderName: String

    init(action: String, senderName: String) {
        self.action = action
        self.senderName = senderName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        // 支援 camelCase (iOS) 與 snake_case (Android)
        if let name = try? container.decode(String.self, forKey: .senderName) {
            senderName = name
        } else {
            senderName = try container.decode(String.self, forKey: .senderNameSnake)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(senderName, forKey: .senderName)
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case senderName
        case senderNameSnake = "sender_name"
    }
}

/// 報告摘要 payload（中繼回前線）— 規範 10.3 欄位
struct RadioReportSummary: Codable {
    let reportId: String
    let senderName: String
    let transcription: String
    let timestamp: Double
    let locationDesc: String
    let patientsCount: Int
    let audioUrl: String?
    let weather: HQWeatherSnapshot?

    /// 向後相容
    var location: String { locationDesc }

    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case senderName = "sender_name"
        case transcription
        case timestamp
        case locationDesc = "location_desc"
        case patientsCount = "patients_count"
        case audioUrl = "audio_url"
        case weather
    }

    init(reportId: String = "", senderName: String = "", transcription: String = "",
         timestamp: Double = 0, locationDesc: String = "", patientsCount: Int = 0,
         audioUrl: String? = nil, weather: HQWeatherSnapshot? = nil) {
        self.reportId = reportId
        self.senderName = senderName
        self.transcription = transcription
        self.timestamp = timestamp
        self.locationDesc = locationDesc
        self.patientsCount = patientsCount
        self.audioUrl = audioUrl
        self.weather = weather
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reportId = try c.decodeIfPresent(String.self, forKey: .reportId) ?? ""
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        transcription = try c.decodeIfPresent(String.self, forKey: .transcription) ?? ""
        locationDesc = try c.decodeIfPresent(String.self, forKey: .locationDesc) ?? ""
        patientsCount = try c.decodeIfPresent(Int.self, forKey: .patientsCount) ?? 0
        audioUrl = try c.decodeIfPresent(String.self, forKey: .audioUrl)
        weather = try c.decodeIfPresent(HQWeatherSnapshot.self, forKey: .weather)
        // 支援 Double (Unix epoch) 與 ISO 8601 字串雙格式
        if let ts = try? c.decode(Double.self, forKey: .timestamp) {
            timestamp = ts
        } else if let iso = try? c.decode(String.self, forKey: .timestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = fmt.date(from: iso)?.timeIntervalSince1970
                ?? ISO8601DateFormatter().date(from: iso)?.timeIntervalSince1970
                ?? Date().timeIntervalSince1970
        } else {
            timestamp = 0
        }
    }
}

// MARK: - 文字廣播

struct HQTextBroadcast: Identifiable {
    let id = UUID()
    let broadcastId: String
    let message: String
    let senderName: String
    let priority: String
    let timestamp: Double

    var timeText: String {
        HQDateFormatters.hhmmss.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

// MARK: - 傷患惡化預警

struct HQPatientWarning: Identifiable {
    let id = UUID()
    let patientId: String
    let patientName: String
    let triageLevel: String
    let warningMessage: String
    let minutesSinceTriage: Int
    let timestamp: Date
}

// MARK: - 翻譯結果

struct HQTranslationResult {
    let original: String
    let translated: String
    let detectedLang: String
    let targetLang: String
}

// MARK: - SOS 即時警報

struct SOSAlert: Identifiable {
    let id: String          // sos_id
    let deviceID: String
    let senderName: String
    let lat: Double
    let lon: Double
    let timestamp: Date
}

// MARK: - AI 副駕駛指令提案（HITL）

/// AI 在 /chat/with_tools 回覆中產生的可審批指令提案。
/// 由 HQ 指揮官在 HQAIChatView 中按「執行」後，才會經 HQCommandServer.sendCommand 廣播。
struct AIProposal: Identifiable, Codable, Equatable {
    let id: String              // 後端產生（AIP-HHMMSS-N）
    let type: String            // 16 種：dispatch/alert/evacuate/medical/resource/personnel/...
    let priority: Int           // 1~5（1=最緊急）
    let title: String
    let detail: String
    let targets: [String]       // 裝置 ID；空陣列代表廣播給全部
    let rationale: String
    let timestamp: String       // ISO8601

    // Phase A 新增欄位（後端 _AI_PROPOSAL_META），舊回應可缺省
    var mode: String = "manual"                          // "auto" | "manual"
    var countdown_sec: Int = 0                           // 自動模式倒數秒數
    var require_human_double_confirm: Bool = false       // 強制人工二次確認

    enum CodingKeys: String, CodingKey {
        case id, type, priority, title, detail, targets, rationale, timestamp
        case mode, countdown_sec, require_human_double_confirm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.type = try c.decode(String.self, forKey: .type)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 3
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        self.targets = try c.decodeIfPresent([String].self, forKey: .targets) ?? []
        self.rationale = try c.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        self.timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        self.mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "manual"
        self.countdown_sec = try c.decodeIfPresent(Int.self, forKey: .countdown_sec) ?? 0
        self.require_human_double_confirm = try c.decodeIfPresent(Bool.self, forKey: .require_human_double_confirm) ?? false
    }

    init(id: String, type: String, priority: Int, title: String, detail: String,
         targets: [String], rationale: String, timestamp: String,
         mode: String = "manual", countdown_sec: Int = 0,
         require_human_double_confirm: Bool = false) {
        self.id = id
        self.type = type
        self.priority = priority
        self.title = title
        self.detail = detail
        self.targets = targets
        self.rationale = rationale
        self.timestamp = timestamp
        self.mode = mode
        self.countdown_sec = countdown_sec
        self.require_human_double_confirm = require_human_double_confirm
    }

    /// 中文類型標籤（16 種）
    var typeLabel: String {
        switch type {
        case "dispatch":                return "派遣"
        case "alert":                   return "預警"
        case "evacuate":                return "撤離"
        case "medical":                 return "醫療"
        case "resource":                return "資源"
        case "personnel":               return "人員"
        case "status_check":            return "狀態查核"
        case "escalate_to_main":        return "升級主模型"
        case "medical_priority_change": return "醫療優先序變更"
        case "resource_relocate":       return "資源調度"
        case "recall":                  return "召回"
        case "checkpoint":              return "查核點"
        case "emergency_evacuation":    return "緊急撤離"
        case "force_broadcast":         return "強制廣播"
        case "task_order":              return "任務派令"
        case "zone_lockdown":           return "區域封鎖"
        default:                        return type.uppercased()
        }
    }

    /// 對應 SF Symbol（16 種）
    var iconName: String {
        switch type {
        case "dispatch":                return "figure.run"
        case "alert":                   return "exclamationmark.triangle.fill"
        case "evacuate":                return "arrow.uturn.backward.circle.fill"
        case "medical":                 return "cross.case.fill"
        case "resource":                return "shippingbox.fill"
        case "personnel":               return "person.2.fill"
        case "status_check":            return "checkmark.shield"
        case "escalate_to_main":        return "arrow.up.circle.fill"
        case "medical_priority_change": return "heart.text.square.fill"
        case "resource_relocate":       return "arrow.left.arrow.right.square"
        case "recall":                  return "arrow.uturn.left.circle"
        case "checkpoint":              return "flag.checkered"
        case "emergency_evacuation":    return "figure.run.circle.fill"
        case "force_broadcast":         return "megaphone.fill"
        case "task_order":              return "list.clipboard.fill"
        case "zone_lockdown":           return "lock.shield.fill"
        default:                        return "bolt.fill"
        }
    }

    /// 是否為自動派遣模式（後端 _AI_PROPOSAL_META.mode == "auto"）
    var isAutoMode: Bool { mode == "auto" }
    /// 是否強制人工二次確認（緊急撤離 / 區域封鎖）
    var requiresDoubleConfirm: Bool { require_human_double_confirm }

    /// priority → 顏色
    var priorityColor: Color {
        switch priority {
        case 1:  return NV.danger
        case 2:  return Color.orange
        case 3:  return NV.warning
        case 4:  return NV.info
        default: return Color.gray
        }
    }

    var priorityLabel: String {
        switch priority {
        case 1: return "P1 緊急"
        case 2: return "P2 高"
        case 3: return "P3 中"
        case 4: return "P4 低"
        default: return "P5 備忘"
        }
    }
}


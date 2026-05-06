import Foundation
import SwiftUI

// MARK: - 共用 DateFormatter 快取（避免每次 computed property 重建）

private let _fixedTWTimeZone = TimeZone(identifier: "Asia/Taipei")!
private let _fixedPOSIXLocale = Locale(identifier: "en_US_POSIX")

enum LGDateFormat {
    static let hms: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        f.locale = _fixedPOSIXLocale; f.timeZone = _fixedTWTimeZone; return f
    }()
    static let hm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        f.locale = _fixedPOSIXLocale; f.timeZone = _fixedTWTimeZone; return f
    }()
    static let mdHm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/dd HH:mm"
        f.locale = _fixedPOSIXLocale; f.timeZone = _fixedTWTimeZone; return f
    }()
    static let mdHmShort: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
        f.locale = _fixedPOSIXLocale; f.timeZone = _fixedTWTimeZone; return f
    }()
}

// MARK: - 統一活動記錄

enum ActivityKind: String, Codable {
    case sentMessage, receivedMessage
    case personalNotification
    case command
    case hqDecision
    case pwsAlert
    case briefing
    case broadcast
    case sos
    case reinforcement
    case hazard
    case patientWarning
    case deviceAlert
    case call
    case task
    case timer
    case patientReport
    case quickStatus

    var icon: String {
        switch self {
        case .sentMessage:          return "arrow.up.circle.fill"
        case .receivedMessage:      return "arrow.down.circle.fill"
        case .personalNotification: return "bell.fill"
        case .command:              return "megaphone.fill"
        case .hqDecision:           return "checkmark.seal.fill"
        case .pwsAlert:             return "exclamationmark.triangle.fill"
        case .briefing:             return "doc.text.fill"
        case .broadcast:            return "megaphone.fill"
        case .sos:                  return "sos.circle.fill"
        case .reinforcement:        return "person.badge.plus"
        case .hazard:               return "exclamationmark.octagon.fill"
        case .patientWarning:       return "heart.text.square.fill"
        case .deviceAlert:          return "antenna.radiowaves.left.and.right.slash"
        case .call:                 return "phone.fill"
        case .task:                 return "checklist.checked"
        case .timer:                return "timer"
        case .patientReport:        return "cross.case.fill"
        case .quickStatus:          return "paperplane.fill"
        }
    }

    var defaultColor: String { "info" }
}

struct ActivityLogEntry: Identifiable {
    let id: String
    var kind: ActivityKind
    var title: String
    var detail: String
    var timestamp: Date

    init(id: String = UUID().uuidString, kind: ActivityKind, title: String, detail: String, timestamp: Date = Date()) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.timestamp = timestamp
    }

    var timeText: String {
        let fmt = Calendar.current.isDateInToday(timestamp) ? LGDateFormat.hm : LGDateFormat.mdHmShort
        return fmt.string(from: timestamp)
    }
}

// MARK: - 災害狀態模型

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

struct FloorStatus: Codable, Identifiable {
    let id: String
    var condition: FloorCondition
    var assignedTeam: String
    var note: String

    init(id: String, condition: FloorCondition = .unknown, assignedTeam: String = "", note: String = "") {
        self.id = id; self.condition = condition; self.assignedTeam = assignedTeam; self.note = note
    }
}

struct RescueZone: Codable, Identifiable {
    let id: String
    var name: String
    var status: ZoneStatus
    var assignedPersonnel: [String]
    var hazards: [HazardType]
    var note: String

    init(id: String = UUID().uuidString, name: String, status: ZoneStatus = .standby,
         assignedPersonnel: [String] = [], hazards: [HazardType] = [], note: String = "") {
        self.id = id; self.name = name; self.status = status
        self.assignedPersonnel = assignedPersonnel; self.hazards = hazards; self.note = note
    }
}

struct EntryPoint: Codable, Identifiable {
    let id: String
    var name: String
    var description: String
    var isAccessible: Bool

    init(id: String = UUID().uuidString, name: String, description: String = "", isAccessible: Bool = true) {
        self.id = id; self.name = name; self.description = description; self.isAccessible = isAccessible
    }
}

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
        self.buildingName = buildingName; self.address = address
        self.aboveGroundFloors = aboveGroundFloors; self.undergroundFloors = undergroundFloors
        self.collapseType = collapseType; self.floors = floors; self.zones = zones
        self.hazards = hazards; self.entryPoints = entryPoints
        self.rallyPoint = rallyPoint; self.note = note
        self.lastUpdated = Date().timeIntervalSince1970
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.buildingName = try container.decodeIfPresent(String.self, forKey: .buildingName) ?? ""
        self.address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        self.aboveGroundFloors = try container.decodeIfPresent(Int.self, forKey: .aboveGroundFloors) ?? 1
        self.undergroundFloors = try container.decodeIfPresent(Int.self, forKey: .undergroundFloors) ?? 0
        let collapseRaw = try container.decodeIfPresent(String.self, forKey: .collapseType) ?? ""
        self.collapseType = CollapseType(rawValue: collapseRaw) ?? .unknown
        self.floors = (try? container.decodeIfPresent([FloorStatus].self, forKey: .floors)) ?? []
        self.zones = (try? container.decodeIfPresent([RescueZone].self, forKey: .zones)) ?? []
        self.hazards = (try? container.decodeIfPresent([HazardType].self, forKey: .hazards)) ?? []
        self.entryPoints = (try? container.decodeIfPresent([EntryPoint].self, forKey: .entryPoints)) ?? []
        self.rallyPoint = try container.decodeIfPresent(String.self, forKey: .rallyPoint) ?? ""
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.lastUpdated = Self.decodeTimestamp(from: container, key: .lastUpdated) ?? Date().timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey {
        case buildingName, address, aboveGroundFloors, undergroundFloors, collapseType
        case floors, zones, hazards, entryPoints, rallyPoint, note, lastUpdated
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decode(String.self, forKey: key) {
            if let numeric = Double(value) { return numeric }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)?.timeIntervalSince1970
        }
        return nil
    }
}

// MARK: - 人員配置

enum PersonnelRole: String, Codable, CaseIterable {
    case search, rescue, medical, logistics, safety, commander, support

    var label: String {
        switch self {
        case .search: return L("搜索"); case .rescue: return L("救援"); case .medical: return L("醫療")
        case .logistics: return L("後勤"); case .safety: return L("安全官")
        case .commander: return L("指揮"); case .support: return L("支援")
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"; case .rescue: return "figure.climbing"
        case .medical: return "cross.case.fill"; case .logistics: return "shippingbox.fill"
        case .safety: return "shield.checkered"; case .commander: return "star.fill"
        case .support: return "wrench.and.screwdriver.fill"
        }
    }
}

struct PersonnelAssignment: Codable, Identifiable {
    let id: String; var name: String; var nickname: String?
    var assignedZone: String; var assignedFloor: String
    var role: PersonnelRole; var timestamp: Double

    init(id: String = UUID().uuidString, name: String, nickname: String? = nil,
         assignedZone: String = "",
         assignedFloor: String = "", role: PersonnelRole = .search) {
        self.id = id; self.name = name; self.nickname = nickname
        self.assignedZone = assignedZone
        self.assignedFloor = assignedFloor; self.role = role
        self.timestamp = Date().timeIntervalSince1970
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        self.assignedZone = try container.decodeIfPresent(String.self, forKey: .assignedZone) ?? ""
        self.assignedFloor = try container.decodeIfPresent(String.self, forKey: .assignedFloor) ?? ""
        let roleRaw = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        self.role = PersonnelRole(rawValue: roleRaw) ?? .search
        self.timestamp = Self.decodeTimestamp(from: container, key: .timestamp) ?? Date().timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, nickname, assignedZone, assignedFloor, role, timestamp
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decode(String.self, forKey: key) {
            if let numeric = Double(value) { return numeric }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)?.timeIntervalSince1970
        }
        return nil
    }

    var displayLabel: String {
        let head = (nickname?.isEmpty == false) ? nickname! : name
        return "\(head) (\(String(id.suffix(8))))"
    }
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

// MARK: - 通訊

struct ChatMessage: Codable, Identifiable {
    let id: String; let senderID: String; let senderName: String
    var recipientID: String?; let content: String; let timestamp: Double; var isRead: Bool
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
        self.id = id; self.senderID = senderID; self.senderName = senderName
        self.recipientID = recipientID; self.content = content
        self.timestamp = Date().timeIntervalSince1970; self.isRead = isRead
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
        LGDateFormat.hms.string(from: Date(timeIntervalSince1970: timestamp))
    }
    var isBroadcast: Bool { recipientID == nil }
}

// MARK: - 通話模式

enum CallStatus: String, Codable, CaseIterable {
    case ringing
    case active
    case declined
    case ended
    case missed

    var label: String {
        switch self {
        case .ringing: return L("響鈴中")
        case .active: return L("通話中")
        case .declined: return L("已拒絕")
        case .ended: return L("已結束")
        case .missed: return L("未接來電")
        }
    }
}

struct CallInvite: Codable, Identifiable, Equatable {
    let callID: String
    let initiatorID: String
    let initiatorName: String
    let targetDeviceIDs: [String]
    var participants: [String]
    let createdAt: Double
    let expiresAt: Double
    let mode: String
    var status: CallStatus

    var id: String { callID }
    var isExpired: Bool { Date().timeIntervalSince1970 >= expiresAt }

    init(callID: String = UUID().uuidString,
         initiatorID: String,
         initiatorName: String,
         targetDeviceIDs: [String],
         participants: [String] = [],
         createdAt: Double = Date().timeIntervalSince1970,
         expiresAt: Double? = nil,
         mode: String = "duplex",
         status: CallStatus = .ringing) {
        self.callID = callID
        self.initiatorID = initiatorID
        self.initiatorName = initiatorName
        self.targetDeviceIDs = targetDeviceIDs
        self.participants = participants.isEmpty ? [initiatorID] : participants
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? (createdAt + 30)
        self.mode = mode
        self.status = status
    }
}

struct CallResponse: Codable, Identifiable, Equatable {
    let callID: String
    let responderID: String
    let responderName: String
    let accepted: Bool
    let timestamp: Double

    var id: String { "\(callID)-\(responderID)-\(timestamp)" }

    init(callID: String,
         responderID: String,
         responderName: String,
         accepted: Bool,
         timestamp: Double = Date().timeIntervalSince1970) {
        self.callID = callID
        self.responderID = responderID
        self.responderName = responderName
        self.accepted = accepted
        self.timestamp = timestamp
    }
}

struct CallEnd: Codable, Identifiable, Equatable {
    let callID: String
    let senderID: String
    let reason: String
    let timestamp: Double

    var id: String { "\(callID)-end-\(timestamp)" }

    init(callID: String,
         senderID: String,
         reason: String = "ended",
         timestamp: Double = Date().timeIntervalSince1970) {
        self.callID = callID
        self.senderID = senderID
        self.reason = reason
        self.timestamp = timestamp
    }
}

struct CallSession: Codable, Identifiable, Equatable {
    let callID: String
    let initiatorID: String
    let initiatorName: String
    var participants: [String]
    var status: CallStatus
    let startedAt: Double
    var endedAt: Double?
    let mode: String

    var id: String { callID }

    init(callID: String,
         initiatorID: String,
         initiatorName: String,
         participants: [String],
         status: CallStatus = .active,
         startedAt: Double = Date().timeIntervalSince1970,
         endedAt: Double? = nil,
         mode: String = "ptt") {
        self.callID = callID
        self.initiatorID = initiatorID
        self.initiatorName = initiatorName
        self.participants = Array(Set(participants)).sorted()
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
    }
}

// MARK: - PWS 警報

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
        case .earthquake: return "waveform.path.ecg"; case .aftershock: return "waveform.badge.exclamationmark"
        case .tsunami: return "water.waves"; case .typhoon: return "tropicalstorm"
        case .flood: return "cloud.heavyrain.fill"; case .landslide: return "mountain.2.fill"
        case .other: return "exclamationmark.triangle.fill"
        }
    }
}

enum PWSSeverity: String, Codable, CaseIterable, Comparable {
    case info, minor, moderate, severe, extreme

    var value: Int {
        switch self {
        case .info: return 0; case .minor: return 1; case .moderate: return 2
        case .severe: return 3; case .extreme: return 4
        }
    }

    static func < (lhs: PWSSeverity, rhs: PWSSeverity) -> Bool { lhs.value < rhs.value }

    var label: String {
        switch self {
        case .info: return L("資訊"); case .minor: return L("輕微"); case .moderate: return L("中等")
        case .severe: return L("嚴重"); case .extreme: return L("極端")
        }
    }
    var color: Color {
        switch self {
        case .info: return NV.info; case .minor: return NV.green; case .moderate: return NV.warning
        case .severe: return NV.reinforce; case .extreme: return NV.danger
        }
    }
}

struct PWSAlert: Codable, Identifiable {
    let id: String; var alertType: PWSAlertType; var title: String; var content: String
    var severity: PWSSeverity; var publisher: String; var publishTime: Double
    var expireTime: Double?; var isActive: Bool

    init(id: String = UUID().uuidString, alertType: PWSAlertType, title: String,
         content: String, severity: PWSSeverity, publisher: String = "HQ", expireTime: Double? = nil) {
        self.id = id; self.alertType = alertType; self.title = title
        self.content = content; self.severity = severity; self.publisher = publisher
        self.publishTime = Date().timeIntervalSince1970; self.expireTime = expireTime; self.isActive = true
    }
}

// MARK: - 會報

enum BriefingType: String, Codable, CaseIterable {
    case initial, progress, shift
    case final_ = "final"

    var label: String {
        switch self {
        case .initial: return L("初期報告"); case .progress: return L("進度報告")
        case .shift: return L("交接報告"); case .final_: return L("結案報告")
        }
    }
}

struct BriefingSection: Codable, Identifiable {
    let id: String; var title: String; var content: String
    init(id: String = UUID().uuidString, title: String, content: String = "") {
        self.id = id; self.title = title; self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
    }
}

struct BriefingReport: Codable, Identifiable {
    let id: String; var title: String; var type: BriefingType; var author: String
    var timestamp: Double; var sections: [BriefingSection]

    init(id: String = UUID().uuidString, title: String, type: BriefingType = .progress,
         author: String = "HQ", sections: [BriefingSection] = []) {
        self.id = id; self.title = title; self.type = type; self.author = author
        self.timestamp = Date().timeIntervalSince1970; self.sections = sections
    }
    var timeText: String {
        LGDateFormat.mdHm.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

// MARK: - 個人通知

struct PersonalNotification: Codable, Identifiable {
    let id: String; var targetDeviceID: String; var title: String; var content: String
    var timestamp: Double; var isRead: Bool

    init(
        id: String = UUID().uuidString,
        targetDeviceID: String,
        title: String,
        content: String,
        timestamp: Double = Date().timeIntervalSince1970,
        isRead: Bool = false
    ) {
        self.id = id; self.targetDeviceID = targetDeviceID; self.title = title
        self.content = content; self.timestamp = timestamp; self.isRead = isRead
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        self.id = Self.decodeString(from: container, keys: ["id"]) ?? UUID().uuidString
        self.targetDeviceID = Self.decodeString(
            from: container,
            keys: ["targetDeviceID", "targetDeviceId", "target_device_id", "target_device"]
        ) ?? ""
        self.title = Self.decodeString(from: container, keys: ["title"]) ?? ""
        self.content = Self.decodeString(from: container, keys: ["content", "message", "body"]) ?? ""
        self.timestamp = Self.decodeTimestamp(from: container, keys: ["timestamp", "time", "created_at"])
            ?? Date().timeIntervalSince1970
        self.isRead = Self.decodeBool(from: container, keys: ["isRead", "is_read", "read"]) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(targetDeviceID, forKey: .targetDeviceID)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isRead, forKey: .isRead)
    }

    var timeText: String {
        LGDateFormat.hms.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private enum CodingKeys: String, CodingKey {
        case id, targetDeviceID, title, content, timestamp, isRead
    }

    private struct FlexibleCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) -> String? {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else { continue }
            if let value = try? container.decode(String.self, forKey: key) { return value }
            if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
            if let value = try? container.decode(Double.self, forKey: key) { return String(value) }
        }
        return nil
    }

    private static func decodeTimestamp(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) -> Double? {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else { continue }
            if let value = try? container.decode(Double.self, forKey: key) { return value }
            if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
            if let value = try? container.decode(String.self, forKey: key) {
                if let numeric = Double(value) { return numeric }
                if let date = isoDate(from: value) { return date.timeIntervalSince1970 }
            }
        }
        return nil
    }

    private static func decodeBool(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) -> Bool? {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else { continue }
            if let value = try? container.decode(Bool.self, forKey: key) { return value }
            if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
            if let value = try? container.decode(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "yes", "1"].contains(normalized) { return true }
                if ["false", "no", "0"].contains(normalized) { return false }
            }
        }
        return nil
    }

    private static func isoDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

// MARK: - LoRa 檔位（對應韌體 profiles[0..8]）

struct LoRaProfile {
    let level: Int
    let sf: Int
    let bw: Double
    let cr: Int
    let label: String
}

let loraProfiles: [LoRaProfile] = [
    LoRaProfile(level: 0, sf: 7,  bw: 500.0, cr: 5, label: L("L0:極速")),
    LoRaProfile(level: 1, sf: 7,  bw: 250.0, cr: 5, label: L("L1:高速")),
    LoRaProfile(level: 2, sf: 8,  bw: 250.0, cr: 5, label: L("L2:敏捷")),
    LoRaProfile(level: 3, sf: 9,  bw: 250.0, cr: 6, label: L("L3:平衡")),
    LoRaProfile(level: 4, sf: 9,  bw: 125.0, cr: 6, label: L("L4:標準")),
    LoRaProfile(level: 5, sf: 10, bw: 125.0, cr: 7, label: L("L5:穿透")),
    LoRaProfile(level: 6, sf: 10, bw: 62.5,  cr: 8, label: L("L6:強穿")),
    LoRaProfile(level: 7, sf: 11, bw: 62.5,  cr: 8, label: L("L7:極限")),
    LoRaProfile(level: 8, sf: 12, bw: 62.5,  cr: 8, label: L("L8:最遠")),
]

// MARK: - 受困者資料（對應韌體 VictimNode）

struct VictimNode: Identifiable {
    let id: String             // 受困者 ID（如 VT-A3F）
    var heartRate: Int         // BPM，0 = 無資料
    var battery: Int           // 0-100
    var rssi: Double           // dBm
    var snr: Double
    var isSOS: Bool
    var lastSeen: Date
    var isOnline: Bool         // lastSeen < 30 秒

    /// 距離估算（對應韌體 estimateDistance: n=2.7, A=-30）
    var estimatedDistance: Double {
        let n = 2.7
        let A = -30.0
        return pow(10.0, (A - rssi) / (10.0 * n))
    }

    var distanceText: String {
        let d = estimatedDistance
        if d < 0.1  { return "<0.1m" }
        if d < 10   { return String(format: "%.1fm", d) }
        if d < 1000 { return "\(Int(d))m" }
        return String(format: "%.1fkm", d / 1000)
    }

    var heartRateText: String {
        heartRate > 0 ? "\(heartRate) bpm" : "-- bpm"
    }

    var lastSeenText: String {
        let interval = Date().timeIntervalSince(lastSeen)
        if interval < 5    { return L("剛剛") }
        if interval < 60   { return "\(Int(interval)) 秒前" }
        if interval < 3600 { return "\(Int(interval / 60)) 分鐘前" }
        return "\(Int(interval / 3600)) 小時前"
    }

    var signalColor: Color {
        guard isOnline else { return .gray }
        if rssi > -70 { return NV.green }
        if rssi > -85 { return NV.warning }
        return NV.danger
    }
}

// MARK: - 搜救節點自身狀態

struct RescueNodeStatus {
    var nodeID: String         // 如 RT-A3F-EMT
    var deptCode: String       // 部門碼 EMT / FD / PD
    var battery: Int           // 0-100
    var voltage: Double = 0    // 電池電壓 (V)
    var loraLevel: Int         // 0-8
    var isConnected: Bool
    var pairCode: String       // LoRa 配對碼

    var loraProfile: LoRaProfile {
        loraProfiles[min(max(loraLevel, 0), 8)]
    }

    var batteryColor: Color {
        if battery > 50 { return NV.green }
        if battery > 20 { return NV.warning }
        return NV.danger
    }
}

// MARK: - SOS 警報紀錄

struct SOSRecord: Identifiable {
    let id: UUID
    var sosID: String = ""
    var victimID: String
    var senderName: String = ""
    var message: String = ""
    var locationDescription: String = ""
    var latitude: Double?
    var longitude: Double?
    var heartRate: Int
    var rssi: Double
    var distance: String
    var battery: Int
    var time: Date
    var isAcknowledged: Bool

    var displayTitle: String {
        if !senderName.isEmpty && senderName != victimID {
            return "\(senderName) · \(victimID)"
        }
        return victimID.isEmpty ? L("未知 SOS") : victimID
    }

    var coordinateText: String? {
        guard let latitude, let longitude else { return nil }
        guard latitude != 0 || longitude != 0 else { return nil }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    var timeText: String {
        LGDateFormat.hms.string(from: time)
    }
}

// MARK: - 韌體 /up JSON 解析

struct FirmwareStatusResponse: Decodable {
    let id: String?
    let dept: String?
    let bat: Int
    let vbat: Double?
    let lvl: Int
    let pair: String?
    let victims: [FirmwareVictim]
    let team: [FirmwareTeamNode]?
    let rf: [FirmwareReinforcement]?
}

struct FirmwareVictim: Decodable {
    let id: String
    let hr: Int
    let bat: Int
    let rssi: Double
    let dist: String?
    let snr: Double?
    let sos: Bool
    let online: Bool
}

/// 韌體団隊節點 JSON
struct FirmwareTeamNode: Decodable {
    let id: String
    let dept: String
    let bat: Int
    let rssi: Double
    let vc: Int
    let online: Bool
}

/// 韌體增援請求 JSON
struct FirmwareReinforcement: Decodable {
    let from: String
    let msg: String
    let loc: String
    let ago: Int
}

// MARK: - 指揮中心命令

/// 命令優先等級
enum CommandPriority: Int, CaseIterable, Comparable {
    case routine  = 0   // 一般
    case urgent   = 1   // 緊急
    case critical = 2   // 最高

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

/// 命令類型
enum CommandType: String, CaseIterable {
    case searchArea   = "搜索區域指派"
    case standby      = "原地待命"
    case support      = "支援請求"
    case statusReport = "狀態回報"
    case evacuation   = "撤離命令"

    /// LoRa JSON 用的英文 key
    var key: String {
        switch self {
        case .searchArea:   return "search"
        case .standby:      return "standby"
        case .support:      return "support"
        case .statusReport: return "report"
        case .evacuation:   return "evacuation"
        }
    }

    /// 從 LoRa JSON key 或中文 rawValue 反查
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

/// 指揮中心命令記錄
struct CommandOrder: Identifiable {
    let id: UUID
    let type: CommandType
    let priority: CommandPriority
    let title: String
    let detail: String
    let sender: String          // 指揮中心代號（如 "HQ-Alpha"）
    let time: Date
    var isRead: Bool

    var timeText: String {
        LGDateFormat.hms.string(from: time)
    }
}

// MARK: - 增援請求

/// 增援請求狀態
enum ReinforcementStatus: String {
    case pending  = "待回覆"
    case accepted = "已加入"
    case declined = "已拒絕"
    case expired  = "已過期"

    var color: Color {
        switch self {
        case .pending:  return NV.warning
        case .accepted: return NV.green
        case .declined: return NV.danger
        case .expired:  return .gray
        }
    }

    var icon: String {
        switch self {
        case .pending:  return "questionmark.circle.fill"
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .expired:  return "clock.badge.xmark"
        }
    }
}

/// 增援請求記錄
struct ReinforcementRequest: Identifiable {
    let id: UUID
    let fromTeam: String        // 請求增援的隊伍 ID
    let message: String         // 說明（如「需要醫療支援」）
    let location: String        // 位置描述
    let time: Date
    var status: ReinforcementStatus
    var respondedBy: [String]   // 回覆的隊伍 ID 列表

    var timeText: String {
        LGDateFormat.hms.string(from: time)
    }

    var isFromSelf: Bool = false // 是否為自己發出的
}

// MARK: - 團隊

/// 團隊成員（其他搜救節點）
struct TeamMember: Identifiable {
    let id: String              // 節點 ID（如 RT-A3F-EMT）
    var deptCode: String        // 部門碼
    var battery: Int
    var rssi: Double
    var lastSeen: Date
    var isOnline: Bool
    var victimCount: Int        // 該隊追蹤的受困者數
    var nickname: String? = nil

    var displayLabel: String {
        let head = (nickname?.isEmpty == false) ? nickname! : id
        return "\(head) (\(deptCode))"
    }

    var lastSeenText: String {
        let interval = Date().timeIntervalSince(lastSeen)
        if interval < 5    { return L("剛剛") }
        if interval < 60   { return "\(Int(interval)) 秒前" }
        if interval < 3600 { return "\(Int(interval / 60)) 分鐘前" }
        return "\(Int(interval / 3600)) 小時前"
    }

    var signalColor: Color {
        guard isOnline else { return .gray }
        if rssi > -70 { return NV.green }
        if rssi > -85 { return NV.warning }
        return NV.danger
    }
}

// MARK: - 快速狀態回報

enum QuickStatusType: String, Codable, CaseIterable {
    case areaClear      = "area_clear"
    case needSupport    = "need_support"
    case victimFound    = "victim_found"
    case retreating     = "retreating"

    var label: String {
        switch self {
        case .areaClear:   return L("區域清除")
        case .needSupport: return L("需要支援")
        case .victimFound: return L("發現受困者")
        case .retreating:  return L("撤退中")
        }
    }

    var icon: String {
        switch self {
        case .areaClear:   return "checkmark.shield.fill"
        case .needSupport: return "exclamationmark.bubble.fill"
        case .victimFound: return "person.fill.questionmark"
        case .retreating:  return "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .areaClear:   return NV.green
        case .needSupport: return NV.warning
        case .victimFound: return NV.info
        case .retreating:  return NV.danger
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

    init(id: String = UUID().uuidString, type: QuickStatusType, senderID: String, senderName: String, zone: String = "", note: String = "", timestamp: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.type = type.rawValue
        self.senderID = senderID
        self.senderName = senderName
        self.zone = zone
        self.note = note
        self.timestamp = timestamp
    }

    var statusType: QuickStatusType? { QuickStatusType(rawValue: type) }

    var timeText: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let fmt = Calendar.current.isDateInToday(date) ? LGDateFormat.hm : LGDateFormat.mdHmShort
        return fmt.string(from: date)
    }
}

// MARK: - 任務指派

enum TaskStatus: String, Codable, CaseIterable {
    case pending     = "pending"
    case accepted    = "accepted"
    case inProgress  = "in_progress"
    case completed   = "completed"
    case cancelled   = "cancelled"

    var label: String {
        switch self {
        case .pending:    return L("待接受")
        case .accepted:   return L("已接受")
        case .inProgress: return L("執行中")
        case .completed:  return L("已完成")
        case .cancelled:  return L("已取消")
        }
    }

    var color: Color {
        switch self {
        case .pending:    return NV.warning
        case .accepted:   return NV.info
        case .inProgress: return NV.green
        case .completed:  return .gray
        case .cancelled:  return NV.danger
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
        self.id = id
        self.title = title
        self.detail = detail
        self.assigneeID = assigneeID
        self.assigneeName = assigneeName
        self.zone = zone
        self.priority = priority.rawValue
        self.status = status.rawValue
        self.createdAt = createdAt
        self.dueTime = dueTime
    }

    var taskStatus: TaskStatus { TaskStatus(rawValue: status) ?? .pending }
    var taskPriority: CommandPriority { CommandPriority(rawValue: priority) ?? .routine }

    var timeText: String {
        LGDateFormat.mdHmShort.string(from: Date(timeIntervalSince1970: createdAt))
    }

    var isActive: Bool { taskStatus == .pending || taskStatus == .accepted || taskStatus == .inProgress }
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
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.isBroadcast = isBroadcast
        self.targetDeviceID = targetDeviceID
    }

    var endTime: Double { startedAt + Double(durationSeconds) }

    var remainingSeconds: Int {
        max(0, Int(endTime - Date().timeIntervalSince1970))
    }

    var isExpired: Bool { remainingSeconds <= 0 }

    var remainingText: String {
        let r = remainingSeconds
        let m = r / 60; let s = r % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 危險標記

enum HazardSeverity: String, Codable, CaseIterable {
    case low      = "low"
    case medium   = "medium"
    case high     = "high"
    case critical = "critical"

    var label: String {
        switch self {
        case .low:      return L("低")
        case .medium:   return L("中")
        case .high:     return L("高")
        case .critical: return L("極高")
        }
    }

    var color: Color {
        switch self {
        case .low:      return NV.info
        case .medium:   return NV.warning
        case .high:     return NV.danger
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
        self.id = id
        self.hazardType = hazardType.rawValue
        self.description = description
        self.reporterID = reporterID
        self.reporterName = reporterName
        self.zone = zone
        self.severity = severity.rawValue
        self.timestamp = timestamp
    }

    var hazard: HazardType? { HazardType(rawValue: hazardType) }
    var severityLevel: HazardSeverity { HazardSeverity(rawValue: severity) ?? .medium }

    var timeText: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let fmt = Calendar.current.isDateInToday(date) ? LGDateFormat.hm : LGDateFormat.mdHmShort
        return fmt.string(from: date)
    }
}

// MARK: - 預設訊息模板

struct PresetMessage: Identifiable {
    var id = UUID()
    let text: String
    let icon: String
}

let presetMessages: [PresetMessage] = [
    PresetMessage(text: L("收到"), icon: "checkmark"),
    PresetMessage(text: L("已到達"), icon: "mappin.and.ellipse"),
    PresetMessage(text: L("請求確認"), icon: "questionmark.circle"),
    PresetMessage(text: L("了解，執行中"), icon: "play.fill"),
    PresetMessage(text: L("任務完成"), icon: "checkmark.circle.fill"),
    PresetMessage(text: L("需要更多人力"), icon: "person.badge.plus"),
    PresetMessage(text: L("情況緊急"), icon: "exclamationmark.triangle.fill"),
    PresetMessage(text: L("安全撤離完成"), icon: "arrow.uturn.backward.circle.fill"),
]

// MARK: - 傷員回報

/// 前線發送的傷員狀態資料（規範 3.1）
struct PatientReport: Codable, Identifiable {
    var id: String { patientId }
    let patientId: String
    let nationalId: String       // 身分證字號
    let name: String             // 姓名
    let birthDate: String        // 出生年月日（原始輸入，支援西元/民國）
    let age: Int?                // 自動計算年齡
    let location: String
    let breathingRate: Int       // -1 代表無呼吸
    let capillaryRefill: Double  // -1 代表無脈搏
    let canFollowCommands: Bool
    let gpsLat: Double?
    let gpsLon: Double?
    let notes: String

    init(patientId: String? = nil, nationalId: String = "", name: String = "", birthDate: String = "", age: Int? = nil,
         location: String, breathingRate: Int, capillaryRefill: Double,
         canFollowCommands: Bool, gpsLat: Double? = nil, gpsLon: Double? = nil, notes: String = "") {
        self.patientId = patientId ?? "P\(Int(Date().timeIntervalSince1970))"
        self.nationalId = nationalId
        self.name = name
        self.birthDate = birthDate
        self.age = age
        self.location = location
        self.breathingRate = breathingRate
        self.capillaryRefill = capillaryRefill
        self.canFollowCommands = canFollowCommands
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
        self.notes = notes
    }
}

/// HQ 決策中傷員列表的單筆條目（規範 6.1）
struct PatientDecisionEntry: Codable, Identifiable {
    let id: String
    let location: String
    let priority: String
    let reason: String
    let gps: GPSCoord?

    enum CodingKeys: String, CodingKey {
        case id, location, priority, reason, gps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        priority = try c.decode(String.self, forKey: .priority)
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        gps = try c.decodeIfPresent(GPSCoord.self, forKey: .gps)
    }
}

struct GPSCoord: Codable {
    let lat: Double
    let lon: Double
}

/// 從 HQ 接收的指揮決策（規範 6.1）
struct HQDecision: Identifiable, Codable {
    let id: UUID
    let decisionId: String  // 伺服器生成的 decision_id（用於已讀追蹤）
    var decision: String
    var patients: [PatientDecisionEntry]
    let timestamp: String
    let trigger: String       // "patient" | "voice" | "manual"
    let weather: WeatherSnapshot?
    let receivedAt: Date
    var model: String
    var escalated: Bool
    // 雙模型升級狀態（V2）
    var requestId: String?
    var provisional: Bool
    var escalationStatus: String?  // pending|queued|processing|done|failed|not_required|peer_offline
    var queuePosition: Int?
    var estimatedWaitSec: Double?
    var smallModelTimeMs: Int?
    var largeModelTimeMs: Int?
    var escalationError: String?

    init(decision: String, patients: [PatientDecisionEntry], timestamp: String,
         trigger: String = "", weather: WeatherSnapshot? = nil, decisionId: String = "",
         model: String = "", escalated: Bool = false,
         requestId: String? = nil, provisional: Bool = false,
         escalationStatus: String? = nil, queuePosition: Int? = nil,
         estimatedWaitSec: Double? = nil,
         smallModelTimeMs: Int? = nil, largeModelTimeMs: Int? = nil,
         escalationError: String? = nil) {
        self.id = UUID()
        self.decisionId = decisionId
        self.decision = decision
        self.patients = patients
        self.timestamp = timestamp
        self.trigger = trigger
        self.weather = weather
        self.receivedAt = Date()
        self.model = model
        self.escalated = escalated
        self.requestId = requestId
        self.provisional = provisional
        self.escalationStatus = escalationStatus
        self.queuePosition = queuePosition
        self.estimatedWaitSec = estimatedWaitSec
        self.smallModelTimeMs = smallModelTimeMs
        self.largeModelTimeMs = largeModelTimeMs
        self.escalationError = escalationError
    }
}

struct WeatherSnapshot: Codable {
    let temperature: Double?
    let humidity: Double?
    let wind_speed: Double?
    let rainfall: Double?
}

// 用於 JSON 解碼 HQDecision（規範 6.1）
struct HQDecisionPayload: Codable {
    let decision: String
    let patients: [PatientDecisionEntry]
    let trigger: String?
    let weather: WeatherSnapshot?
    let timestamp: String?
    let model: String?
    let escalated: Bool?
    // 雙模型升級欄位（V2，皆 optional 以保相容）
    let request_id: String?
    let provisional: Bool?
    let escalation_status: String?
    let queue_position: Int?
    let estimated_wait_sec: Double?
    let small_model_time_ms: Int?
    let large_model_time_ms: Int?
    let error: String?
}

// MARK: - 電台 / 會報

/// 電台會報報告（前線上傳後收到的摘要）
struct RadioReport: Identifiable, Codable {
    let id: String
    let senderName: String
    let timestamp: Double
    let transcription: String
    let location: String
    let reportId: String
    let patientsCount: Int
    let audioUrl: String
    let weather: WeatherSnapshot?

    enum CodingKeys: String, CodingKey {
        case id
        case senderName = "sender_name"
        case timestamp
        case transcription
        case location = "location_desc"
        case reportId = "report_id"
        case patientsCount = "patients_count"
        case audioUrl = "audio_url"
        case weather
    }

    /// 與 HQ HQRadioReport 一致的別名
    var locationDesc: String { location }

    init(senderName: String, transcription: String, location: String, reportId: String,
         patientsCount: Int = 0, audioUrl: String = "", weather: WeatherSnapshot? = nil) {
        self.id = UUID().uuidString
        self.senderName = senderName
        self.timestamp = Date().timeIntervalSince1970
        self.transcription = transcription
        self.location = location
        self.reportId = reportId
        self.patientsCount = patientsCount
        self.audioUrl = audioUrl
        self.weather = weather
    }
}

/// 從 HQ / 伺服器中繼回來的報告摘要（規範 10.3）
struct RadioReportSummary: Codable {
    let reportId: String
    let senderName: String
    let transcription: String
    let locationDesc: String
    let patientsCount: Int
    let weather: WeatherSnapshot?
    let audioUrl: String?
    let timestamp: Double

    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case senderName = "sender_name"
        case transcription
        case locationDesc = "location_desc"
        case patientsCount = "patients_count"
        case weather
        case audioUrl = "audio_url"
        case timestamp
    }

    /// 供 RadioReport 轉換用的便利屬性
    var location: String { locationDesc }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reportId = try c.decodeIfPresent(String.self, forKey: .reportId) ?? ""
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        transcription = try c.decodeIfPresent(String.self, forKey: .transcription) ?? ""
        locationDesc = try c.decodeIfPresent(String.self, forKey: .locationDesc) ?? ""
        patientsCount = try c.decodeIfPresent(Int.self, forKey: .patientsCount) ?? 0
        weather = try c.decodeIfPresent(WeatherSnapshot.self, forKey: .weather)
        audioUrl = try c.decodeIfPresent(String.self, forKey: .audioUrl)
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
            timestamp = Date().timeIntervalSince1970
        }
    }
}

/// 電台控制訊息 payload
struct RadioControlPayload: Codable {
    let action: String   // "start" or "stop"
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

// MARK: - 照片回報模型

struct PhotoReport: Identifiable, Codable {
    let id: String  // photo_id
    let senderName: String
    let lat: Double
    let lon: Double
    let locationDesc: String
    let caption: String
    let thumbnailURL: String
    let fullURL: String
    let timestamp: Date
    var mediaType: String = "photo"  // "photo" or "video"

    enum CodingKeys: String, CodingKey {
        case id
        case senderName = "sender_name"
        case lat, lon
        case locationDesc = "location_desc"
        case caption
        case thumbnailURL = "thumbnail_url"
        case fullURL = "full_url"
        case timestamp
        case mediaType = "media_type"
    }
}

// MARK: - 資源狀態模型

struct ResourceStatus: Codable {
    let ambulanceTotal: Int
    let ambulanceAvailable: Int
    let medicalKitTotal: Int
    let medicalKitAvailable: Int
    let personnelTotal: Int
    let personnelAvailable: Int

    var ambulanceText: String { "救護車 \(ambulanceAvailable)/\(ambulanceTotal) 可用" }
    var medicalKitText: String { "醫療包 \(medicalKitAvailable)/\(medicalKitTotal) 可用" }
    var personnelText: String { "人員 \(personnelAvailable)/\(personnelTotal) 可用" }
}

// MARK: - 文字廣播模型

struct TextBroadcast: Identifiable, Codable {
    let id: String  // broadcast_id
    let broadcastId: String
    let message: String
    let senderName: String
    let priority: String  // "normal" / "urgent"
    let timestamp: Date
}

// MARK: - 傷患惡化預警模型

struct PatientWarning: Identifiable, Codable {
    var id = UUID()
    let patientId: String
    let priority: String
    let location: String
    let minutesSinceTriage: Int
    let warningLevel: String  // "high" / "medium" / "low"
    let message: String
    let timestamp: Date
}

// MARK: - 翻譯結果模型

struct TranslationResult: Identifiable, Codable {
    var id = UUID()
    let original: String
    let translated: String
    let detectedLang: String
    let targetLang: String
}

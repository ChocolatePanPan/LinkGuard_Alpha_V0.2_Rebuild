import Foundation

// MARK: - Point Types (8 types)
/// 地圖點標記類型（8 種災害現場標記點）
public enum MapPointType: String, Codable, CaseIterable, Sendable {
    case sos              // 緊急求救
    case victim           // 傷患位置
    case survivor         // 受困者定位
    case rescueTeamMember // 隊員/搜救員位置
    case hazardPoint      // 危險點（瓦斯/電線等）
    case assemblyPoint    // 臨時據點/集結點
    case medicalStation   // EMT醫療站
    case commandPost      // 指揮所（SCC/UCC）
    
    public var displayName: String {
        switch self {
        case .sos: return "SOS"
        case .victim: return "傷患"
        case .survivor: return "受困者"
        case .rescueTeamMember: return "隊員"
        case .hazardPoint: return "危險點"
        case .assemblyPoint: return "集結點"
        case .medicalStation: return "醫療站"
        case .commandPost: return "指揮所"
        }
    }
    
    public var systemColor: String {
        switch self {
        case .sos, .hazardPoint: return "#FF0000" // 紅色
        case .victim: return "#FFFF00"               // 黃色
        case .survivor, .rescueTeamMember: return "#0000FF" // 藍色
        case .assemblyPoint, .medicalStation: return "#00FF00" // 綠色
        case .commandPost: return "#0000FF"         // 藍色
        }
    }
}

// MARK: - Line Types (6 types)
/// 地圖線標記類型（6 種災害現場標記線）
public enum MapLineType: String, Codable, CaseIterable, Sendable {
    case evacuationRoute  // 撤離路線
    case hazardousRoute   // 危險路線
    case searchPath       // 搜索動線
    case supplyRoute      // 補給路線
    case cordonLine       // 封鎖線
    case passageway       // 通道/可通行區域
    
    public var displayName: String {
        switch self {
        case .evacuationRoute: return "撤離路線"
        case .hazardousRoute: return "危險路線"
        case .searchPath: return "搜索動線"
        case .supplyRoute: return "補給路線"
        case .cordonLine: return "封鎖線"
        case .passageway: return "通道"
        }
    }
    
    public var systemColor: String {
        switch self {
        case .evacuationRoute: return "#00FF00"     // 綠色
        case .hazardousRoute: return "#FF0000"      // 紅色
        case .searchPath: return "#0000FF"          // 藍色
        case .supplyRoute: return "#FFFF00"         // 黃色
        case .cordonLine: return "#000000"          // 黑色
        case .passageway: return "#00FF00"          // 綠色
        }
    }
}

// MARK: - Polygon Types (7 types)
/// 地圖面標記類型（7 種災害現場標記面）
public enum MapPolygonType: String, Codable, CaseIterable, Sendable {
    case collapsedArea    // 倒塌區
    case searchArea       // 搜救區
    case subzone          // 子區域（D1/D2）
    case hazardousZone    // 危險區
    case cleanedArea      // 已淨空區
    case fireZone         // 火災區
    case chemicalHazard   // 化學危害區
    
    public var displayName: String {
        switch self {
        case .collapsedArea: return "倒塌區"
        case .searchArea: return "搜救區"
        case .subzone: return "子區域"
        case .hazardousZone: return "危險區"
        case .cleanedArea: return "已淨空區"
        case .fireZone: return "火災區"
        case .chemicalHazard: return "化學危害區"
        }
    }
    
    public var systemColor: String {
        switch self {
        case .collapsedArea: return "#FF0000"      // 紅色
        case .searchArea: return "#FFFF00"         // 黃色
        case .subzone: return "#0000FF"            // 藍色
        case .hazardousZone: return "#FF0000"      // 紅色
        case .cleanedArea: return "#00FF00"        // 綠色
        case .fireZone: return "#FF8800"           // 橙色
        case .chemicalHazard: return "#00FF00"     // 綠色
        }
    }
}

// MARK: - ICS Section System (Map Geography)
/// ICS 分區系統（支持 A/B/C 主區 + D1/D2 子區）- 用於地圖上的地理分區
public enum ICSMapArea: String, Codable, CaseIterable, Sendable {
    case sectionA
    case sectionB
    case sectionC
    case sectionD1
    case sectionD2
    case sectionD3
    
    public var displayName: String {
        switch self {
        case .sectionA: return "A區"
        case .sectionB: return "B區"
        case .sectionC: return "C區"
        case .sectionD1: return "D1區"
        case .sectionD2: return "D2區"
        case .sectionD3: return "D3區"
        }
    }
    
    public var systemColor: String {
        switch self {
        case .sectionA: return "#FF0000"        // 紅色
        case .sectionB: return "#0000FF"        // 藍色
        case .sectionC: return "#FFFF00"        // 黃色
        case .sectionD1, .sectionD2, .sectionD3: return "#00FF00" // 綠色
        }
    }
    
    public var parentSection: ICSMapArea? {
        switch self {
        case .sectionD1, .sectionD2, .sectionD3: return nil
        default: return nil
        }
    }
    
    public var subsections: [ICSMapArea] {
        switch self {
        case .sectionA: return [.sectionD1, .sectionD2, .sectionD3]
        case .sectionB: return [.sectionD1, .sectionD2, .sectionD3]
        case .sectionC: return [.sectionD1, .sectionD2, .sectionD3]
        case .sectionD1, .sectionD2, .sectionD3: return []
        }
    }
}

// MARK: - Search State System (6 states)
/// 搜救狀態圖層（6 種搜救進度狀態）
public enum SearchState: String, Codable, CaseIterable, Sendable {
    case unconfirmed  // 未確認
    case searching    // 搜救中
    case cleared      // 已淨空
    case highRisk     // 高危險
    case forbidden    // 禁止進入
    case secondSearch // 二次搜索
    
    public var displayName: String {
        switch self {
        case .unconfirmed: return "未確認"
        case .searching: return "搜救中"
        case .cleared: return "已淨空"
        case .highRisk: return "高危險"
        case .forbidden: return "禁止進入"
        case .secondSearch: return "二次搜索"
        }
    }
    
    public var systemColor: String {
        switch self {
        case .unconfirmed: return "#808080"    // 灰色
        case .searching: return "#FFFF00"      // 黃色
        case .cleared: return "#00FF00"        // 綠色
        case .highRisk: return "#FF0000"       // 紅色
        case .forbidden: return "#000000"      // 黑色
        case .secondSearch: return "#0000FF"   // 藍色
        }
    }
}

// MARK: - Map Markup Feature
/// 地圖標記特徵（點/線/面統一結構）
public struct MapMarkupFeature: Codable, Hashable, Sendable {
    public enum MarkupGeometry: Codable, Hashable, Sendable {
        case point(MapPointType, Double, Double) // 類型, 緯度, 經度
        case line(MapLineType, [MapCoordinate])   // 類型, 座標序列
        case polygon(MapPolygonType, [MapCoordinate]) // 類型, 座標序列
        
        var displayName: String {
            switch self {
            case .point(let type, _, _): return type.displayName
            case .line(let type, _): return type.displayName
            case .polygon(let type, _): return type.displayName
            }
        }
    }
    
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var sectionID: ICSMapArea
    public var geometry: MarkupGeometry
    public var searchState: SearchState
    public var title: String
    public var notes: String
    public var createdBy: LinkGuardID
    public var createdAt: Date
    public var updatedAt: Date
    public var attachmentIDs: [LinkGuardID]
    
    public init(
        id: LinkGuardID = .generated(prefix: "MAP"),
        incidentID: LinkGuardID,
        sectionID: ICSMapArea = .sectionA,
        geometry: MarkupGeometry,
        searchState: SearchState = .unconfirmed,
        title: String,
        notes: String = "",
        createdBy: LinkGuardID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        attachmentIDs: [LinkGuardID] = []
    ) {
        self.id = id
        self.incidentID = incidentID
        self.sectionID = sectionID
        self.geometry = geometry
        self.searchState = searchState
        self.title = title
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachmentIDs = attachmentIDs
    }
}

// MARK: - Map Coordinate
/// 地圖座標結構
public struct MapCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var accuracy: Double?
    
    public init(latitude: Double, longitude: Double, altitude: Double? = nil, accuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.accuracy = accuracy
    }
}

// MARK: - ICS Geometry (Section Area)
/// ICS 分區幾何定義
public struct ICSGeometry: Codable, Hashable, Sendable {
    public var section: ICSMapArea
    public var boundaries: [MapCoordinate]
    public var assignedTeamLeadID: LinkGuardID?
    public var searchState: SearchState
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        section: ICSMapArea,
        boundaries: [MapCoordinate],
        assignedTeamLeadID: LinkGuardID? = nil,
        searchState: SearchState = .unconfirmed,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.section = section
        self.boundaries = boundaries
        self.assignedTeamLeadID = assignedTeamLeadID
        self.searchState = searchState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Personnel Safety Tracking
/// 人員安全追蹤
public struct PersonnelSafetyMarker: Codable, Hashable, Sendable {
    public enum TrackingStatus: String, Codable, Sendable {
        case active        // 活躍/即時定位
        case lastKnown     // 最後位置
        case lostContact   // 失聯
        case sos           // SOS 已觸發
        case offline       // 離線（本地 GPS）
    }
    
    public var memberID: LinkGuardID
    public var currentLocation: MapCoordinate
    public var status: TrackingStatus
    public var lastUpdate: Date
    public var deviceBattery: Double? // 百分比
    public var inDangerZone: Bool
    public var sosTriggered: Bool
    
    public init(
        memberID: LinkGuardID,
        currentLocation: MapCoordinate,
        status: TrackingStatus = .active,
        lastUpdate: Date = Date(),
        deviceBattery: Double? = nil,
        inDangerZone: Bool = false,
        sosTriggered: Bool = false
    ) {
        self.memberID = memberID
        self.currentLocation = currentLocation
        self.status = status
        self.lastUpdate = lastUpdate
        self.deviceBattery = deviceBattery
        self.inDangerZone = inDangerZone
        self.sosTriggered = sosTriggered
    }
}

// MARK: - Photo Integration
/// 照片地點標記
public struct GeotaggedPhoto: Codable, Hashable, Sendable {
    public var photoID: LinkGuardID
    public var incidentID: LinkGuardID
    public var location: MapCoordinate
    public var timestamp: Date
    public var takenBy: LinkGuardID
    public var section: ICSMapArea
    public var structuralAnalysisResults: String? // AI 倒塌分析結果
    public var hazardFlags: [String]              // 危險標示
    
    public init(
        photoID: LinkGuardID = .generated(prefix: "PHOTO"),
        incidentID: LinkGuardID,
        location: MapCoordinate,
        timestamp: Date = Date(),
        takenBy: LinkGuardID,
        section: ICSMapArea = .sectionA,
        structuralAnalysisResults: String? = nil,
        hazardFlags: [String] = []
    ) {
        self.photoID = photoID
        self.incidentID = incidentID
        self.location = location
        self.timestamp = timestamp
        self.takenBy = takenBy
        self.section = section
        self.structuralAnalysisResults = structuralAnalysisResults
        self.hazardFlags = hazardFlags
    }
}

// MARK: - Offline Map Cache
/// 離線地圖快取邊界
public struct MapBounds: Codable, Hashable, Sendable {
    public var minLat: Double
    public var minLon: Double
    public var maxLat: Double
    public var maxLon: Double
    
    public init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }
}

/// 離線地圖快取管理
public struct OfflineMapCache: Codable, Sendable {
    public var tileRegionID: String
    public var bounds: MapBounds
    public var minZoom: UInt8
    public var maxZoom: UInt8
    public var downloadedAt: Date
    public var lastAccessedAt: Date
    public var cacheSize: Int64 // 位元組
    public var isSynced: Bool

    public var zoomLevels: ClosedRange<UInt8> {
        minZoom...maxZoom
    }
    
    public init(
        tileRegionID: String,
        bounds: MapBounds,
        minZoom: UInt8 = 0,
        maxZoom: UInt8 = 18,
        downloadedAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        cacheSize: Int64 = 0,
        isSynced: Bool = true
    ) {
        self.tileRegionID = tileRegionID
        self.bounds = bounds
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.downloadedAt = downloadedAt
        self.lastAccessedAt = lastAccessedAt
        self.cacheSize = cacheSize
        self.isSynced = isSynced
    }

    public init(
        tileRegionID: String,
        bounds: (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double),
        zoomLevels: ClosedRange<UInt8> = 0...18,
        downloadedAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        cacheSize: Int64 = 0,
        isSynced: Bool = true
    ) {
        self.init(
            tileRegionID: tileRegionID,
            bounds: MapBounds(minLat: bounds.minLat, minLon: bounds.minLon, maxLat: bounds.maxLat, maxLon: bounds.maxLon),
            minZoom: zoomLevels.lowerBound,
            maxZoom: zoomLevels.upperBound,
            downloadedAt: downloadedAt,
            lastAccessedAt: lastAccessedAt,
            cacheSize: cacheSize,
            isSynced: isSynced
        )
    }
}

// MARK: - Map System Core Functions Catalog
/// 地圖系統 12 項核心功能定義
public enum MapCoreFunction: String, Codable, CaseIterable, Sendable {
    case gpsPerson            // GPS 定位 - 顯示人員位置
    case sectionManagement    // 分區管理 - ABC 區/D1 子區
    case markupSystem         // 標記系統 - 點線面
    case searchState          // 搜救狀態 - 搜救中/淨空
    case hazardZone           // 危險區 - 結構危險標示
    case victimLocation       // 傷患定位 - 傷患位置
    case sosAlert             // SOS 定位 - SOS 警報
    case personTracking       // 人員追蹤 - 隊員位置
    case taskLayer            // 任務圖層 - 任務分布
    case photoIntegration     // 照片整合 - 照片 GPS 定位
    case offlineMap           // 離線地圖 - 無網路地圖
    case aiAnalysis           // AI 分析圖層 - AI 風險區
    
    public var displayName: String {
        switch self {
        case .gpsPerson: return "GPS 定位"
        case .sectionManagement: return "分區管理"
        case .markupSystem: return "標記系統"
        case .searchState: return "搜救狀態"
        case .hazardZone: return "危險區"
        case .victimLocation: return "傷患定位"
        case .sosAlert: return "SOS 定位"
        case .personTracking: return "人員追蹤"
        case .taskLayer: return "任務圖層"
        case .photoIntegration: return "照片整合"
        case .offlineMap: return "離線地圖"
        case .aiAnalysis: return "AI 分析圖層"
        }
    }
    
    public var purpose: String {
        switch self {
        case .gpsPerson: return "顯示人員位置"
        case .sectionManagement: return "搜救責任區"
        case .markupSystem: return "災情標記"
        case .searchState: return "搜索進度"
        case .hazardZone: return "安全管制"
        case .victimLocation: return "醫療派遣"
        case .sosAlert: return "緊急救援"
        case .personTracking: return "人員安全"
        case .taskLayer: return "指揮調度"
        case .photoIntegration: return "現場紀錄"
        case .offlineMap: return "災後運作"
        case .aiAnalysis: return "決策輔助"
        }
    }
}

// MARK: - Map System Design Principles
/// 地圖系統設計原則（可靠性指南）
public struct MapSystemDesignPrinciples: Sendable {
    public static let requiredFeatures: [String] = [
        "大按鈕",          // 戴手套操作
        "少層級",          // 快速操作
        "常用固定",        // 減少搜尋
        "自動儲存",        // 防止遺失
        "一鍵SOS",         // 緊急救命
        "色彩統一",        // 直覺判讀
        "離線優先",        // 災後可靠
        "地圖快取",        // 加速載入
        "黑夜模式",        // 夜間搜救
        "語音操作"         // 雙手忙碌
    ]
    
    public static let recommendedTechStack: [String: String] = [
        "地圖引擎": "Mapbox",
        "離線地圖": "MBTiles",
        "GPS": "CoreLocation",
        "即時同步": "WebSocket",
        "離線資料庫": "SQLite",
        "LoRa同步": "MQTT",
        "AI分析": "本地AI + 雲端",
        "照片定位": "EXIF GPS"
    ]
    
    public static let pageHierarchy: [String] = [
        "1. 地圖",
        "2. 人員總覽",
        "3. 資源管理",
        "4. 通訊"
    ]
}

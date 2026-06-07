import Foundation

/// Product surface for the v0.3 Mac command consoles (LinkGuard-UCC / LinkGuard-SCC).
///
/// This catalog is the authoritative mapping of the LinkGuard-E development-phase
/// specification onto concrete, role-aware console modules. It is intentionally
/// additive to `UCCPhaseCatalog` / `SCCPhaseCatalog` (which remain the engineering
/// contract): this layer is what the operator actually navigates, and every module
/// carries the `LinkGuardFeature` that decides its access level (● / ○ / ✕) via
/// `LinkGuardFeatureAccessMatrix`.
public enum CommandConsoleModuleKind: String, Codable, Hashable, Sendable, CaseIterable {
    // Shared between UCC and SCC
    case radioMonitoring
    case eventLog
    case deviceSync
    case aarReplay

    // UCC (Unified Command Center) – cross-region strategic command
    case identityAccess
    case globalDashboard
    case multiDisasterMap
    case icsArchitecture
    case globalSOS
    case casualtyStatistics
    case aiStrategy
    case heatmap
    case resourceManagement
    case emtDispatch
    case heavyTeamDispatch
    case uavManagement
    case pwsIntegration
    case emicIntegration
    case multiSCCMonitor
    case aiRiskPrediction

    // SCC (Site Command Center) – on-site tactical command
    case fieldSituationMap
    case mapMarkup
    case sectorManagement
    case subSectorManagement
    case searchStatusLayer
    case hazardZoneManagement
    case personnelTracking
    case fieldSOS
    case taskDispatch
    case personnelAssignment
    case teamCapability
    case patientManagement
    case startTriage
    case photoWall
    case temporaryBase
    case accessControl
    case aiDecisionSupport
    case loraIntegration
    case offlineMode
}

/// A single navigable module in a command console, derived from a development phase.
public struct CommandConsoleModule: Identifiable, Hashable, Sendable {
    public var appID: LinkGuardAppID
    public var phaseNumber: Int
    public var title: String          // 模組名稱
    public var capability: String     // 功能內容
    public var purpose: String        // 目的
    public var systemImageName: String
    public var section: ICSSection
    public var primaryFeature: LinkGuardFeature
    public var kind: CommandConsoleModuleKind

    public init(
        appID: LinkGuardAppID,
        phaseNumber: Int,
        title: String,
        capability: String,
        purpose: String,
        systemImageName: String,
        section: ICSSection,
        primaryFeature: LinkGuardFeature,
        kind: CommandConsoleModuleKind
    ) {
        self.appID = appID
        self.phaseNumber = phaseNumber
        self.title = title
        self.capability = capability
        self.purpose = purpose
        self.systemImageName = systemImageName
        self.section = section
        self.primaryFeature = primaryFeature
        self.kind = kind
    }

    public var id: String { "\(appID.rawValue)-\(phaseNumber)" }

    public var phaseLabel: String {
        let prefix = (appID == .ucc) ? "UCC" : "SCC"
        return "\(prefix) Phase \(phaseNumber)"
    }

    /// Access level for this module under the owning console role (● primary / ○ limited / ✕ none).
    public var accessLevel: FeatureAccessLevel {
        LinkGuardFeatureAccessMatrix.accessLevel(for: appID, feature: primaryFeature)
    }

    public var isAvailable: Bool { accessLevel.isAvailable }
}

public enum CommandConsoleCatalog {
    /// LinkGuard-UCC – 聯合指揮中心：v0.2-compatible command surface without international coordination modules.
    public static let uccModules: [CommandConsoleModule] = [
        .init(appID: .ucc, phaseNumber: 1, title: "基礎登入系統", capability: "帳號、權限、角色管理", purpose: "建立系統基礎",
              systemImageName: "person.badge.key.fill", section: .command, primaryFeature: .accountIdentity, kind: .identityAccess),
        .init(appID: .ucc, phaseNumber: 2, title: "全區戰情儀表板", capability: "全縣市災情總覽", purpose: "建立戰情中心",
              systemImageName: "square.grid.3x3.fill", section: .command, primaryFeature: .globalStatisticsDashboard, kind: .globalDashboard),
        .init(appID: .ucc, phaseNumber: 3, title: "多災區地圖", capability: "多 SCC 顯示", purpose: "跨區管理",
              systemImageName: "map.fill", section: .operations, primaryFeature: .multiDisasterSwitch, kind: .multiDisasterMap),
        .init(appID: .ucc, phaseNumber: 4, title: "ICS 指揮架構", capability: "UCC/SCC/TL 權限管理", purpose: "指揮層級建立",
              systemImageName: "point.3.connected.trianglepath.dotted", section: .command, primaryFeature: .commandAuthoritySwitch, kind: .icsArchitecture),
        .init(appID: .ucc, phaseNumber: 5, title: "全區 SOS 總覽", capability: "所有 SOS 事件統整", purpose: "緊急事件掌握",
              systemImageName: "sos.circle.fill", section: .command, primaryFeature: .sosDetail, kind: .globalSOS),
        .init(appID: .ucc, phaseNumber: 6, title: "全區傷患統計", capability: "傷患總數與狀態", purpose: "醫療資源分析",
              systemImageName: "cross.case.fill", section: .medical, primaryFeature: .medicalOperationalSummary, kind: .casualtyStatistics),
        .init(appID: .ucc, phaseNumber: 7, title: "AI 戰略分析", capability: "AI 資源調度建議", purpose: "降低指揮負荷",
              systemImageName: "brain.head.profile", section: .planning, primaryFeature: .aiStrategicAnalysis, kind: .aiStrategy),
        .init(appID: .ucc, phaseNumber: 8, title: "資源管理", capability: "人力與物資調度", purpose: "後勤管理",
              systemImageName: "shippingbox.fill", section: .logistics, primaryFeature: .resourceManagement, kind: .resourceManagement),
        .init(appID: .ucc, phaseNumber: 9, title: "PWS 整合", capability: "地震警報整合", purpose: "提前應變",
              systemImageName: "antenna.radiowaves.left.and.right.circle.fill", section: .command, primaryFeature: .pwsIntegration, kind: .pwsIntegration),
        .init(appID: .ucc, phaseNumber: 10, title: "事件日誌", capability: "全區事件記錄", purpose: "AAR 檢討",
              systemImageName: "clock.arrow.circlepath", section: .afterActionReview, primaryFeature: .eventLog, kind: .eventLog),
        .init(appID: .ucc, phaseNumber: 11, title: "電台監聽", capability: "PTT 轉錄與監控", purpose: "通訊管理",
              systemImageName: "antenna.radiowaves.left.and.right", section: .command, primaryFeature: .radioMonitoring, kind: .radioMonitoring),
        .init(appID: .ucc, phaseNumber: 12, title: "多裝置同步", capability: "Mac/iPad 同步", purpose: "指揮協同",
              systemImageName: "rectangle.connected.to.line.below", section: .logistics, primaryFeature: .commandCenterRedundancy, kind: .deviceSync)
    ]

    /// LinkGuard-SCC – 現場指揮中心：災區現場戰術指揮平台 (22 phases).
    public static let sccModules: [CommandConsoleModule] = [
        .init(appID: .scc, phaseNumber: 1, title: "現場戰情地圖", capability: "災區即時地圖", purpose: "現場指揮核心",
              systemImageName: "map.fill", section: .operations, primaryFeature: .fieldSituationDashboard, kind: .fieldSituationMap),
        .init(appID: .scc, phaseNumber: 2, title: "點線面系統", capability: "地圖標記", purpose: "災區視覺化",
              systemImageName: "pencil.and.outline", section: .operations, primaryFeature: .pointMarker, kind: .mapMarkup),
        .init(appID: .scc, phaseNumber: 3, title: "分區建立", capability: "A/B/C 區", purpose: "ICS 管理",
              systemImageName: "square.split.2x2.fill", section: .operations, primaryFeature: .sectorCreation, kind: .sectorManagement),
        .init(appID: .scc, phaseNumber: 4, title: "子區建立", capability: "D1/D2 細分", purpose: "大型災害管理",
              systemImageName: "square.split.1x2.fill", section: .operations, primaryFeature: .subSectorCreation, kind: .subSectorManagement),
        .init(appID: .scc, phaseNumber: 5, title: "搜救狀態圖層", capability: "搜救中／淨空", purpose: "搜索管理",
              systemImageName: "circle.grid.cross.fill", section: .operations, primaryFeature: .searchProgressColoring, kind: .searchStatusLayer),
        .init(appID: .scc, phaseNumber: 6, title: "危險區管理", capability: "危險與禁區標記", purpose: "人員安全",
              systemImageName: "exclamationmark.octagon.fill", section: .operations, primaryFeature: .hazardZoneManagement, kind: .hazardZoneManagement),
        .init(appID: .scc, phaseNumber: 7, title: "GPS 人員定位", capability: "即時定位", purpose: "搜救掌握",
              systemImageName: "location.fill.viewfinder", section: .operations, primaryFeature: .teamMemberRealtimeLocation, kind: .personnelTracking),
        .init(appID: .scc, phaseNumber: 8, title: "SOS 管理", capability: "SOS 優先處理", purpose: "緊急救援",
              systemImageName: "sos.circle.fill", section: .command, primaryFeature: .sosDetail, kind: .fieldSOS),
        .init(appID: .scc, phaseNumber: 9, title: "任務派遣", capability: "指派隊伍", purpose: "戰術調度",
              systemImageName: "arrow.triangle.branch", section: .operations, primaryFeature: .taskAssignment, kind: .taskDispatch),
        .init(appID: .scc, phaseNumber: 10, title: "人員配置", capability: "搜救隊管理", purpose: "資源配置",
              systemImageName: "person.3.sequence.fill", section: .operations, primaryFeature: .personnelOverview, kind: .personnelAssignment),
        .init(appID: .scc, phaseNumber: 11, title: "隊伍能力表", capability: "各隊專長資訊", purpose: "派遣最佳化",
              systemImageName: "list.bullet.clipboard.fill", section: .logistics, primaryFeature: .teamCapabilityOverview, kind: .teamCapability),
        .init(appID: .scc, phaseNumber: 12, title: "傷患管理", capability: "傷患統整", purpose: "醫療協調",
              systemImageName: "cross.case.fill", section: .medical, primaryFeature: .patientLocation, kind: .patientManagement),
        .init(appID: .scc, phaseNumber: 13, title: "START 檢傷", capability: "初步檢傷分類", purpose: "傷患排序",
              systemImageName: "staroflife.fill", section: .medical, primaryFeature: .startTriage, kind: .startTriage),
        .init(appID: .scc, phaseNumber: 14, title: "照片牆", capability: "照片 GPS 整合", purpose: "現場紀錄",
              systemImageName: "photo.on.rectangle.angled", section: .operations, primaryFeature: .photoWall, kind: .photoWall),
        .init(appID: .scc, phaseNumber: 15, title: "臨時據點", capability: "指揮所與集結點", purpose: "現場部署",
              systemImageName: "tent.fill", section: .logistics, primaryFeature: .temporaryBaseSetup, kind: .temporaryBase),
        .init(appID: .scc, phaseNumber: 16, title: "安全管制", capability: "進出紀錄", purpose: "搜救安全",
              systemImageName: "shield.lefthalf.filled", section: .command, primaryFeature: .safetyControlBoard, kind: .accessControl),
        .init(appID: .scc, phaseNumber: 17, title: "電台監聽", capability: "PTT 轉錄", purpose: "通訊備援",
              systemImageName: "antenna.radiowaves.left.and.right", section: .command, primaryFeature: .radioMonitoring, kind: .radioMonitoring),
        .init(appID: .scc, phaseNumber: 18, title: "AI 決策輔助", capability: "AI 建議", purpose: "指揮輔助",
              systemImageName: "brain.head.profile", section: .planning, primaryFeature: .aiFieldRiskAnalysis, kind: .aiDecisionSupport),
        .init(appID: .scc, phaseNumber: 19, title: "LoRa 整合", capability: "自主通訊", purpose: "災後備援",
              systemImageName: "dot.radiowaves.up.forward", section: .logistics, primaryFeature: .loraRelayManagement, kind: .loraIntegration),
        .init(appID: .scc, phaseNumber: 20, title: "離線模式", capability: "離線地圖與資料", purpose: "斷網運作",
              systemImageName: "wifi.slash", section: .operations, primaryFeature: .offlineMap, kind: .offlineMode),
        .init(appID: .scc, phaseNumber: 21, title: "多裝置同步", capability: "iPad/Mac 同步", purpose: "現場協同",
              systemImageName: "rectangle.connected.to.line.below", section: .logistics, primaryFeature: .commandCenterRedundancy, kind: .deviceSync),
        .init(appID: .scc, phaseNumber: 22, title: "AAR 回放", capability: "災後檢討", purpose: "訓練用途",
              systemImageName: "play.rectangle.on.rectangle.fill", section: .afterActionReview, primaryFeature: .aarReplay, kind: .aarReplay)
    ]

    public static func modules(for appID: LinkGuardAppID) -> [CommandConsoleModule] {
        switch appID {
        case .ucc:
            return uccModules
        case .scc, .sccIPad:
            return sccModules
        case .teamLeader, .teamLeaderIPad, .teamMember, .emt, .emtIPad, .volunteer:
            return []
        }
    }

    /// Console positioning strings used in the shell header.
    public static func positioning(for appID: LinkGuardAppID) -> (title: String, role: String, summary: String)? {
        switch appID {
        case .ucc:
            return ("Lifeline-HQ", "聯合指揮中心",
                    "全區域戰略指揮平台：跨災區協調、資源調度、災情總覽與多 SCC 管理。")
        case .scc, .sccIPad:
            return ("LinkGuard-SCC", "現場指揮中心",
                    "災區現場戰術指揮平台：分區管理、搜救調度、人員安全與現場協同。")
        default:
            return nil
        }
    }
}

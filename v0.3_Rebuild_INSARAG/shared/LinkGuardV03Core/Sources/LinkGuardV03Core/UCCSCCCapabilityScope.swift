import Foundation

public enum CapabilityScopeSymbol: String, Codable, CaseIterable, Sendable {
    case primary = "●"
    case assisted = "○"
    case unavailable = "✕"

    public var accessLevel: FeatureAccessLevel {
        switch self {
        case .primary:
            return .primary
        case .assisted:
            return .limited
        case .unavailable:
            return .none
        }
    }
}

public struct UCCSCCCapabilityScope: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var ucc: CapabilityScopeSymbol
    public var scc: CapabilityScopeSymbol

    public init(id: String, title: String, ucc: CapabilityScopeSymbol, scc: CapabilityScopeSymbol) {
        self.id = id
        self.title = title
        self.ucc = ucc
        self.scc = scc
    }
}

public enum UCCSCCCapabilityMatrix {
    public static let scopes: [UCCSCCCapabilityScope] = [
        .init(id: "mapLevel", title: "地圖定位層級", ucc: .primary, scc: .primary),
        .init(id: "corePositioning", title: "核心定位", ucc: .primary, scc: .primary),
        .init(id: "mapPerspective", title: "地圖視角", ucc: .primary, scc: .primary),
        .init(id: "multiDisasterSwitch", title: "多災區切換", ucc: .primary, scc: .unavailable),
        .init(id: "globalHeatAnalysis", title: "全區熱區分析", ucc: .primary, scc: .unavailable),
        .init(id: "aiStrategicAnalysis", title: "AI戰略分析", ucc: .primary, scc: .assisted),
        .init(id: "aiFieldRiskAnalysis", title: "現場AI風險分析", ucc: .assisted, scc: .primary),
        .init(id: "abcSectorCreation", title: "分區建立（A/B/C）", ucc: .assisted, scc: .primary),
        .init(id: "subSectorCreation", title: "子區建立（D1/D2）", ucc: .unavailable, scc: .primary),
        .init(id: "pointMarker", title: "點標記", ucc: .assisted, scc: .primary),
        .init(id: "lineMarker", title: "線標記", ucc: .assisted, scc: .primary),
        .init(id: "polygonMarker", title: "面標記", ucc: .assisted, scc: .primary),
        .init(id: "searchAreaManagement", title: "搜救區管理", ucc: .unavailable, scc: .primary),
        .init(id: "searchProgress", title: "搜救進度管理", ucc: .assisted, scc: .primary),
        .init(id: "hazardZone", title: "危險區標記", ucc: .assisted, scc: .primary),
        .init(id: "forbiddenZone", title: "禁止進入區", ucc: .assisted, scc: .primary),
        .init(id: "searchRoute", title: "搜救動線管理", ucc: .unavailable, scc: .primary),
        .init(id: "evacuationRoute", title: "撤離路線管理", ucc: .unavailable, scc: .primary),
        .init(id: "soldierGPS", title: "單兵GPS定位", ucc: .assisted, scc: .primary),
        .init(id: "teRealtimeLocation", title: "TE即時位置", ucc: .unavailable, scc: .primary),
        .init(id: "tlRealtimeLocation", title: "TL即時位置", ucc: .assisted, scc: .primary),
        .init(id: "emtLocation", title: "EMT位置管理", ucc: .assisted, scc: .primary),
        .init(id: "sosRealtimeLocation", title: "SOS即時定位", ucc: .assisted, scc: .primary),
        .init(id: "casualtyLocation", title: "傷患位置管理", ucc: .assisted, scc: .primary),
        .init(id: "entryControl", title: "人員進出管制", ucc: .unavailable, scc: .primary),
        .init(id: "lastLocation", title: "人員最後定位", ucc: .unavailable, scc: .primary),
        .init(id: "missingAlert", title: "失聯警示", ucc: .unavailable, scc: .primary),
        .init(id: "teamCapability", title: "隊伍能力管理", ucc: .assisted, scc: .primary),
        .init(id: "taskAssignment", title: "任務分派", ucc: .assisted, scc: .primary),
        .init(id: "crossRegionDispatch", title: "跨區資源調度", ucc: .primary, scc: .assisted),
        .init(id: "heavyTeamDispatch", title: "重型隊調度", ucc: .primary, scc: .unavailable),
        .init(id: "emtCrossRegion", title: "EMT跨區派遣", ucc: .primary, scc: .assisted),
        .init(id: "droneDispatch", title: "空拍機調度", ucc: .primary, scc: .assisted),
        .init(id: "fieldPhoto", title: "現場即時照片", ucc: .unavailable, scc: .primary),
        .init(id: "pttMonitoring", title: "PTT電台監聽", ucc: .primary, scc: .primary),
        .init(id: "voiceTranscription", title: "語音轉錄", ucc: .primary, scc: .primary),
        .init(id: "eventLog", title: "事件日誌", ucc: .primary, scc: .primary),
        .init(id: "globalDashboard", title: "全區統計儀表板", ucc: .primary, scc: .unavailable),
        .init(id: "fieldDashboard", title: "現場戰情儀表板", ucc: .assisted, scc: .primary),
        .init(id: "pws", title: "PWS地震警報", ucc: .primary, scc: .assisted),
        .init(id: "emic", title: "EMIC整合", ucc: .primary, scc: .unavailable),
        .init(id: "loraRelay", title: "LoRa中繼管理", ucc: .assisted, scc: .primary),
        .init(id: "offlineMap", title: "離線地圖", ucc: .assisted, scc: .primary),
        .init(id: "offlineQueue", title: "離線暫存", ucc: .assisted, scc: .primary),
        .init(id: "multiDeviceSync", title: "多裝置同步", ucc: .primary, scc: .primary),
        .init(id: "highPressureMode", title: "高壓快速操作模式", ucc: .unavailable, scc: .primary),
        .init(id: "bigButtonMode", title: "大按鈕模式", ucc: .unavailable, scc: .primary),
        .init(id: "nightMode", title: "夜間模式", ucc: .assisted, scc: .primary),
        .init(id: "gloveMode", title: "手套操作模式", ucc: .unavailable, scc: .primary),
        .init(id: "voiceOperation", title: "語音操作", ucc: .assisted, scc: .primary),
        .init(id: "authorityControl", title: "指揮權限管理", ucc: .primary, scc: .assisted),
        .init(id: "multiSCCMonitoring", title: "多SCC監控", ucc: .primary, scc: .unavailable),
        .init(id: "sccStatusMonitoring", title: "SCC狀態監控", ucc: .primary, scc: .unavailable),
        .init(id: "fieldSafetyRealtime", title: "即時現場安全管理", ucc: .unavailable, scc: .primary),
        .init(id: "secondaryCollapseWarning", title: "二次崩塌警示", ucc: .assisted, scc: .primary),
        .init(id: "rescueCompletionStats", title: "搜救完成率統計", ucc: .primary, scc: .assisted),
        .init(id: "medicalCapacityAnalysis", title: "醫療量能分析", ucc: .primary, scc: .assisted),
        .init(id: "roadInterruptionAnalysis", title: "道路中斷分析", ucc: .primary, scc: .assisted),
        .init(id: "regionalWorkforceGap", title: "全區人力缺口分析", ucc: .primary, scc: .unavailable),
        .init(id: "fieldStaffShortage", title: "現場缺人警示", ucc: .assisted, scc: .primary)
    ]

    public static func scope(for id: String) -> UCCSCCCapabilityScope? {
        scopes.first(where: { $0.id == id })
    }

    public static func expectedScope(for feature: LinkGuardFeature, appID: LinkGuardAppID) -> CapabilityScopeSymbol? {
        let canonical = canonicalAppID(for: appID)
        guard let pair = featureScopeMap[feature] else { return nil }
        return canonical == .ucc ? pair.ucc : pair.scc
    }

    private static func canonicalAppID(for appID: LinkGuardAppID) -> LinkGuardAppID {
        switch appID {
        case .sccIPad:
            return .scc
        case .teamLeaderIPad, .emtIPad, .teamLeader, .teamMember, .emt, .volunteer:
            return .scc
        case .ucc, .scc:
            return appID
        }
    }

    private static let featureScopeMap: [LinkGuardFeature: (ucc: CapabilityScopeSymbol, scc: CapabilityScopeSymbol)] = [
        .globalMapOverview: (.primary, .assisted),
        .sectorCreation: (.assisted, .primary),
        .subSectorCreation: (.unavailable, .primary),
        .pointMarker: (.assisted, .primary),
        .lineMarker: (.assisted, .primary),
        .areaMarker: (.assisted, .primary),
        .searchProgressColoring: (.assisted, .primary),
        .hazardZoneManagement: (.assisted, .primary),
        .worksiteMarkerSystem: (.unavailable, .primary),
        .offlineMap: (.assisted, .primary),
        .offlineDraftQueue: (.assisted, .primary),
        .gpsTracking: (.assisted, .primary),
        .personnelEntryLog: (.unavailable, .primary),
        .teamCapabilityOverview: (.assisted, .primary),
        .taskAssignment: (.assisted, .primary),
        .patientLocation: (.assisted, .primary),
        .medicalEvacuation: (.primary, .assisted),
        .hospitalCapacityView: (.primary, .assisted),
        .communicationChannel: (.primary, .primary),
        .radioMonitoring: (.primary, .primary),
        .speechTranscription: (.primary, .primary),
        .voiceReport: (.primary, .primary),
        .photoReport: (.assisted, .primary),
        .sosSending: (.assisted, .primary),
        .sosDetail: (.assisted, .primary),
        .aiDecisionAnalysis: (.primary, .assisted),
        .aiPatientWarning: (.assisted, .primary),
        .commandAuthoritySwitch: (.primary, .assisted),
        .disasterStatistics: (.primary, .assisted),
        .resourceManagement: (.primary, .assisted),
        .pwsIntegration: (.primary, .assisted),
        .emicIntegration: (.primary, .unavailable),
        .commandCenterRedundancy: (.primary, .primary)
    ]
}
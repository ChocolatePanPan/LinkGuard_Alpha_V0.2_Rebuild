import Foundation

extension USAROperationalPhase {
    var displayText: String {
        switch self {
        case .preparedness: return "整備"
        case .mobilization: return "動員"
        case .operations: return "作業中"
        case .demobilization: return "撤收"
        case .afterAction: return "復盤"
        }
    }
}

extension UCCRole {
    var displayText: String {
        switch self {
        case .uccCommander: return "UCC 指揮官"
        case .uccOperations: return "UCC 作業"
        case .uccPlanning: return "UCC 計畫"
        case .uccResources: return "UCC 資源"
        case .uccMedical: return "UCC 醫療"
        case .uccSafety: return "UCC 安全"
        case .sectorCommander: return "分區指揮"
        case .sectorSafety: return "分區安全"
        case .sectorLogistics: return "分區後勤"
        case .worksiteManager: return "工作點管理"
        case .searchLead: return "搜索組長"
        case .rescueLead: return "救援組長"
        case .medicalLead: return "醫療組長"
        case .logisticsLead: return "後勤組長"
        case .squadLeader: return "小隊長"
        }
    }
}

extension WorksiteStatus {
    var displayText: String {
        switch self {
        case .unassigned: return "未指派"
        case .assigned: return "已指派"
        case .assessing: return "評估中"
        case .searching: return "搜索中"
        case .rescuing: return "救援中"
        case .paused: return "暫停"
        case .evacuated: return "已撤離"
        case .completed: return "已完成"
        }
    }
}

extension WorksitePriority {
    var displayText: String {
        switch self {
        case .immediate: return "立即"
        case .high: return "高"
        case .normal: return "一般"
        case .low: return "低"
        case .deferred: return "延後"
        }
    }
}

extension ASRLevel {
    var displayText: String { "ASR \(rawValue)" }
}

extension SquadTaskKind {
    var displayText: String {
        switch self {
        case .assess: return "評估"
        case .search: return "搜索"
        case .rescue: return "救援"
        case .medical: return "醫療"
        case .logistics: return "後勤"
        case .marking: return "標記"
        case .safety: return "安全"
        case .evacuation: return "撤離"
        }
    }
}

extension SquadTaskStatus {
    var displayText: String {
        switch self {
        case .pending: return "待確認"
        case .acknowledged: return "已確認"
        case .enRoute: return "前往中"
        case .arrived: return "已抵達"
        case .inProgress: return "進行中"
        case .paused: return "暫停"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        }
    }
}

extension SquadOperationalStatus {
    var displayText: String {
        switch self {
        case .standby: return "待命"
        case .enRoute: return "前往中"
        case .arrived: return "已抵達"
        case .assessing: return "評估中"
        case .searching: return "搜索中"
        case .rescuing: return "救援中"
        case .treating: return "處置中"
        case .requestingSupport: return "請求支援"
        case .paused: return "暫停"
        case .evacuating: return "撤離中"
        case .completed: return "已完成"
        }
    }
}

extension USARHazardSeverity {
    var displayText: String {
        switch self {
        case .monitor: return "監測"
        case .caution: return "注意"
        case .high: return "高危"
        case .critical: return "危急"
        }
    }
}

extension USARHazardType {
    var displayText: String {
        switch self {
        case .structuralInstability: return "結構不穩"
        case .fire: return "火災"
        case .gas: return "瓦斯"
        case .electrical: return "電力"
        case .flood: return "淹水"
        case .hazmat: return "危害物質"
        case .accessBlocked: return "通道阻塞"
        case .security: return "安全威脅"
        case .weather: return "天候"
        case .other: return "其他"
        }
    }
}

extension ResourceRequestStatus {
    var displayText: String {
        switch self {
        case .requested: return "已請求"
        case .approved: return "已核准"
        case .dispatched: return "已派送"
        case .fulfilled: return "已完成"
        case .denied: return "已拒絕"
        case .cancelled: return "已取消"
        }
    }
}

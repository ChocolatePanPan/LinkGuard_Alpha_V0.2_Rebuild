import Foundation
import SwiftUI

enum MWTheme {
    static let bg = Color(red: 0.035, green: 0.045, blue: 0.06)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.115)
    static let elevated = Color(red: 0.105, green: 0.12, blue: 0.15)
    static let green = Color(red: 0.35, green: 0.94, blue: 0.67)
    static let cyan = Color(red: 0.32, green: 0.78, blue: 0.98)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.28)
    static let red = Color(red: 1.0, green: 0.34, blue: 0.31)
    static let violet = Color(red: 0.64, green: 0.58, blue: 1.0)
    static let textOnColor = Color(red: 0.02, green: 0.028, blue: 0.035)
}

// 觸控最小尺寸（HIG: ≥44pt）
enum MWTouch {
    static let minH: CGFloat = 52    // 可點擊元素最小高度
    static let cardH: CGFloat = 88   // 主要卡片高度
}

enum MilkyWayRoute: String, CaseIterable, Identifiable, Hashable {
    case overview
    case incidents
    case teams
    case tasks
    case comms
    case resources
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "態勢總覽"
        case .incidents: "事件線"
        case .teams: "隊伍"
        case .tasks: "任務"
        case .comms: "通訊"
        case .resources: "資源"
        case .settings: "中樞設定"
        }
    }

    var icon: String {
        switch self {
        case .overview: "rectangle.3.group.fill"
        case .incidents: "timeline.selection"
        case .teams: "person.3.sequence.fill"
        case .tasks: "checklist.checked"
        case .comms: "antenna.radiowaves.left.and.right"
        case .resources: "shippingbox.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum MWSeverity: String, CaseIterable, Identifiable {
    case stable
    case watch
    case urgent
    case critical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stable: "穩定"
        case .watch: "觀察"
        case .urgent: "緊急"
        case .critical: "危急"
        }
    }

    var color: Color {
        switch self {
        case .stable: MWTheme.green
        case .watch: MWTheme.cyan
        case .urgent: MWTheme.amber
        case .critical: MWTheme.red
        }
    }
}

enum MWCommandPreset: CaseIterable, Identifiable {
    case evacuate
    case hold
    case report
    case medical

    var id: String { title }

    var title: String {
        switch self {
        case .evacuate: "全員撤離"
        case .hold: "原地待命"
        case .report: "回報狀態"
        case .medical: "醫療支援"
        }
    }

    var detail: String {
        switch self {
        case .evacuate: "所有隊伍移動至安全集結點"
        case .hold: "保持目前位置，等待下一步命令"
        case .report: "回報人員、傷患、風險與可用資源"
        case .medical: "醫療與搬運組前往高優先傷患位置"
        }
    }

    var icon: String {
        switch self {
        case .evacuate: "figure.run.circle.fill"
        case .hold: "pause.circle.fill"
        case .report: "doc.text.fill"
        case .medical: "cross.case.fill"
        }
    }

    var color: Color {
        switch self {
        case .evacuate: MWTheme.red
        case .hold: MWTheme.amber
        case .report: MWTheme.cyan
        case .medical: MWTheme.violet
        }
    }
}

struct MWMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let color: Color
}

struct MWIncident: Identifiable {
    let id = UUID()
    var title: String
    var location: String
    var severity: MWSeverity
    var note: String
    var updatedAt: Date
}

struct MWTeamUnit: Identifiable {
    let id = UUID()
    var name: String
    var role: String
    var zone: String
    var status: String
    var battery: Int
    var severity: MWSeverity
}

struct MWTaskItem: Identifiable {
    let id = UUID()
    var title: String
    var owner: String
    var due: String
    var progress: Double
    var severity: MWSeverity
}

struct MWLogEntry: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var time: Date
    var color: Color
}

struct MWResourceItem: Identifiable {
    let id = UUID()
    var name: String
    var amount: String
    var location: String
    var condition: MWSeverity
}

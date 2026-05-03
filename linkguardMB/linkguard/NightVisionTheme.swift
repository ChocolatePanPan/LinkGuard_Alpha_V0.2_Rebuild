import SwiftUI

/// 夜視儀（Night Vision）主題色彩系統
enum NV {
    // MARK: - 基礎色盤

    /// 主要螢光綠 — 標題、重要數值、線上狀態
    static let green       = Color(red: 0.20, green: 0.86, blue: 0.38)

    /// 中綠 — 一般文字、圖示、已連線
    static let greenMedium = Color(red: 0.13, green: 0.68, blue: 0.28)

    /// 暗綠 — 次要文字、標題（取代 .secondary）
    static let greenDim    = Color(red: 0.08, green: 0.44, blue: 0.20)

    /// 極暗綠 — 停用、離線（取代 .gray）
    static let greenFaint  = Color(red: 0.05, green: 0.26, blue: 0.13)

    /// 背景 — 夜視儀深綠黑，不使用極致黑
    static let bg          = Color(red: 0.012, green: 0.042, blue: 0.032)

    /// 卡片/表面背景
    static let surface     = Color(red: 0.035, green: 0.082, blue: 0.064)

    // MARK: - 語義色彩

    /// SOS / 危險 — 柔和紅
    static let danger      = Color(red: 0.82, green: 0.22, blue: 0.22)

    /// 警告 / 中等優先 — 柔和琥珀
    static let warning     = Color(red: 0.72, green: 0.58, blue: 0.12)

    /// 心率 — 暗紅，保留醫療語義
    static let heartRate   = Color(red: 0.72, green: 0.25, blue: 0.25)

    /// 資訊 — 柔和青綠
    static let info        = Color(red: 0.10, green: 0.68, blue: 0.55)

    /// 模擬模式 — 柔和紫
    static let simulation  = Color(red: 0.42, green: 0.12, blue: 0.65)

    /// 指揮中心命令 — 柔和藍
    static let command     = Color(red: 0.25, green: 0.40, blue: 0.72)

    /// 團隊 — 柔和青
    static let team        = Color(red: 0.10, green: 0.56, blue: 0.72)

    /// 增援 — 柔和橙
    static let reinforce   = Color(red: 0.82, green: 0.50, blue: 0.08)

    /// 色塊上的文字
    static let textOnColor = Color.white
}

import Foundation

public enum FieldOperationalPrincipleCategory: String, Codable, CaseIterable, Sendable {
    case reliability
    case offlineReadiness
    case speed
    case ergonomics
    case visibility
    case safety
    case commandFlow
}

public struct FieldOperationalPrinciple: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var priority: Int
    public var title: String
    public var category: FieldOperationalPrincipleCategory
    public var acceptanceRule: String

    public init(id: String, priority: Int, title: String, category: FieldOperationalPrincipleCategory, acceptanceRule: String) {
        self.id = id
        self.priority = priority
        self.title = title
        self.category = category
        self.acceptanceRule = acceptanceRule
    }
}

public enum FieldOperationalPrinciples {
    public static let primaryStatement = "第一優先不是 AI，而是不斷線、不當機、能離線，並讓現場隊員在三秒內用手套完成關鍵操作。"
    public static let maximumPrimaryActionSeconds = 3.0
    public static let minimumPrimaryButtonHitTargetPoints = 56.0
    public static let maximumCommandFlowSteps = 3
    public static let minimumNightContrastRatio = 7.0

    public static let firefighterInterview2026: [FieldOperationalPrinciple] = [
        FieldOperationalPrinciple(
            id: "connection-continuity",
            priority: 1,
            title: "不斷線",
            category: .reliability,
            acceptanceRule: "通訊失敗時必須自動重連、排隊、回補，不讓使用者重填資料。"
        ),
        FieldOperationalPrinciple(
            id: "crash-resistance",
            priority: 2,
            title: "不當機",
            category: .reliability,
            acceptanceRule: "任何感測器、網路、AI、背景服務失敗都必須降級處理，不可讓主要回報流程崩潰。"
        ),
        FieldOperationalPrinciple(
            id: "offline-capable",
            priority: 3,
            title: "能離線",
            category: .offlineReadiness,
            acceptanceRule: "沒有網路時仍可查資料、填回報、送 SOS，恢復連線後自動同步。"
        ),
        FieldOperationalPrinciple(
            id: "three-second-action",
            priority: 4,
            title: "三秒內完成操作",
            category: .speed,
            acceptanceRule: "SOS、確認、回報、拍照送出等主要操作從入口到完成不得超過三秒或三步。"
        ),
        FieldOperationalPrinciple(
            id: "glove-safe",
            priority: 5,
            title: "戴手套可操作",
            category: .ergonomics,
            acceptanceRule: "主要控制必須能用消防手套點擊，避免細小文字連結與密集控件。"
        ),
        FieldOperationalPrinciple(
            id: "large-buttons",
            priority: 6,
            title: "大按鈕",
            category: .ergonomics,
            acceptanceRule: "主要按鈕觸控目標至少 56pt，危急操作採固定位置與清楚圖示。"
        ),
        FieldOperationalPrinciple(
            id: "night-contrast",
            priority: 7,
            title: "夜間高對比",
            category: .visibility,
            acceptanceRule: "夜間模式文字與重要狀態需達高對比，避免低亮度環境誤讀。"
        ),
        FieldOperationalPrinciple(
            id: "one-hand",
            priority: 8,
            title: "單手可操作",
            category: .ergonomics,
            acceptanceRule: "手機版主要流程應落在單手可及範圍，避免必須雙手縮放或精準拖拉。"
        ),
        FieldOperationalPrinciple(
            id: "low-false-touch",
            priority: 9,
            title: "誤觸率低",
            category: .safety,
            acceptanceRule: "破壞性與危急指令需有防誤觸設計，常用確認不可藏在相鄰小按鈕。"
        ),
        FieldOperationalPrinciple(
            id: "short-command-flow",
            priority: 10,
            title: "指令流程簡短",
            category: .commandFlow,
            acceptanceRule: "現場指令、確認、回報流程最多三步，避免長表單阻塞救援節奏。"
        )
    ]

    public static func principle(id: String) -> FieldOperationalPrinciple? {
        firefighterInterview2026.first { $0.id == id }
    }

    public static func primaryActionFitsTimeBudget(seconds: Double) -> Bool {
        seconds <= maximumPrimaryActionSeconds
    }

    public static func primaryButtonFitsGloveUse(hitTargetPoints: Double) -> Bool {
        hitTargetPoints >= minimumPrimaryButtonHitTargetPoints
    }

    public static func commandFlowFitsFieldUse(stepCount: Int) -> Bool {
        stepCount <= maximumCommandFlowSteps
    }

    public static func contrastFitsNightUse(ratio: Double) -> Bool {
        ratio >= minimumNightContrastRatio
    }
}
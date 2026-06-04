import Combine
import Foundation

public enum FieldAppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zhHant = "zh-Hant"
    case en = "en"

    public var id: String { rawValue }

    public var localeIdentifier: String {
        switch self {
        case .zhHant:
            return "zh-Hant"
        case .en:
            return "en"
        }
    }

    public var displayName: String {
        switch self {
        case .zhHant:
            return "繁體中文"
        case .en:
            return "English"
        }
    }

    public var shortLabel: String {
        switch self {
        case .zhHant:
            return "中"
        case .en:
            return "EN"
        }
    }
}

public final class FieldLocalization: ObservableObject {
    public static let shared = FieldLocalization()

    private static let storageKey = "linkguard.field.language"

    @Published public var language: FieldAppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    public var localeIdentifier: String { language.localeIdentifier }

    public init(defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: Self.storageKey),
           let savedLanguage = FieldAppLanguage(rawValue: rawValue) {
            self.language = savedLanguage
        } else if let preferred = Locale.preferredLanguages.first,
                  preferred.lowercased().hasPrefix("en") {
            self.language = .en
        } else {
            self.language = .zhHant
        }
    }

    public func text(_ key: String) -> String {
        switch language {
        case .zhHant:
            return Self.zhHant[key] ?? key
        case .en:
            return Self.en[key] ?? key
        }
    }

    public func choice(zh: String, en: String) -> String {
        language == .en ? en : zh
    }

    private static let zhHant: [String: String] = [
        "Accept": "接受",
        "Accept assigned task": "接受已派任務",
        "Active fire observed": "發現現場火勢",
        "App": "App",
        "App Settings": "App 設定",
        "App Language": "App 語言",
        "Area": "區域",
        "Attach patient evidence": "附加傷員證據",
        "Attach patient photo": "附加傷員照片",
        "Authority": "權限",
        "Bad Endpoint": "端點錯誤",
        "Blocked": "受阻",
        "Build": "建置號",
        "Cancel": "取消",
        "Capture and queue photo evidence": "拍照並加入回報佇列",
        "Channel": "通道",
        "Chat": "聊天",
        "Check In": "進入登記",
        "Check Out": "離開登記",
        "Clear": "清空",
        "Collapse": "坍塌",
        "Collapse report": "坍塌回報",
        "Command Preview": "指揮預覽",
        "Command voice update": "指揮語音更新",
        "Commit": "送出",
        "Comms": "通訊",
        "Confirm support task": "確認支援任務",
        "Create A1 worksite plan": "建立 A1 作業點計畫",
        "Create field patient record": "建立現場傷員紀錄",
        "Create sector/sub-sector/worksite": "建立區域/子區域/作業點",
        "Current GPS fix": "目前 GPS 定位",
        "Delivered": "已送達",
        "Device": "裝置",
        "Dispatch": "派遣",
        "EMT Field Support": "EMT 現場支援",
        "EMT patient status update": "EMT 傷員狀態更新",
        "EMT voice update": "EMT 語音更新",
        "Entry": "進入",
        "English": "English",
        "Error": "錯誤",
        "Event Log": "事件紀錄",
        "Evac": "後送",
        "Failed": "失敗",
        "Field Readiness": "現場就緒度",
        "Field Reports": "現場回報",
        "Field SOS": "現場 SOS",
        "Field marker": "現場標記",
        "Field point": "現場點位",
        "Field voice update": "現場語音更新",
        "Fill A/B/C/D team capability profile": "填寫 A/B/C/D 隊伍能力概況",
        "Fire": "火災",
        "Foreground location is available.": "前景定位可用。",
        "Foreground location not requested.": "尚未請求前景定位。",
        "GPS": "GPS",
        "GPS Blocked": "GPS 受阻",
        "GPS Fix Recorded": "已記錄 GPS 定位",
        "GPS Needed": "需要 GPS",
        "GPS Permission Needed": "需要 GPS 權限",
        "GPS Ready": "GPS 就緒",
        "GPS Updated": "GPS 已更新",
        "Git Tag": "Git 標籤",
        "Granted": "已授權",
        "Hazard area": "危險區域",
        "Hot Zone": "熱區",
        "Hospital": "醫院",
        "IDLE": "閒置",
        "In Progress": "進行中",
        "Language": "語言",
        "Last Sync": "上次同步",
        "Limited": "有限",
        "Line": "線段",
        "Local Queue": "本機佇列",
        "Locating": "定位中",
        "Location authorization is unavailable.": "定位授權不可用。",
        "Location authorization unavailable.": "定位授權不可用。",
        "Location permission denied.": "定位權限遭拒。",
        "Location permission disabled.": "定位權限已停用。",
        "Map": "地圖",
        "Map draft incomplete": "地圖草稿未完成",
        "Medical": "醫療",
        "Medical Flow": "醫療流程",
        "Memory": "記憶體",
        "Mission": "任務",
        "Mode": "模式",
        "No GPS": "無 GPS",
        "No GPS fix available": "尚無 GPS 定位",
        "No incoming items": "尚無收件項目",
        "No local audit events yet": "尚無本機稽核事件",
        "No local map markup": "尚無本機地圖標註",
        "No location fix returned.": "未取得定位結果。",
        "No personnel heartbeat": "尚無人員心跳",
        "No queued envelopes": "尚無待送封包",
        "No task assigned": "尚無任務",
        "Notes": "備註",
        "Offline Queue": "離線佇列",
        "Online": "在線",
        "Open Tasks": "開放任務",
        "Operations": "作業",
        "Ops": "作業",
        "Outbox Storage": "待送儲存",
        "OUTBOX": "待送",
        "Patient": "傷員",
        "Patient Actions": "傷員動作",
        "Patient Photo": "傷員照片",
        "Patient photo": "傷員照片",
        "Patient photo evidence": "傷員照片證據",
        "Patients": "傷員",
        "Personnel": "人員",
        "Photo": "照片",
        "Point": "點位",
        "Polyline route marker": "路線折線標記",
        "Preview message": "預覽訊息",
        "Preview sector plan": "預覽區域計畫",
        "Preview task dispatch": "預覽任務派遣",
        "Primary": "主要",
        "Priority Actions": "優先動作",
        "Publish active danger zone": "發布目前危險區",
        "Publish capacity update": "發布收治量能更新",
        "Publish hazard zone": "發布危害區",
        "Publish hot zone": "發布熱區",
        "Publish online personnel status": "發布人員在線狀態",
        "Push a voice status report": "送出語音狀態回報",
        "Queue": "佇列",
        "Queue audio/transcript report": "佇列音訊/逐字稿回報",
        "Queue group message": "佇列群組訊息",
        "Queue location + danger report": "佇列位置與危險回報",
        "Queue photo + GPS evidence": "佇列照片與 GPS 證據",
        "Queue settings persisted on this device.": "語言設定會儲存在此裝置。",
        "Queued": "已佇列",
        "Queued for sync": "等待同步",
        "Ready": "就緒",
        "Record START triage": "記錄 START 檢傷",
        "Record entering controlled zone": "記錄進入管制區",
        "Record entry control": "記錄進入管制",
        "Record leaving controlled zone": "記錄離開管制區",
        "Redo": "重做",
        "Refresh": "更新",
        "Refresh GPS": "更新 GPS",
        "Remaining": "剩餘",
        "Report active fire": "回報現場火勢",
        "Report photo evidence": "回報照片證據",
        "Report scene photo": "回報現場照片",
        "Report structural collapse": "回報結構坍塌",
        "Reports": "回報",
        "Request patient evacuation": "請求傷員後送",
        "Required": "必需",
        "Role Contract": "角色合約",
        "Route": "路線",
        "Runtime": "執行狀態",
        "SCC iPad Sector Control": "SCC iPad 區域管制",
        "SCC sector update": "SCC 區域更新",
        "SYNC": "同步",
        "Safety": "安全",
        "Safety Control": "安全管制",
        "Saved": "已儲存",
        "Saved Map": "地圖已保存",
        "Sector": "區域",
        "Select": "選取",
        "Send current field position": "送出目前現場位置",
        "Send EMT location": "送出 EMT 位置",
        "Send location heartbeat": "送出位置心跳",
        "Send medical message": "送出醫療訊息",
        "Send sector message": "送出區域訊息",
        "Send support location": "送出支援位置",
        "Send support message": "送出支援訊息",
        "Send team message": "送出隊伍訊息",
        "Series": "系列",
        "Settings": "設定",
        "Storage": "儲存",
        "Support task, photos, disaster report, and SOS": "支援任務、照片、災情與 SOS",
        "Switch identity": "切換身分",
        "Sync Endpoint": "同步端點",
        "Sync Error": "同步錯誤",
        "Sync Failed": "同步失敗",
        "Sync Idle": "同步閒置",
        "Sync Now": "立即同步",
        "Sync endpoint": "同步端點",
        "Synced": "已同步",
        "Syncing": "同步中",
        "TL Worksite Command": "TL 作業點指揮",
        "Task photo": "任務照片",
        "Tasks": "任務",
        "TE Task Execution": "TE 任務執行",
        "TE task progress update": "TE 任務進度更新",
        "Team Briefing": "隊伍簡報",
        "Team command": "隊伍指揮",
        "Tourniquet applied": "已使用止血帶",
        "Traditional Chinese": "繁體中文",
        "Unavailable": "不可用",
        "Undo": "復原",
        "Update task status": "更新任務狀態",
        "Update triage and vitals": "更新檢傷與生命徵象",
        "Updating GPS": "GPS 更新中",
        "USAR Profile": "USAR 概況",
        "Version": "版本",
        "Victim or marker point": "傷患或標記點",
        "Vitals": "生命徵象",
        "VO Support Loop": "VO 支援流程",
        "VO support update": "VO 支援更新",
        "Voice": "語音",
        "Workflow": "流程",
        "Working": "作業中",
        "Worksite": "作業點",
        "Worksite overview": "作業點概況",
        "choose_identity": "選擇啟動身分",
        "choose_iphone_identity": "選擇 iPhone 現場身份",
        "iphone_identity_subtitle": "同一個 App 可進入 TL / TE / EMT / VO",
        "language_current_detail": "切換後會立即套用到現場 App 的頁籤、面板與動作按鈕。",
        "language_current_title": "目前語言",
        "language_panel_title": "語言 / Language",
        "local_cache_unavailable": "本機快取不可用",
        "no worksite": "無作業點",
        "副分隊長": "副分隊長",
        "協助指揮與安全回報": "協助指揮與安全回報",
        "同一個 App 可進入 TL / TE / EMT / VO": "同一個 App 可進入 TL / TE / EMT / VO",
        "小隊指揮與任務派遣": "小隊指揮與任務派遣",
        "志工": "志工",
        "後勤志工": "後勤志工",
        "搜救員": "搜救員",
        "支援任務、照片、災情與 SOS": "支援任務、照片、災情與 SOS",
        "救護員": "救護員",
        "救護組長": "救護組長",
        "物資支援與位置回報": "物資支援與位置回報",
        "現場指揮": "現場指揮",
        "醫療分流與病患後送": "醫療分流與病患後送",
        "Clinical": "臨床",
        "Command Field Preview": "指揮現場預覽",
        "EMT / Triage Flow": "EMT / 檢傷流程",
        "Global Command": "全域指揮",
        "Global command": "全域指揮",
        "Incident command": "事故指揮",
        "Medical Triage": "醫療檢傷",
        "Missing": "缺少",
        "No command": "無指揮權",
        "None": "無",
        "Overview": "總覽",
        "Received": "收件",
        "SCC iPad / Sector Control": "SCC iPad / 區域管制",
        "Sector Command": "區域指揮",
        "Sector command": "區域指揮",
        "Self report": "自行回報",
        "Summary": "摘要",
        "TL iPad / Worksite Command": "TL iPad / 作業點指揮",
        "TL/TE 小隊作業": "TL/TE 小隊作業",
        "Task List": "任務列表",
        "VO / Support Reporting": "VO / 支援回報",
        "Volunteer Safety": "志工安全",
        "routine": "例行",
        "low": "低",
        "medium": "中",
        "high": "高",
        "critical": "危急",
        "shared core envelope preview": "共享核心封包預覽",
        "分區管理、人員總覽、安全管制": "分區管理、人員總覽、安全管制",
        "分區、Worksite、任務派遣與回報閉環": "分區、作業點、任務派遣與回報閉環",
        "小隊指揮、任務執行、GPS、照片、SOS 與狀態回報": "小隊指揮、任務執行、GPS、照片、SOS 與狀態回報",
        "GPS、SOS、照片、災情與語音回報": "GPS、SOS、照片、災情與語音回報"
    ]

    private static let en: [String: String] = [
        "choose_identity": "Choose launch identity",
        "choose_iphone_identity": "Choose iPhone field identity",
        "iphone_identity_subtitle": "Use one app as TL / TE / EMT / VO",
        "language_current_detail": "Changes apply immediately to field tabs, panels, and action buttons.",
        "language_current_title": "Current Language",
        "language_panel_title": "Language",
        "local_cache_unavailable": "Local cache unavailable",
        "no worksite": "no worksite",
        "副分隊長": "Deputy Team Leader",
        "協助指揮與安全回報": "Assist command and safety reporting",
        "同一個 App 可進入 TL / TE / EMT / VO": "Use one app as TL / TE / EMT / VO",
        "小隊指揮與任務派遣": "Team command and task dispatch",
        "志工": "Volunteer",
        "後勤志工": "Logistics Volunteer",
        "搜救員": "Search Rescuer",
        "支援任務、照片、災情與 SOS": "Support tasks, photos, disaster reports, and SOS",
        "救護員": "EMT",
        "救護組長": "Medical Lead",
        "物資支援與位置回報": "Supply support and location reporting",
        "現場指揮": "Field Command",
        "醫療分流與病患後送": "Medical triage and evacuation",
        "TL/TE 小隊作業": "TL/TE Team Operations",
        "分區管理、人員總覽、安全管制": "Sector management, personnel overview, and safety control",
        "分區、Worksite、任務派遣與回報閉環": "Sector, worksite, dispatch, and report loop",
        "小隊指揮、任務執行、GPS、照片、SOS 與狀態回報": "Team command, task execution, GPS, photos, SOS, and status reports",
        "GPS、SOS、照片、災情與語音回報": "GPS, SOS, photos, disaster, and voice reports"
    ]
}

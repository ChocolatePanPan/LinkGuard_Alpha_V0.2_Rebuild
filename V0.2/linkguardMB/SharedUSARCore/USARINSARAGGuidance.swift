import Foundation

// MARK: - INSARAG Role Guidance

struct INSARAGGuidanceItem: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String

    init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

struct INSARAGRoleBrief: Identifiable, Equatable {
    var id: String { profile.rawValue }
    var profile: INSARAGRoleProfile
    var title: String
    var subtitle: String
    var cycle: String
    var checklist: [INSARAGGuidanceItem]
}

enum INSARAGRoleProfile: String, CaseIterable, Identifiable {
    case ucc
    case sector
    case worksite
    case squadLeader

    var id: String { rawValue }

    var brief: INSARAGRoleBrief {
        switch self {
        case .ucc:
            return INSARAGRoleBrief(
                profile: self,
                title: "INSARAG UCC 作業節奏",
                subtitle: "協調、計畫、作業、資源、安全與資訊管理保持同一循環。",
                cycle: "建立事件目標 -> 分區/工作點優先序 -> 派令與資源 -> SITREP/ASR 回收 -> 調整下一輪作業",
                checklist: [
                    .init(id: "ucc-objectives", title: "事件目標", detail: "維持清楚事件目標、作業期與優先序，不讓工作點自行漂移。"),
                    .init(id: "ucc-sector", title: "分區控制", detail: "每個 Sector/Worksite 需要明確 scope、負責角色與回報路徑。"),
                    .init(id: "ucc-asr", title: "ASR 驅動", detail: "ASR、危害、受困者與資源需求共同決定任務派遣。"),
                    .init(id: "ucc-safety", title: "安全監督", detail: "撤離、停止、危害升級與人員問責必須可追蹤。")
                ]
            )
        case .sector:
            return INSARAGRoleBrief(
                profile: self,
                title: "INSARAG Sector 控制",
                subtitle: "分區指揮負責邊界、通道、通訊、資源與工作點節奏。",
                cycle: "接收 UCC 目標 -> 排列工作點 -> 分派工作點/小隊 -> 收 SITREP -> 回報 UCC",
                checklist: [
                    .init(id: "sector-boundary", title: "邊界與通道", detail: "確認 Sector 邊界、進出路線、危害區與集合點。"),
                    .init(id: "sector-worksites", title: "工作點節奏", detail: "依 ASR、優先序與隊伍能力調整工作點狀態。"),
                    .init(id: "sector-resources", title: "資源請求", detail: "資源不足時向 UCC 提交明確數量、用途與優先級。"),
                    .init(id: "sector-sitrep", title: "SITREP", detail: "用狀態、危害、後送與任務完成度組成分區回報。")
                ]
            )
        case .worksite:
            return INSARAGRoleBrief(
                profile: self,
                title: "INSARAG Worksite 管理",
                subtitle: "工作點管理聚焦 ASR、危害、RCM 標記、小隊任務與受困者資訊。",
                cycle: "建立工作點控制 -> ASR 評估 -> 標記/危害 -> 派小隊任務 -> 匯整回報",
                checklist: [
                    .init(id: "worksite-control", title: "控制點", detail: "確認工作點代號、位置、入口、危害與安全觀察點。"),
                    .init(id: "worksite-asr", title: "ASR 1-5", detail: "用 ASR 層級、構造、信心度與備註支撐優先序。"),
                    .init(id: "worksite-marking", title: "RCM/標記", detail: "工作點、受困者位置、危害與路線標記需能回到 UCC。"),
                    .init(id: "worksite-tasking", title: "小隊派工", detail: "任務要包含工作點、任務類型、指示與預期回報。")
                ]
            )
        case .squadLeader:
            return INSARAGRoleBrief(
                profile: self,
                title: "INSARAG Squad Leader 回報",
                subtitle: "小隊長只做明確任務、即時狀態、危害、資源與醫療後送回報。",
                cycle: "確認任務 -> 到達/評估 -> 搜索/救援/醫療 -> 回報狀態 -> 撤離或完成",
                checklist: [
                    .init(id: "squad-ack", title: "任務確認", detail: "確認工作點、任務、進出路線與通訊方式。"),
                    .init(id: "squad-status", title: "狀態回報", detail: "抵達、評估、搜索、救援、暫停、撤離與完成都要回報。"),
                    .init(id: "squad-safety", title: "危害與資源", detail: "發現危害或能力不足時立即送出危害/資源請求。"),
                    .init(id: "squad-medical", title: "醫療後送", detail: "傷患 ID、檢傷代碼、交接點與狀態需在封包中留痕。")
                ]
            )
        }
    }
}

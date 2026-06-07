# LinkGuard-UCC

聯合指揮中心版本。

## 適用對象

- 消防局
- EOC
- 聯合應變中心

## 核心定位

「跨區域戰略指揮平台」。

- Command：決策、優先順序、重大警報、快速命令。
- Planning：災情分析、行動計畫、事件日誌。
- Logistics：跨區資源與通訊支援總覽。
- Finance：成本、採購、工時、耗材與任務紀錄總覽。

UCC 是最高協調與資料權威，但不是唯一操作中心。

UCC/SCC 權限分工以 `docs/architecture/role-feature-access/README.md` 的「UCC / SCC 正式基準」為唯一來源，shared core 對應 `UCCSCCCapabilityMatrix`。

## ICS 對照

| ICS 部門 | 中文說法 | 主要工作 | 對 LinkGuard-E 的對應 |
| --- | --- | --- | --- |
| Incident Commander | 事故指揮官 | 統一指揮、設定目標、核准行動計畫 | 消防指揮官／現場總指揮 |
| Command Staff | 指揮幕僚 | 安全、媒體、跨單位聯絡 | 系統管理、對外通報、安全提醒 |
| Operations Section | 作業組 | 執行現場搜救與戰術任務 | 搜救員終端、任務分派、受困者救援 |
| Planning Section | 計畫組 | 蒐集資料、判斷災情、建立行動計畫 | AI 分析、受困者排序、災情地圖 |
| Logistics Section | 後勤組 | 通訊、設備、補給、交通、醫療支援 | LoRa 節點、NFC 傷票、設備電量、通訊維護 |
| Finance/Admin Section | 財務／行政組 | 成本、採購、工時、文件紀錄 | 系統紀錄、任務歷程、災後報告 |

## Phase roadmap

| Phase | 功能模組 | 功能內容 | 開發目的 |
| --- | --- | --- | --- |
| UCC Phase 1 | 基礎登入系統 | 帳號、權限、角色管理 | 建立系統基礎 |
| UCC Phase 2 | 全區戰情儀表板 | 全縣市災情總覽 | 建立戰情中心 |
| UCC Phase 3 | 多災區地圖 | 多 SCC 顯示 | 跨區管理 |
| UCC Phase 4 | ICS 指揮架構 | UCC/SCC/TL 權限管理 | 指揮層級建立 |
| UCC Phase 5 | 全區 SOS 總覽 | 所有 SOS 事件統整 | 緊急事件掌握 |
| UCC Phase 6 | 全區傷患統計 | 傷患總數與狀態 | 醫療資源分析 |
| UCC Phase 7 | AI 戰略分析 | AI 資源調度建議 | 降低指揮負荷 |
| UCC Phase 8 | 資源管理 | 人力與物資調度 | 後勤管理 |
| UCC Phase 9 | PWS 整合 | 地震警報整合 | 提前應變 |
| UCC Phase 10 | 事件日誌 | 全區事件記錄 | AAR 檢討 |
| UCC Phase 11 | 電台監聽 | PTT 轉錄與監控 | 通訊管理 |
| UCC Phase 12 | 多裝置同步 | Mac/iPad 同步 | 指揮協同 |

`CommandConsoleCatalog.uccModules` 是此表的 shared core 來源。UCC Mac console 採 v0.2 相容功能面，v0.3 擴充模組不會出現在左側操作清單。

## UI 實作

UCC Mac app 使用 `LinkGuardV03MacUI` 的 `MacCommandConsoleView`。畫面狀態由 `MacSystemUIFactory.makeState(appID: .ucc, ...)` 產生，繼承 shared core 的權限、指揮層級、事件快照、離線佇列、傳輸拓撲與版本資訊。

目前 UCC 已導入第一版 ICS 架構模組：

- `MacUCCICSArchitecture` 定義 UCC 的 ICS lanes、指揮權限與邊界規則。
- `MacSystemUIState.uccICSArchitecture` 僅在 UCC 產生，SCC 不會套用。
- `MacCommandConsoleView` 透過 `ICSArchitectureModule` 呈現 UCC 的指揮架構與邊界規則。

詳細產品邊界見 `docs/architecture/ucc-ics/README.md`。

`LinkGuard-UCC.xcodeproj` 已包含 macOS SwiftUI app target，並透過本地 Swift package dependency 引用 `LinkGuardV03MacUI`。

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

## Phase roadmap

| Phase | 功能模組 | 功能內容 | 開發目的 |
| --- | --- | --- | --- |
| UCC Phase 1 | 全區儀表板 | 全災區監控 | 戰情中心 |
| UCC Phase 2 | ICS架構 | UCC/SCC/TL管理 | 指揮體系 |
| UCC Phase 3 | 跨區調度 | 區域派遣 | 資源協同 |
| UCC Phase 4 | AI分析 | AI決策建議 | 高階指揮 |
| UCC Phase 5 | 災情統計 | 搜救統計 | 決策依據 |
| UCC Phase 6 | 電台監聽 | PTT轉錄 | 通訊掌握 |
| UCC Phase 7 | 事件日誌 | AAR紀錄 | 災後檢討 |
| UCC Phase 8 | PWS整合 | 地震警報 | 提前應變 |
| UCC Phase 9 | EMIC整合 | 災情同步 | 政府協同 |
| UCC Phase 10 | 資源總控 | 人力物資管理 | 戰略配置 |
| UCC Phase 11 | 安全管制 | 危險區總覽 | 全區安全 |
| UCC Phase 12 | 多指揮中心 | 備援切換 | 容錯能力 |
| UCC Phase 13 | 國際協作 | INSARAG模式 | 國際接軌 |

`UCCPhaseCatalog` 是此表的 shared core 來源；Phase 1-5、7、10、11 已對應現有 shared core 權限、功能矩陣與 sync message 類型，Phase 6、8、9 標為外部整合待接，Phase 12、13 標為戰略產品規劃。

## UI 實作

UCC Mac app 使用 `LinkGuardV03MacUI` 的 `MacSystemShellView`。畫面狀態由 `MacSystemUIFactory.makeState(appID: .ucc, ...)` 產生，繼承 shared core 的權限、指揮層級、事件快照、離線佇列、傳輸拓撲與版本資訊。

`LinkGuard-UCC.xcodeproj` 已包含 macOS SwiftUI app target，並透過本地 Swift package dependency 引用 `LinkGuardV03MacUI`。

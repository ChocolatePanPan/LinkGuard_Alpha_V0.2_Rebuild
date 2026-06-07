# Mac Apps

Mac 端負責高層指揮、現場總指揮、跨區協調、資料彙整與復盤紀錄。

## 規劃版本

- `LinkGuard-UCC`：聯合指揮中心，跨區域戰略指揮平台。
- `LinkGuard-SCC`：現場總指揮中心。

`LinkGuard-UCC` 的 Mac console 由 shared core 的 `CommandConsoleCatalog.uccModules` 固定為 12 個 v0.2 相容模組：基礎登入、全區戰情、多災區地圖、ICS 指揮架構、全區 SOS、全區傷患統計、AI 戰略分析、資源管理、PWS、事件日誌、電台監聽與多裝置同步。

## UI 繼承方式

Mac 端 UI 使用 `LinkGuardV03MacUI`，並由 `MacSystemUIFactory` 從 shared core 產生畫面狀態。UCC 與 SCC 共用同一套 SwiftUI shell，但依各自的 `AppBlueprint`、`RoleProfile`、`OperationSnapshot`、`TransportTopology` 自動呈現不同權限、模組、快速操作與傳輸路由。

這讓 SCC 不會只是 UCC 鏡像，而是繼承共同實作後套用現場指揮中心自己的 scope。

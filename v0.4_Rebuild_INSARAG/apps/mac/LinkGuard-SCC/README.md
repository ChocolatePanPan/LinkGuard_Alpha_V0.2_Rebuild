# LinkGuard-SCC

現場總指揮版。

## 適用對象

- 現場總指揮官
- 大隊長
- 指揮官
- Sector Command Center

## 核心定位

- Operations 主控。
- 現場分區與子區域管理。
- 戰術地圖與離線圖資。
- 安全管制與現場資源調度。
- 向 UCC 回報彙整狀態。

SCC 是現場指揮中心，不能只是 UCC 的螢幕鏡像。

## UI 實作

SCC Mac app 使用 `LinkGuardV03MacUI` 的 `MacSystemShellView`。畫面狀態由 `MacSystemUIFactory.makeState(appID: .scc, ...)` 產生，會繼承 shared core 的 runtime、權限、傳輸與 snapshot，但保留 SCC 的現場指揮範圍，不顯示 UCC-only Finance 操作。

`LinkGuard-SCC.xcodeproj` 已包含 macOS SwiftUI app target，並透過本地 Swift package dependency 引用 `LinkGuardV03MacUI`。

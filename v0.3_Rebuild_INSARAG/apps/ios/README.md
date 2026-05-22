# iOS Apps

iOS 端採角色分流，避免一套 App 承載所有功能造成現場混亂。

## 規劃版本

- `LinkGuard-VO`：Volunteer。
- `LinkGuard-TE`：Team Member。
- `LinkGuard-TL`：Team Leader。
- `LinkGuard-EMT`：Medical。

## Buildable targets

每個 iOS project 目前都有 SwiftUI app target，引用 `LinkGuardV03FieldUI`。現場端已接上快速操作：GPS/狀態上傳、任務更新、照片回報、安全進出、群組訊息、語音回報、SOS 與地圖點/線/面標註。Map tab 支援本地 canvas、圖層顯示、undo/redo、draft commit 與離線 queue。`LinkGuard-TE` 另以 `TeamMemberPhaseCatalog` 固定搜救隊員版 12 phase 產品契約。

`LinkGuard-TL` 與 `LinkGuard-TE` 手機端已整合為同一套小隊作業 workflow：兩個 target 都顯示 TL/TE 啟動身分選項，並共用 `TeamMemberPhaseCatalog` 的 12 phase 任務執行流程；目前啟動身分只作為畫面標示，不限制功能。

# iOS Apps

v0.4 iOS 端新增單一 `LinkGuard-iPhone` 現場入口，同時保留原本角色分流 targets 供測試與過渡。

## 規劃版本

- `LinkGuard-VO`：Volunteer。
- `LinkGuard-TE`：Team Member。
- `LinkGuard-TL`：Team Leader。
- `LinkGuard-EMT`：Medical。
- `LinkGuard-iPhone`：Unified iPhone launcher。

## Buildable targets

每個 iOS project 目前都有 SwiftUI app target，引用 `LinkGuardV03FieldUI`。現場端已接上快速操作：GPS/狀態上傳、任務更新、照片回報、安全進出、群組訊息、語音回報、SOS 與地圖點/線/面標註。Map tab 支援本地 canvas、圖層顯示、undo/redo、draft commit 與離線 queue。`LinkGuard-TE` 另以 `TeamMemberPhaseCatalog` 固定搜救隊員版 12 phase 產品契約。

`LinkGuard-iPhone` 啟動時提供 TL-01、TL-02、TE-01、EMT-01、EMT-02、VO-01、VO-02 多身份選擇。選擇後會重建對應 `FieldAppController`，因此 EMT 會載入 medical flow，TE/VO 會載入任務、GPS、照片、SOS 與回報流程，TL 會載入小隊指揮與任務派遣流程。

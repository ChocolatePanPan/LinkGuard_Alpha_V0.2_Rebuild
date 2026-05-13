# iOS Apps

iOS 端採角色分流，避免一套 App 承載所有功能造成現場混亂。

## 規劃版本

- `LinkGuard-VO`：Volunteer。
- `LinkGuard-TE`：Team Member。
- `LinkGuard-TL`：Team Leader。
- `LinkGuard-EMT`：Medical。

## Buildable targets

每個 iOS project 目前都有 SwiftUI app target，引用 `LinkGuardV03FieldUI`。現場端已接上快速操作：GPS/狀態上傳、任務更新、照片回報、安全進出、群組訊息、語音回報與 SOS。`LinkGuard-TE` 另以 `TeamMemberPhaseCatalog` 固定搜救隊員版 12 phase 產品契約。

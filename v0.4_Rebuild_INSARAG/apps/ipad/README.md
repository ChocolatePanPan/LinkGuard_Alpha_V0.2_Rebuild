# iPad Apps

iPad 端用於需要大畫面、多欄資訊與地圖操作的版本。

## 優先版本

- `LinkGuard-SCC`
- `LinkGuard-TL`
- `LinkGuard-EMT`

## Buildable targets

每個 iPad project 目前都有 SwiftUI app target，引用 `LinkGuardV03FieldUI`。SCC/TL/EMT iPad 版共用 Phase 2 現場端操作流程，並保留各自 app id、bundle id 與權限 gate。Map tab 已接上大畫面 canvas、地圖點/線/面標註、圖層開關、undo/redo、draft commit 與離線 queue。

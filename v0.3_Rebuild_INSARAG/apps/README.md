# Apps

此資料夾規劃 LinkGuard v0.3 的角色分流版本。

目前 UCC/SCC macOS、Lifeline iPhone 與 iPad field apps 都有獨立 Xcode target。iPad 端透過 `LinkGuardV03FieldUI` 共用現場端操作流程；Lifeline iPhone 端直接讀取 shared core 的 `CommandConsoleCatalog.uccModules`，對齊 UCC 12 模組指揮面。

共享框架放在 `../shared/LinkGuardV03Core`。各 app project 引用這個 local Swift package。

## 原則

- 各版本使用共享核心，不直接複製程式碼。
- 各版本可有不同 display name、bundle id、icon、首頁與權限。
- Lifeline 是配合 `LinkGuard-UCC` v0.2-compatible catalog 的 iPhone companion；對應 HQ 外顯名稱為 `Lifeline-HQ`。
- EMT、TL、SCC 需要優先考慮 iPad 版操作。

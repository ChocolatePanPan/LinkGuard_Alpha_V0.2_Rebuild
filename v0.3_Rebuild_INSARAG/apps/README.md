# Apps

此資料夾規劃 LinkGuard v0.3 的角色分流版本。

目前 UCC/SCC macOS 與 iOS/iPad field apps 都有獨立 Xcode target。iOS/iPad 端透過 `LinkGuardV03FieldUI` 共用現場端操作流程，不直接複製業務邏輯。

共享框架放在 `../shared/LinkGuardV03Core`。各 app project 引用這個 local Swift package。

## 原則

- 各版本使用共享核心，不直接複製程式碼。
- 各版本可有不同 display name、bundle id、icon、首頁與權限。
- EMT、TL、SCC 需要優先考慮 iPad 版操作。

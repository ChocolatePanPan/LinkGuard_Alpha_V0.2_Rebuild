# Apps

此資料夾規劃 LinkGuard v0.3 的角色分流版本。

目前建立資料夾、README 與各版本獨立 Xcode project 殼，不建立 Xcode target 或 scheme。

共享框架已先放在 `../shared/LinkGuardV03Core`。後續建立 target 時，各 app 應引用這個 package。

## 原則

- 各版本未來應使用共享核心，不直接複製程式碼。
- 各版本可有不同 display name、bundle id、icon、首頁與權限。
- EMT、TL、SCC 需要優先考慮 iPad 版操作。

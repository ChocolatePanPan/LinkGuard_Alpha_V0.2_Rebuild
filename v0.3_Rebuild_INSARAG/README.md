# LinkGuard v0.3 Rebuild INSARAG

本資料夾目前建立 v0.3 的資料夾骨架、README、各版本獨立 Xcode project，以及共享 Swift framework。Mac、iOS、iPad 角色 project 均有獨立 target/scheme；共用程式放在 `shared/LinkGuardV03Core`，讓各版本引用同一套模型、權限、同步協議與 field UI。

v0.3 的方向是 USAR/INSARAG + ICS 架構，採用共享核心與角色分流版本。Mac HQ 不再是唯一操作中心，UCC 作為最高協調與資料權威，SCC 作為現場指揮中心，iOS/iPad 依角色分成 VO、TE、TL、EMT。

## Current status

v0.3 目前是 shared core + app target + role field shell + Mac copied HQ UI 的產品化前階段，不是完整 INSARAG 現場系統。已完成的是核心資料模型、同步骨架、角色權限/功能矩陣、可 build 的 field app targets，以及 iOS/iPad FieldUI 的本地 Phase 2 閉環；同步底座已開始產品化，支援 offline flush planning、retry interval 與 manual retry。主要缺口仍是真實 GPS/相機/語音/NFC/地圖能力、正式同步 server/provisioning、Mac v0.3 指揮 UI 與 field drill 驗證。

狀態基準詳見 `docs/implementation-status/README.md`。全版本 Phase、進度與權限總表詳見 [docs/LinkGuard-E 全版本開發流程總表.md](docs/LinkGuard-E%20全版本開發流程總表.md)。

## 版本分流

- `LinkGuard-UCC`：最高指揮中心版，Mac 優先。
- `LinkGuard-SCC`：現場總指揮版，Mac + iPad。
- `LinkGuard-VO`：志工/民間支援版，iPhone 優先。
- `LinkGuard-TE`：搜救隊員版，iPhone 優先。
- `LinkGuard-TL`：小隊長/分區指揮版，iPhone + iPad。
- `LinkGuard-EMT`：醫療/檢傷版，iPhone + iPad，必須獨立。

## 重要決策

- 消防訪談後的第一優先不是 AI，而是不斷線、不當機、能離線與現場低負擔操作。
- 現場主要操作必須三秒內完成，戴手套可操作，採大按鈕、夜間高對比、單手可操作、低誤觸與短指令流程。
- EMT 版一定要獨立，因為醫療流程不等於搜救流程。
- EMT 主要關心 Triage、CCP、後送、醫院容量、傷患生命徵象。
- EMT 不應被分區、ICS 指揮、搜救進度等非醫療作業干擾。
- After Action Review 災後復盤必須納入核心資料流，記錄誰做了什麼、何時做、指令流向與決策紀錄。

## 目前結構

- `apps/`：各版本 App 的位置。
- `shared/`：共享核心、協議、離線同步、附件與設計系統。
- `shared/LinkGuardV03Core/`：v0.3 第一版 Swift package framework。
- `modules/`：ICS 五大模組、醫療模組與災後復盤。
- `docs/`：架構、權限、流程規格。
- `resources/`：地圖 overlay 與範例資料。

## Xcode projects

各角色版本的 Xcode project 分開建立於自己的版本資料夾內。UCC/SCC Mac、TL/TE/VO/EMT iPhone，以及 SCC/TL/EMT iPad 都已建立可 build 的 target/scheme，並透過 local Swift package 依賴 `LinkGuardV03Core` / `LinkGuardV03FieldUI`。

## Implementation framework

`shared/LinkGuardV03Core` 目前包含：

- app identity 與 role profile。
- ICS section、position、role assignment。
- app permission matrix 與 role blueprint。
- role feature access matrix：以 UCC/SCC/TL/TE/EMT/VO 的 ●/○/✕ 細項矩陣定義地圖、人員、醫療、通訊與 AI/指揮功能 gate。
- LinkGuard-UCC phase catalog：全區儀表板、ICS 架構、跨區調度、AI 分析、災情統計、電台監聽、事件日誌、PWS、EMIC、資源總控、安全管制、多指揮中心與 INSARAG 國際協作的 13 phase 產品契約。
- LinkGuard-VO volunteer phase catalog：帳號、GPS、SOS、照片、災情回報、離線暫存、語音、多語、安全警告與超簡化模式的 10 phase 產品契約。
- LinkGuard-TE phase catalog：任務接收、GPS、SOS、照片、危險標記、分區資訊、任務回報、離線、語音、安全管制、LoRa 與高壓模式的 12 phase 產品契約。
- LinkGuard-EMT medical phase catalog：傷患建立、START、生命徵象、狀態更新、後送、醫療照片、語音病歷、離線病歷、多語翻譯、AI 預警、醫院資訊與手錶整合的 12 phase 產品契約。
- incident、sector、sub-sector、worksite、task、alert、map feature。
- personnel overview：GPS、作業狀態、在線狀態與電量摘要。
- photo report：照片附件 ID、GPS、時間戳記與任務/案場關聯。
- safety control：危險區、安全管制區與人員進出紀錄。
- communication：群組聊天與語音回報 payload。
- EMT patient、vitals、evacuation、hospital capacity 與醫療版本 phase roadmap。
- Finance purchase request 與 personnel hours。
- AAR audit event、decision record、timeline event。
- sync envelope、idempotency key、offline queue、operation snapshot store。
- HTTP envelope transport、file-backed local cache store、connectivity recovery sync coordinator、offline flush planning、retry interval 與 manual retry。
- firefighter interview field principles：可靠、離線、三秒操作、手套、大按鈕、夜間高對比、單手、低誤觸、短指令流程。
- offline map tile manifest、tile request template、download progress model。
- field SOS one-tap action：iPhone/iPad runtime + latest GPS fix → SOS envelope。
- AAR audit query 與 JSON/CSV export bundle。
- `LinkGuardV03FieldUI`：iPhone/iPad field app shell + Phase 2 controller，依角色功能矩陣排隊 Sector/Sub-sector/Worksite、點線面地圖標記、人員狀態、任務回報、照片、傷患/START/後送、安全進出、聊天、語音與 SOS envelopes。
- FieldUI role shell：TL 顯示分區/Worksite/任務派遣，TE/VO 顯示任務接收、GPS、照片、SOS 與回報，SCC-iPad 顯示分區管理、人員總覽與安全管制，EMT 顯示傷患、START、生命徵象與後送；所有操作會更新本地 `OperationSnapshot` 與 outbox。
- USAR team capability profile：v3 shared core 已加入正式「城市搜索與救援隊隊伍概況表」A/B/C/D 資料模型、`teamCapabilityReportUpsert` sync message、FieldUI queue action、snapshot 儲存與 audit event；完整 v0.2 可執行專案也同步保留於 `legacy/V0.2_complete_snapshot/`。

驗證指令：

```bash
cd v0.3_Rebuild_INSARAG/shared/LinkGuardV03Core
swift test
```

## Versioning

目前版本基準是 `0.3.1-alpha.12`，由 repo 根目錄的 `VERSION`、`VERSION.json`、shared framework 的 `LinkGuardVersionInfo.current` 與 Git tag `v0.3.1-alpha.12` 對齊。

每次實作更新後都必須更新版本號。v0.3 alpha 線使用 `scripts/version.sh bump-alpha`；現場指定版使用 `scripts/version.sh set <version>`。提交後使用 `scripts/version.sh tag` 建立本機 annotated tag。push 前使用 `scripts/version.sh push-check`，並把 `git push origin v<version>` 放在 push 流程最後。

App 設定頁要透過 `LinkGuardAppSettingsInfo` 顯示建構版本、build number、release channel 與 Git tag。

版本檢查指令：

```bash
scripts/version.sh check
```

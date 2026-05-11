# LinkGuard v0.3 Rebuild INSARAG

本資料夾目前只建立 v0.3 的資料夾骨架與 README，不建立 Xcode 專案，也不放入 Swift 程式碼。

v0.3 的方向是 USAR/INSARAG + ICS 架構，採用共享核心與角色分流版本。Mac HQ 不再是唯一操作中心，UCC 作為最高協調與資料權威，SCC 作為現場指揮中心，iOS/iPad 依角色分成 VO、TE、TL、EMT。

## 版本分流

- `LinkGuard-UCC`：最高指揮中心版，Mac 優先。
- `LinkGuard-SCC`：現場總指揮版，Mac + iPad。
- `LinkGuard-VO`：志工/民間支援版，iPhone 優先。
- `LinkGuard-TE`：搜救隊員版，iPhone 優先。
- `LinkGuard-TL`：小隊長/分區指揮版，iPhone + iPad。
- `LinkGuard-EMT`：醫療/檢傷版，iPhone + iPad，必須獨立。

## 重要決策

- EMT 版一定要獨立，因為醫療流程不等於搜救流程。
- EMT 主要關心 Triage、CCP、後送、醫院容量、傷患生命徵象。
- EMT 不應被分區、ICS 指揮、搜救進度等非醫療作業干擾。
- After Action Review 災後復盤必須納入核心資料流，記錄誰做了什麼、何時做、指令流向與決策紀錄。

## 目前結構

- `apps/`：各版本 App 的位置。
- `shared/`：共享核心、協議、離線同步、附件與設計系統。
- `modules/`：ICS 五大模組、醫療模組與災後復盤。
- `docs/`：架構、權限、流程規格。
- `resources/`：地圖 overlay 與範例資料。

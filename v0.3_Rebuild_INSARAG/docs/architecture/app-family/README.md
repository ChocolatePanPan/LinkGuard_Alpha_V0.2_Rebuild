# App Family Architecture

LinkGuard v0.3 採角色分流版本，但底層資料與同步規則必須一致。

## App family

- `LinkGuard-UCC`：最高指揮中心。
- `LinkGuard-SCC`：現場總指揮中心。
- `LinkGuard-VO`：志工與民間支援。
- `LinkGuard-TE`：搜救隊員。
- `LinkGuard-TL`：小隊長與分區指揮。
- `LinkGuard-EMT`：醫療與檢傷，必須獨立。

## Architecture rule

版本可以分開，但事件、地圖、警報、醫療、AAR、Finance 的資料契約不能分裂。所有 app 都應回到同一套 shared model 與 protocol。

端上功能必須依 `LinkGuardFeatureAccessMatrix` 控制顯示與操作：`✕` 不出現在角色介面，`○` 保留查看或有限操作，`●` 才是主要操作入口。

UCC 與 SCC 不能只是同一套 HQ 外殼換名。UCC 是戰略層，負責跨區資源、對外協調與多指揮中心；SCC 是戰術層，負責災區現場戰情、分區切割、任務派遣、多隊協同與現場安全控管。

## LinkGuard-VO rule

VO 的產品定位是最低操作複雜度的災情回報工具。它的主要入口集中在基礎帳號、GPS、SOS、照片、災情回報、離線暫存、語音輸入、多語翻譯、安全警告與超簡化模式；不得暴露命令發布、分區建立、完整傷患資料、ICS 指揮與安全區管理入口。

VO Phase 1-10 由 shared core 的 `LinkGuardVolunteerBlueprint` 定義，並由 `LinkGuardFeatureAccessMatrix` 驗證每個 phase 所需 feature 對 `LinkGuard-VO` 可用。

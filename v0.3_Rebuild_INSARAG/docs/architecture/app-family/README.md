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

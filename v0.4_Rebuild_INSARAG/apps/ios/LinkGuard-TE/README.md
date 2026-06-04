# LinkGuard-TE

搜救隊員版，核心定位是「前線搜救與任務執行裝置」。

## 適用對象

- 前線搜救員
- 第一線搜救隊員
- 特搜隊成員
- 搜索人員

## Phase roadmap

| Phase | 功能模組 | 功能內容 | 開發目的 |
| --- | --- | --- | --- |
| TE Phase 1 | 任務接收 | 接收搜索任務 | 任務執行 |
| TE Phase 2 | GPS定位 | 即時位置同步 | 隊伍掌握 |
| TE Phase 3 | SOS功能 | 緊急求救 | 人員安全 |
| TE Phase 4 | 照片回報 | 搜救照片上傳 | 現場資訊 |
| TE Phase 5 | 危險標記 | 危險點回報 | 安全警示 |
| TE Phase 6 | 分區資訊 | 搜索區域查看 | 搜救定位 |
| TE Phase 7 | 任務回報 | 完成/中止回報 | 指揮同步 |
| TE Phase 8 | 離線模式 | 離線資料同步 | 災後穩定 |
| TE Phase 9 | 語音回報 | 語音紀錄 | 高壓操作 |
| TE Phase 10 | 安全管制 | 進出紀錄 | 人員管理 |
| TE Phase 11 | LoRa整合 | 災區通訊 | 斷網運作 |
| TE Phase 12 | 高壓模式 | 手套操作、大按鈕 | 高可靠性 |

`TeamMemberPhaseCatalog` 是此表的 shared core 來源；FieldUI 透過 `FieldAppController.teamMemberPhases` 取得同一份 roadmap。

TL 手機版也使用同一份 `TeamMemberPhaseCatalog`。目前 TL/TE 啟動身分只作為畫面標示，兩個手機 target 先共用分隊長、副分隊長、搜救員三個身分與一致的小隊任務執行功能面。

## 允許功能

- 分區地圖讀取與有限標記。
- 初步傷患位置與照片回報，正式 START 檢傷交由 TL/EMT。
- 搜救照片上傳與現場狀態紀錄。
- 搜救狀態回報：搜救中、已淨空、危險區。
- PTT、離線訊息、AI 語音轉錄。
- SOS、位置共享與個人狀態回報。
- LoRa 備援通訊與命令接收。

TE 不負責建立 ICS 指揮結構，也不負責完整分區指揮。

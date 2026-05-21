# LinkGuard-SCC iPad

SCC iPad 版用於現場總指揮的移動工作台。

## 使用對象

- 現場指揮官
- 特搜隊現場總指揮
- 分區統籌官
- 災區前進指揮所

## 核心定位

LinkGuard-SCC 是「災區現場戰術指揮中心」，位於 UCC 與 TL 之間，負責現場戰術決策、分區管理、搜救資源調度、多隊伍協調與現場安全控管。

UCC 偏向戰略層，SCC 偏向戰術層。

UCC/SCC 權限分工以 `docs/architecture/role-feature-access/README.md` 的「UCC / SCC 正式基準」為唯一來源，shared core 對應 `UCCSCCCapabilityMatrix`。

## ICS 對照

| ICS 部門 | 中文說法 | 主要工作 | 對 LinkGuard-E 的對應 |
| --- | --- | --- | --- |
| Incident Commander | 事故指揮官 | 統一指揮、設定目標、核准行動計畫 | 消防指揮官／現場總指揮 |
| Command Staff | 指揮幕僚 | 安全、媒體、跨單位聯絡 | 系統管理、對外通報、安全提醒 |
| Operations Section | 作業組 | 執行現場搜救與戰術任務 | 搜救員終端、任務分派、受困者救援 |
| Planning Section | 計畫組 | 蒐集資料、判斷災情、建立行動計畫 | AI 分析、受困者排序、災情地圖 |
| Logistics Section | 後勤組 | 通訊、設備、補給、交通、醫療支援 | LoRa 節點、NFC 傷票、設備電量、通訊維護 |
| Finance/Admin Section | 財務／行政組 | 成本、採購、工時、文件紀錄 | 系統紀錄、任務歷程、災後報告 |

## 主要畫面

- 戰術地圖
- 分區與子區域
- SOS 與重大警報
- 小隊狀態
- 安全管制
- 現場資源

## Phase 路線圖

| Phase | 功能模組 | 功能內容 | 開發目的 |
| --- | --- | --- | --- |
| SCC Phase 1 | 現場戰情儀表板 | 災區即時總覽 | 建立現場戰情中心 |
| SCC Phase 2 | 分區管理 | 建立A/B/C主區 | 災區切割管理 |
| SCC Phase 3 | 子區域管理 | 建立D1/D2等副區 | 大型倒塌管理 |
| SCC Phase 4 | 地圖點線面 | 點線面標記 | 視覺化災區 |
| SCC Phase 5 | 嚴重度分色 | 紅黃綠黑區域 | 危險程度判讀 |
| SCC Phase 6 | 搜救狀態管理 | 搜救中／已淨空／危險區 | 區域管理 |
| SCC Phase 7 | 人員配置 | 搜救隊分派 | 現場調度 |
| SCC Phase 8 | 任務派遣 | 指派搜索任務 | 戰術指揮 |
| SCC Phase 9 | 隊伍能力表 | 隊伍專長與能力 | 最佳化派遣 |
| SCC Phase 10 | SOS統整 | SOS優先排序 | 緊急應變 |
| SCC Phase 11 | 傷患統整 | 傷患總覽 | 醫療協調 |
| SCC Phase 12 | START統計 | 檢傷分類統計 | MCI管理 |
| SCC Phase 13 | 臨時據點 | 指揮所/集結點建立 | 現場部署 |
| SCC Phase 14 | 安全管制 | 危險區封鎖 | 搜救安全 |
| SCC Phase 15 | 人員進出管理 | 進出災區紀錄 | 人員安全 |
| SCC Phase 16 | 會報系統 | 現場會報 | 指揮同步 |
| SCC Phase 17 | 電台監聽 | PTT轉錄 | 通訊管理 |
| SCC Phase 18 | 多隊伍協調 | 跨隊任務整合 | 大型災害協同 |
| SCC Phase 19 | AI決策輔助 | AI派遣建議 | 降低指揮負荷 |
| SCC Phase 20 | AI風險分析 | 結構風險預警 | 搜救安全 |
| SCC Phase 21 | 離線指揮 | 離線地圖與資料 | 通訊中斷備援 |
| SCC Phase 22 | LoRa中繼 | 災區自主通訊 | 基地台失效備援 |
| SCC Phase 23 | 多裝置同步 | iPad/Mac同步 | 現場協同 |
| SCC Phase 24 | UCC同步 | 與中央戰情同步 | 上下層協同 |
| SCC Phase 25 | AAR紀錄 | 災後回放分析 | 檢討與訓練 |

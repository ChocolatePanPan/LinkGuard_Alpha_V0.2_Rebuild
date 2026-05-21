# v0.3 Implementation Status

本文件是 v0.3 目前狀態的判定基準。結論是：v0.3 不是沒有做，但目前完成的是 shared core 骨架、同步資料鏈雛形、offline flush/retry 行為、role feature matrix、可 build 的 app targets、iOS/iPad 角色化 FieldUI 本地閉環，以及 Mac UCC/SCC 套用 copied v0.2 HQ UI；它還不是完整 INSARAG 現場系統。

## Current Classification

目前狀態應視為 `prototype/core scaffold`，不是 `field-ready product`。

已具備的價值是資料契約、權限分流、離線/同步骨架、角色 app 專案結構，以及 field app shell 能依 TL/TE/VO/EMT/SCC-iPad 建立、接收、更新、回報並即時反映本地 snapshot。同步底座已開始產品化，能規劃可送批次、等待 retry interval、手動重試，以及處理缺漏 transport receipt。尚未完成的是硬體能力、真實同步 server/provisioning、Mac v0.3 指揮 UI 產品化，以及跨角色現場演練驗證。

## Completed Foundation

- `LinkGuardV03Core` 已包含 incident、sector、sub-sector、worksite、task、map、personnel、photo、safety、communication、medical、AAR、finance 等核心模型。
- `SyncEnvelope`、`OperationSnapshot`、`OfflineQueue`、transport topology、local cache/recovery sync coordinator 已建立資料鏈骨架，並具備 offline flush planning、retry interval gating、manual retry 與 receipt failure handling。
- `RoleProfileCatalog`、`AppBlueprintCatalog`、`LinkGuardFeatureAccessMatrix` 已定義 UCC/SCC/TL/TE/EMT/VO 的權限與功能可見性。
- `SCCPhaseCatalog` 已將 LinkGuard-SCC 的 25 phase 固定為 shared core 產品契約；Phase 1-16、18、19、21、25 由現有 core/feature gate/snapshot 骨架覆蓋，Phase 17/22 為通訊整合待接，Phase 20/23/24 為產品化與上下層協同待接。
- Mac `LinkGuard-UCC` / `LinkGuard-SCC` 已有可 build project，並包入 copied v0.2 HQ UI。
- iPhone `LinkGuard-TL` / `LinkGuard-TE` / `LinkGuard-VO` / `LinkGuard-EMT` 與 iPad `LinkGuard-SCC-iPad` / `LinkGuard-TL-iPad` / `LinkGuard-EMT-iPad` 已有 target/scheme 與 shared FieldUI shell。
- `LinkGuardV03FieldUI` 可依角色矩陣排隊地圖標記、人員狀態、任務回報、照片、傷患/START/後送、安全進出、聊天、語音與 SOS envelopes。
- FieldUI 已加入角色化 Phase 2 本地閉環：TL 分區/Worksite/任務派遣，TE/VO 任務接收/GPS/照片/SOS/回報，SCC-iPad 分區管理/人員總覽/安全管制，EMT 傷患/START/生命徵象/後送。
- `UCCPhaseCatalog` 已將 LinkGuard-UCC 的 13 phase 固定為 shared core 產品契約；Phase 1-5、7、10、11 由既有 UCC 權限、feature gate、snapshot 與 sync message 類型覆蓋，Phase 6/8/9 為外部整合待接，Phase 12/13 為戰略產品規劃。
- Mac UCC 已導入第一版 ICS architecture panel：`MacUCCICSArchitecture`、`MacICSSectionLane`、`MacICSBoundaryRule` 與 `MacSystemUIState.uccICSArchitecture`，並以 `MacUCCICSArchitecturePanel` 顯示 UCC 的 Command/Operations/Planning/Logistics/Finance/AAR 邊界。
- `TeamMemberPhaseCatalog` 已將 LinkGuard-TE 的 12 phase 固定為 shared core 產品契約；Phase 1-10 由現有 core/FieldUI envelope、離線與權限 gate 覆蓋，Phase 11 LoRa 為待硬體整合，Phase 12 高壓模式連到 field operation principles。
- `EMTMedicalPhaseCatalog` 已將 LinkGuard-EMT 醫療版本 12 phase 固定為 shared core 產品契約；Phase 1-9 與 11 由現有 medical core/FieldUI gate 覆蓋，Phase 10 醫療AI預警與 Phase 12 手錶整合仍是後續產品化工作。

## Productization Gaps

- iOS/iPad 現場端已有角色化 shell 與本地 snapshot 閉環，但仍需要接上真實系統能力與完整 field drill 後才能視為正式產品頁面。
- field app 尚未接入實際 `CLLocationManager`、相機/照片 picker、麥克風/PTT、語音轉錄、地圖 SDK、NFC 讀寫、背景上傳與系統通知。
- Mac UCC/SCC 目前主要仍是 copied v0.2 HQ UI；UCC 已有第一版 ICS architecture panel，但各 ICS lane 尚未完整替換成 v0.3 專用指揮流程。
- SCC 的 25 phase 產品契約已補入 shared core，但 Phase 17 電台監聽、Phase 22 LoRa 中繼、Phase 23 多裝置同步、Phase 24 UCC 同步仍未串成正式產品流程，Phase 20 AI 風險分析仍缺專用模型與驗證。
- UCC Phase 6/8/9/12/13 已有 shared core roadmap 與 feature gate，但仍待接入實際 PTT/PWS/EMIC、備援切換與國際協作流程。
- HQ/UCC/SCC 與 field apps 的實際 HTTP/WebSocket/Bonjour/LoRa/MQTT/離線轉送鏈路尚未以產品流程串起；目前已完成 client-side offline retry 行為，尚缺 server endpoint、device provisioning 與真實網路 field drill。
- TE Phase 11 的 LoRa 仍待 iPhone field app 接入實際 LoRa/BLE gateway、封包轉換與弱網演練。
- EMT Phase 10/12 仍待接入 AI 惡化預測模型與 Apple Watch/其他穿戴式生命徵象來源。
- conflict handling、device provisioning、role assignment、manual/config sync 尚未做成完整端上流程。
- 醫療流程需要正式 EMT UI：傷患卡、START、生命徵象、後送、醫院容量、交接與歷史時間軸。
- 地圖流程需要正式點線面工具、離線地圖下載/選區、危險區、搜救進度著色與 worksite layers。
- 目前尚未完成 field drill 驗證，因此不能宣稱為完整 INSARAG 現場系統。

## Definition Of Done For Field System

完整 INSARAG 現場系統至少需要以下條件同時成立：

- 每個角色 app 都有自己的首頁、主要流程與權限裁切後的 UI。
- UCC/SCC/Mac/iPad/iPhone 能透過正式通道同步同一個 incident state。
- 斷線時所有現場操作可本地暫存，恢復通訊後自動同步並可追蹤狀態。
- GPS、照片、語音、NFC、地圖、通知、權限與裝置設定都接入真實系統 API。
- Mac UCC/SCC 不只是 v0.2 HQ 外殼，而是 v0.3 的 UCC/SCC 指揮產品。
- 經過角色分流、離線、弱網、多人同步、SOS、醫療後送與 AAR 的 field drill 驗證。

## Next Implementation Order

1. 建立 field app 到 HQ/UCC/SCC 的正式 sync server endpoint、device provisioning 與角色配置。
2. 接上真實 GPS、照片、語音、NFC、地圖與通知能力。
3. 將 Mac UCC/SCC 從 copied HQ UI 逐步替換為 v0.3 指揮流程。
4. 做 offline/weak-network field drill，將結果轉成測試與修復清單。

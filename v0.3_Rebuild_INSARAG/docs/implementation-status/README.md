# v0.3 Implementation Status

本文件是 v0.3 目前狀態的判定基準。結論是：v0.3 不是沒有做，但目前完成的是 shared core 骨架、同步資料鏈雛形、role feature matrix、可 build 的 app targets、iOS/iPad 角色化 FieldUI 本地閉環，以及 Mac UCC/SCC 套用 copied v0.2 HQ UI；它還不是完整 INSARAG 現場系統。

## Current Classification

目前狀態應視為 `prototype/core scaffold`，不是 `field-ready product`。

已具備的價值是資料契約、權限分流、離線/同步骨架、角色 app 專案結構，以及 field app shell 能依 TL/TE/VO/EMT/SCC-iPad 建立、接收、更新、回報並即時反映本地 snapshot。尚未完成的是硬體能力、真實同步通道、Mac v0.3 指揮 UI 產品化，以及跨角色現場演練驗證。

## Completed Foundation

- `LinkGuardV03Core` 已包含 incident、sector、sub-sector、worksite、task、map、personnel、photo、safety、communication、medical、AAR、finance 等核心模型。
- `SyncEnvelope`、`OperationSnapshot`、`OfflineQueue`、transport topology、local cache/recovery sync coordinator 已建立資料鏈骨架。
- `RoleProfileCatalog`、`AppBlueprintCatalog`、`LinkGuardFeatureAccessMatrix` 已定義 UCC/SCC/TL/TE/EMT/VO 的權限與功能可見性。
- Mac `LinkGuard-UCC` / `LinkGuard-SCC` 已有可 build project，並包入 copied v0.2 HQ UI。
- iPhone `LinkGuard-TL` / `LinkGuard-TE` / `LinkGuard-VO` / `LinkGuard-EMT` 與 iPad `LinkGuard-SCC-iPad` / `LinkGuard-TL-iPad` / `LinkGuard-EMT-iPad` 已有 target/scheme 與 shared FieldUI shell。
- `LinkGuardV03FieldUI` 可依角色矩陣排隊地圖標記、人員狀態、任務回報、照片、傷患/START/後送、安全進出、聊天、語音與 SOS envelopes。
- FieldUI 已加入角色化 Phase 2 本地閉環：TL 分區/Worksite/任務派遣，TE/VO 任務接收/GPS/照片/SOS/回報，SCC-iPad 分區管理/人員總覽/安全管制，EMT 傷患/START/生命徵象/後送。
- `TeamMemberPhaseCatalog` 已將 LinkGuard-TE 的 12 phase 固定為 shared core 產品契約；Phase 1-10 由現有 core/FieldUI envelope、離線與權限 gate 覆蓋，Phase 11 LoRa 為待硬體整合，Phase 12 高壓模式連到 field operation principles。

## Productization Gaps

- iOS/iPad 現場端已有角色化 shell 與本地 snapshot 閉環，但仍需要接上真實系統能力與完整 field drill 後才能視為正式產品頁面。
- field app 尚未接入實際 `CLLocationManager`、相機/照片 picker、麥克風/PTT、語音轉錄、地圖 SDK、NFC 讀寫、背景上傳與系統通知。
- Mac UCC/SCC 目前主要仍是 copied v0.2 HQ UI，尚未完整改成 v0.3 INSARAG/UCC/SCC 指揮流程。
- HQ/UCC/SCC 與 field apps 的實際 HTTP/WebSocket/Bonjour/LoRa/MQTT/離線轉送鏈路尚未以產品流程串起。
- TE Phase 11 的 LoRa 仍待 iPhone field app 接入實際 LoRa/BLE gateway、封包轉換與弱網演練。
- local cache、sync retry、conflict handling、device provisioning、role assignment、manual/config sync 尚未做成完整端上流程。
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

1. 接上真實 GPS、照片、語音、NFC、地圖與通知能力。
2. 建立 field app 到 HQ/UCC/SCC 的正式 sync client/server 與 device provisioning。
3. 將 Mac UCC/SCC 從 copied HQ UI 逐步替換為 v0.3 指揮流程。
4. 做 offline/weak-network field drill，將結果轉成測試與修復清單。
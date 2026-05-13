# v0.3 Implementation Status

本文件是 v0.3 目前狀態的判定基準。結論是：v0.3 不是沒有做，但目前完成的是 shared core 骨架、同步資料鏈雛形、role feature matrix、可 build 的 app targets，以及 Mac UCC/SCC 套用 copied v0.2 HQ UI；它還不是完整 INSARAG 現場系統。

## Current Classification

目前狀態應視為 `prototype/core scaffold`，不是 `field-ready product`。

已具備的價值是資料契約、權限分流、離線/同步骨架、角色 app 專案結構，以及 field app shell 能產生 envelopes。尚未完成的是端上正式工作流、硬體能力、真實同步通道、Mac v0.3 指揮 UI 產品化，以及跨角色現場演練驗證。

## Completed Foundation

- `LinkGuardV03Core` 已包含 incident、sector、sub-sector、worksite、task、map、personnel、photo、safety、communication、medical、AAR、finance 等核心模型。
- `SyncEnvelope`、`OperationSnapshot`、`OfflineQueue`、transport topology、local cache/recovery sync coordinator 已建立資料鏈骨架。
- `RoleProfileCatalog`、`AppBlueprintCatalog`、`LinkGuardFeatureAccessMatrix` 已定義 UCC/SCC/TL/TE/EMT/VO 的權限與功能可見性。
- Mac `LinkGuard-UCC` / `LinkGuard-SCC` 已有可 build project，並包入 copied v0.2 HQ UI。
- iPhone `LinkGuard-TL` / `LinkGuard-TE` / `LinkGuard-VO` / `LinkGuard-EMT` 與 iPad `LinkGuard-SCC-iPad` / `LinkGuard-TL-iPad` / `LinkGuard-EMT-iPad` 已有 target/scheme 與 shared FieldUI shell。
- `LinkGuardV03FieldUI` 可依角色矩陣排隊地圖標記、人員狀態、任務回報、照片、傷患/START/後送、安全進出、聊天、語音與 SOS envelopes。

## Productization Gaps

- iOS/iPad 現場端仍需要正式角色頁面，而不是共用 shell 上的 envelope demo actions。
- field app 尚未接入實際 `CLLocationManager`、相機/照片 picker、麥克風/PTT、語音轉錄、地圖 SDK、NFC 讀寫、背景上傳與系統通知。
- Mac UCC/SCC 目前主要仍是 copied v0.2 HQ UI，尚未完整改成 v0.3 INSARAG/UCC/SCC 指揮流程。
- HQ/UCC/SCC 與 field apps 的實際 HTTP/WebSocket/Bonjour/LoRa/MQTT/離線轉送鏈路尚未以產品流程串起。
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

1. 先產品化 iOS/iPad role homepages 與核心流程：TL、TE、EMT、SCC-iPad 優先。
2. 接上真實 GPS、照片、語音、NFC、地圖與通知能力。
3. 建立 field app 到 HQ/UCC/SCC 的正式 sync client/server 與 device provisioning。
4. 將 Mac UCC/SCC 從 copied HQ UI 逐步替換為 v0.3 指揮流程。
5. 做 offline/weak-network field drill，將結果轉成測試與修復清單。
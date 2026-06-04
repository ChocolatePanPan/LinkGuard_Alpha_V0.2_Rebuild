# Data Flow

此文件規劃 v0.3 跨版本資料流。

## Core path

1. 現場端建立事件或回報。
2. 離線時先寫入本機佇列。
3. 連線後同步到 SCC 或 UCC。
4. Store 去重、合併、保留來源與時間。
5. AAR 同步記錄資料變更、指令流向與確認狀態。

## Implemented framework path

- `LinkGuardAppRuntime`：每個 app 的邏輯入口，負責角色 profile、blueprint、權限 gate 與 outbound envelope。
- `SyncEnvelope`：所有跨 app payload 的共同封包。
- `TransportTopology`：依訊息類型決定 command spine、field operations、medical、finance、broadcast 或 audit 路由。
- `InMemoryTransportHub`：在真實網路前驗證傳輸鏈路與接收端 store apply。
- `OperationSnapshot`：接收端 reducer/store，使用 idempotency key 去重。

## Route families

- Command：UCC/SCC/TL 指揮鏈。
- Field operations：TL/TE/VO/SCC/UCC 任務鏈。
- Medical clinical：只給 EMT 與 EMT iPad。
- Medical operational：EMT、SCC、UCC 分享後送與容量狀態。
- Broadcast：全 app 警報與確認。
- Finance：UCC 財務彙整。
- Audit：全 app 進入 AAR 軌跡。

## Must preserve

- event id
- source app
- source role
- device id
- created time
- received time
- location
- attachment references
- acknowledgement state

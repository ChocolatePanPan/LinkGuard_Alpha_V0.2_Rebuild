# Sync Contracts

Sync contract 定義資料如何跨 app 合併。

## Contract fields

- message id
- message type
- schema version
- source app
- source role
- source device
- payload
- created time
- idempotency key

## Rule

接收端必須可安全處理重送、延遲、重排序與部分附件缺失。

## Current implementation

`shared/LinkGuardV03Core` 已實作第一版 sync contract：

- `SyncEnvelope`
- `SyncMessageType`
- `OfflineQueue`
- `TransportTopology`
- `InMemoryTransportHub`
- `OperationSnapshot`

第一版用 in-memory transport 驗證邏輯，之後 app target 可把同一個 envelope 接到 Bonjour、LAN relay、HTTP relay、LoRa gateway 或離線匯入流程。

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

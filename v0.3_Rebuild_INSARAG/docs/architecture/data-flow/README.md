# Data Flow

此文件規劃 v0.3 跨版本資料流。

## Core path

1. 現場端建立事件或回報。
2. 離線時先寫入本機佇列。
3. 連線後同步到 SCC 或 UCC。
4. Store 去重、合併、保留來源與時間。
5. AAR 同步記錄資料變更、指令流向與確認狀態。

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

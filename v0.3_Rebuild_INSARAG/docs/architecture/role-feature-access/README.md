# Role Feature Access Matrix

此表是 `LinkGuardFeatureAccessMatrix` 的產品規則來源。`●` 代表主要操作權限，`○` 代表部分權限或查看權限，`✕` 代表不提供該功能，以降低端上介面複雜度與誤操作風險。

| 功能 | UCC | SCC | TL | TE | EMT | VO |
| --- | --- | --- | --- | --- | --- | --- |
| 全區災情總覽 | ● | ● | ○ | ✕ | ○ | ✕ |
| 分區建立 | ○ | ● | ● | ✕ | ✕ | ✕ |
| 子區域建立 | ✕ | ○ | ● | ✕ | ✕ | ✕ |
| 指揮調度 | ● | ● | ○ | ✕ | ✕ | ✕ |
| 任務分派 | ○ | ● | ● | ✕ | ✕ | ✕ |
| SOS處理 | ○ | ● | ● | ● | ● | ○ |
| GPS定位 | ● | ● | ● | ● | ● | ● |
| 照片回報 | ○ | ● | ● | ● | ● | ● |
| 傷患上傳 | ✕ | ○ | ● | ○ | ● | ✕ |
| START檢傷 | ✕ | ○ | ● | ✕ | ● | ✕ |
| 後送管理 | ✕ | ○ | ✕ | ✕ | ● | ✕ |
| 傷患狀態更新 | ✕ | ○ | ● | ✕ | ● | ✕ |
| AI決策分析 | ● | ● | ○ | ✕ | ✕ | ✕ |
| 離線暫存 | ● | ● | ● | ● | ● | ● |
| 安全管制 | ○ | ● | ● | ✕ | ✕ | ✕ |
| 事件日誌 | ● | ● | ○ | ✕ | ○ | ✕ |
| 會報功能 | ○ | ● | ● | ✕ | ✕ | ✕ |
| 電台監聽 | ● | ● | ○ | ✕ | ✕ | ✕ |

## Runtime rules

- iPad variants inherit their role column: `SCC-iPad` uses SCC, `TL-iPad` uses TL, and `EMT-iPad` uses EMT.
- FieldUI must hide `✕` actions, allow `●` actions, and allow only constrained/view-oriented flows for `○` actions.
- Message-level gates remain in `AppLogicGate`; product-level visibility and field operation checks must call `LinkGuardFeatureAccessMatrix`.
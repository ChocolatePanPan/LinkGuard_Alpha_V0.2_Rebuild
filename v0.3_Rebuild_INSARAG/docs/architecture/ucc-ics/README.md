# UCC ICS Architecture

本文件定義 LinkGuard-UCC 導入 ICS 架構後的產品邊界、資料模型與 Mac UI 行為。UCC 的定位是跨區協調與戰略資料權威，不是把 SCC 的現場戰術工作全部搬到 Mac HQ。

## Current implementation

已完成的導入點：

- `MacUCCICSArchitecture`：UCC 專屬的 ICS 架構摘要模型。
- `MacICSSectionLane`：將 `ICSSection` 轉成 UCC 畫面可呈現的指揮分層。
- `MacICSBoundaryRule`：明確列出 UCC/SCC/EMT/AAR 的邊界規則。
- `MacSystemUIState.uccICSArchitecture`：只有 `LinkGuard-UCC` 會有值，SCC 不套用。
- `MacUCCICSArchitecturePanel`：Mac UCC 畫面左上方顯示 ICS 架構面板。
- 測試覆蓋：UCC 會生成 ICS 架構，SCC 不會被誤套成 UCC 架構。

目前這是 `architecture panel`，不是完整的 UCC 指揮工作台。它的用途是把 UCC 的 ICS 分層先固定在 shared Mac UI state，作為後續逐步替換 copied v0.2 HQ UI 的穩定入口。

## UCC command role

UCC 採 `global` command authority，主要負責：

- 跨災區協調。
- 多 SCC 狀態監控。
- 外部機關、EOC、OSOCC/RDC 類協作。
- 全區資源缺口、醫療量能、道路中斷與統計分析。
- PWS、EMIC、跨中心同步與備援。
- AAR 彙整與決策紀錄。

UCC 不應直接取代 SCC 的現場戰術指揮。分區、worksite、現場安全、出入管制與 TE/TL 即時任務落地仍由 SCC/TL 主責。

## ICS lanes in UCC

| ICS Section | UCC responsibility | Primary positions | Authority boundary |
| --- | --- | --- | --- |
| Command | 全局目標、跨中心指揮權限、對外協調與警報發布 | Incident Commander, Liaison Officer, Public Information Officer, Safety Officer | UCC 主責跨區與外部協調；SCC 主責現場命令落地 |
| Operations | 跨區資源調度、SCC 戰情監控、重大任務與 SOS 升級 | Operations Section Chief, Sector Commander, Team Leader | UCC 看全區與跨區缺口；SCC/TL 主責現場任務派遣 |
| Planning | IAP 週期、情資彙整、災情統計與作戰節奏 | Planning Section Chief | UCC 匯整 IAP 與情資；SCC 維護現場 operational period 細節 |
| Logistics | 通訊、裝備、電力、交通、LoRa/中繼與補給支援 | Logistics Section Chief | UCC 協調跨區資源；SCC 管現場補給、通訊與中繼 |
| Finance | 工時、採購、成本、行政文件與災後請款資料 | Finance Section Chief | UCC 主責彙整；現場端只提供必要工時與成本事件 |
| Medical | 後送、醫院容量、醫療量能與跨區 EMT 支援摘要 | EMT Lead, EMT | UCC 只看營運摘要；EMT 保留完整 clinical data |
| AAR | 事件時間線、決策紀錄、證據包與復盤匯出 | Incident Commander, Planning Section Chief | UCC 彙整跨區復盤；各端都必須保留原始 audit event |

## Boundary rules

### SCC keeps tactical authority

UCC 可以監控多個 SCC 狀態、資源缺口與重大告警，但不應直接操作 SCC 的細部現場流程。以下仍歸 SCC/TL：

- Sector / sub-sector / worksite 建立與調整。
- 現場任務派遣與任務完成判定。
- 人員進出與危險區安全管制。
- TE/TL/EMT 即時位置與最後定位處置。
- 搜救動線、撤離路線與工作區清空狀態。

### Medical data stays bounded

UCC 需要醫療營運摘要，但不需要完整臨床病歷。

UCC 可看：

- 後送請求數量與優先級。
- 醫院容量與區域醫療量能。
- EMT 跨區派遣需求。
- 傷患位置與狀態摘要。

UCC 不應直接看到：

- 完整 clinical notes。
- 詳細生命徵象歷史。
- 未授權的傷患照片與病歷附件。

### AAR is shared, not centralized after the fact

AAR 不是災後才人工補寫，而是每個 app 在操作時產生 audit event。UCC 的角色是跨區彙整、查詢、匯出與復盤，而不是唯一寫入點。

## Data authority

| Domain | Primary writer | UCC access | Notes |
| --- | --- | --- | --- |
| Incident objective | UCC / SCC | Full | UCC 可建立跨區目標，SCC 落地現場 operational objective |
| Sector / worksite | SCC / TL | Summary or assisted | UCC 監控，不作為現場細部編輯主端 |
| Tasking | SCC / TL | Assisted | UCC 可看跨區缺口與重大任務升級 |
| Personnel/resource | SCC / Logistics / UCC | Full summary | UCC 主責跨區調度，SCC 主責現場狀態 |
| Medical clinical | EMT | Operational summary | 完整臨床資料只在 EMT 授權邊界 |
| Finance/Admin | UCC | Full | 現場端提供工時、成本與採購事件 |
| AAR/Audit | All apps | Full aggregation | UCC 彙整跨區時間線與證據包 |

## UI behavior

Mac UCC 的 ICS panel 是「架構導覽與權限邊界提示」，不是新的完整操作頁。它應該：

- 永遠只在 `.ucc` app ID 顯示。
- 使用 `MacSystemUIState.uccICSArchitecture`，不要在 view 裡硬編 UCC/SCC 規則。
- 顯示 UCC 的 global command authority。
- 顯示每個 ICS lane 的責任、職位與 authority boundary。
- 保留 copied v0.2 HQ UI 既有功能，直到各 lane 被 v0.3 專用畫面替換。

## Productization order

1. 將 UCC ICS panel 從 overlay 升級為正式 UCC home dashboard 的一個固定區塊。
2. 為 Command lane 建立 UCC objectives / alerts / authority switch 頁面。
3. 為 Operations lane 建立多 SCC 狀態與跨區資源缺口頁面。
4. 為 Planning lane 建立 IAP、operational period、情資摘要與統計頁面。
5. 為 Logistics lane 建立通訊、LoRa、裝備、電力與補給狀態頁面。
6. 為 Medical lane 建立醫療量能與後送摘要頁面，保持 clinical data boundary。
7. 為 Finance/AAR lane 建立成本、工時、採購與復盤匯出頁面。

## Acceptance checks

- UCC state contains `uccICSArchitecture`.
- SCC state keeps `uccICSArchitecture == nil`.
- UCC lanes include Command, Operations, Planning, Logistics, Finance, and AAR.
- Operations lane boundary must mention SCC/TL tactical authority.
- Medical lane must only expose operational summary to UCC.
- Tests must protect UCC/SCC separation before any UI refactor.

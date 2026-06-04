# Incident Lifecycle

事件生命週期是 v0.3 的共同流程。

## INSARAG-Aligned Stages

1. 建立事件與 operational period：UCC 或 SCC 建立 incident，設定初始 command authority、事件名稱、時間、範圍與資料同步拓撲。
2. 建立 UCC/SCC 指揮骨架：指派 Command、Operations、Planning、Logistics、Finance/Admin、Safety、Medical 與 AAR 權責。
3. 隊伍接收與能力登錄：UCC/SCC 登錄 USAR/EMT/VO 隊伍，保存 response type、classification、抵達時間、支援需求與是否可支援 OSOCC/RDC。
4. 建立 sector、sub-sector 與 worksite：SCC 依現場範圍、危險、交通、建築物與隊伍能力切分作戰區。
5. 建立地圖 operational picture：載入 GPS、離線圖、航照、平面圖、危險區、集合點、CCP、後送路線與 worksite overlay。
6. 初始 ASR / reconnaissance：TL/TE/VO 回報危險、入口、受困者線索、建築狀態、照片與 GPS；SCC 判定是否納入正式 worksite 狀態。
7. 任務派遣：SCC/TL 依優先度、隊伍能力、安全狀態與醫療負荷派遣搜索、救援、支援、醫療或撤離任務。
8. RCM / 現場標記更新：現場端提交 RCM、搜索進度、危險變化、可進入/禁止進入資訊與照片證據。
9. 醫療檢傷與後送：EMT 建立傷患卡、START、生命徵象、CCP、後送路線、目的地與交接狀態；SCC/UCC 只接收 operational summary。
10. 同步、衝突與稽核：每次任務、地圖、ASR、RCM、醫療摘要、資源或安全事件都要進入 sync envelope 與 audit trail。
11. 資源、後勤與 Finance 紀錄：UCC/SCC 匯整人力、器材、車輛、通訊、補給、支援需求、工時與成本事件。
12. 轉換或收束：worksite 可從未評估、搜索中、救援中、穩定、清空、暫停、移交到關閉；incident 可進入復原、移交或結案。
13. After Action Review：UCC/SCC 產生時間線、指揮決策、同步狀態、任務結果、醫療後送、資源使用與改善項。

## Role Responsibilities

| Stage | Primary role | Supporting roles | Product requirement |
| --- | --- | --- | --- |
| Incident setup | UCC / SCC | Planning | 建立共同 incident state 與權限邊界。 |
| Team intake | UCC / SCC | Logistics | 隊伍能力表必須能影響派遣與資源規劃。 |
| Sectoring | SCC | TL / UCC | 分區是現場 tactical truth，UCC 只看跨區摘要。 |
| ASR / RCM | TL / TE | SCC / VO | 現場回報需可離線保存、附照片/GPS、由 SCC 接受為正式狀態。 |
| Tasking | SCC / TL | UCC | 任務需有目標、worksite、優先度、接收與結果。 |
| Medical | EMT | SCC / UCC | 保護臨床細節，只同步檢傷、後送與容量摘要。 |
| AAR | UCC / SCC | all roles | 所有角色事件需進入時間線與稽核紀錄。 |

## State Transitions

| Object | Normal progression |
| --- | --- |
| Incident | draft -> active -> transition -> closed -> archived |
| Sector | proposed -> active -> saturated -> reduced -> closed |
| Worksite | unassessed -> assigned -> assessing -> searching -> rescue -> stabilized -> cleared -> closed |
| Task | created -> dispatched -> accepted -> inProgress -> blocked/completed -> verified |
| Patient | found -> triaged -> treated -> awaitingEvacuation -> evacuated -> handedOff |
| Sync envelope | queued -> sending -> acknowledged -> merged -> audited |

## Product Guardrails

- UCC 不應直接覆蓋 SCC 的現場 tactical worksite state；若需要跨區調整，應形成命令或建議，並留下 audit trail。
- SCC 可以接受、退回或修正現場端 ASR/RCM，但不能失去原始回報者、時間與證據。
- TL/TE/VO 在離線時仍可完成任務回報、照片、GPS、SOS 與 ASR/RCM 草稿，恢復連線後同步。
- EMT 醫療資料要分成 operational summary 與 clinical details，避免 UCC/SCC 取得不必要病歷細節。
- 結案不是刪除資料，而是凍結 incident truth、輸出 AAR 與保存可追溯紀錄。

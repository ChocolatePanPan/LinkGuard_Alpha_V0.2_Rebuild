# Map Overlay Workflow

v0.3 地圖需要支援 GPS 地圖與離線平面圖/航照 overlay。

完整地圖產品架構（點線面、ICS 分區、搜救狀態、人員安全、離線與 AI 圖層）見 `docs/architecture/map-system/README.md`。

## Overlay types

- GPS calibrated map
- local image overlay
- building floor plan
- drone or aerial image
- printed map scan

## Coordinate modes

- WGS84 GPS coordinate
- local image coordinate
- mixed coordinate with calibration points

## Role view

- UCC/SCC：完整圖層。
- TL：分區與危險區編輯。
- TE：讀取與有限回報。
- VO：只看安全相關圖層。
- EMT：醫療站、CCP、後送路線。

## INSARAG Overlay Layers

| Layer | Purpose | Primary editor | Visible to | Notes |
| --- | --- | --- | --- | --- |
| Incident boundary | 事件範圍與 operational period 基準 | UCC / SCC | all roles | UCC 可看跨 SCC 範圍，SCC 維護現場邊界。 |
| Sector / sub-sector | 現場分區與戰術責任 | SCC | UCC, TL, TE, EMT, VO | 任務、worksite、隊伍與安全管制都應回掛到 sector。 |
| Worksite | 建築物、倒塌區或搜索點 | SCC / TL | all operational roles | 每個 worksite 應有 code、狀態、ASR、RCM、任務與照片。 |
| ASR observations | 評估危險、入口、受困者線索與優先度 | TL / TE | SCC, UCC | 現場端提交後由 SCC 接受為正式狀態。 |
| RCM markings | 搜索/救援標記與交接資訊 | TL / TE | SCC, UCC, TL, TE | 應可附時間、照片、定位與 worksite。 |
| Hazard zones | 禁入、坍塌、火災、化學、電力、水域等危險 | SCC / TL | all roles | TE/VO 可提報，SCC/TL 決定是否升級為正式危險區。 |
| Team locations | 人員與隊伍 GPS / last known position | TL / SCC | UCC, SCC, TL | TE/VO 只看自身與必要安全資訊。 |
| Medical | CCP、傷患集中點、後送路線、醫療站、醫院容量 | EMT / SCC | UCC, SCC, EMT, TL | UCC 看統計與容量，不看完整臨床細節。 |
| Logistics | 集結點、補給、通訊中繼、車輛、器材 | Logistics / SCC | UCC, SCC, TL | 與 Finance/Admin 事件分開，但可被 AAR 彙整。 |
| AAR timeline | 重要決策、任務、SOS、後送、同步與狀態變更 | system | UCC, SCC | 從 audit trail 自動生成，不應靠人工重填。 |

## ASR And RCM Workflow

1. TL/TE 在 worksite 或地圖位置建立 ASR/RCM 草稿。
2. 草稿可包含 GPS、local image coordinate、照片、文字、危險類型、受困者線索、入口、出口與時間。
3. 離線時先存入本機 queue，保持 reporter、device、role 與 timestamp。
4. SCC 收到後決定 accept、revise 或 reject；原始回報仍保留。
5. 被接受的 ASR/RCM 更新 worksite status、search state、hazard zone 或 task priority。
6. UCC 讀取跨區摘要與資源影響，不直接編輯 SCC tactical truth。

## Offline Overlay Rules

- 每個 overlay feature 必須有 stable ID、source role、source device、createdAt、updatedAt 與 sync state。
- local image coordinate 需要保存 calibration reference，不能只保存螢幕像素。
- 同一個 worksite 的多筆 ASR/RCM 不應互相覆蓋；要保留歷史並由 SCC 選定 current operational truth。
- 若 GPS 精度不足，UI 應標示 uncertainty，而不是把點位偽裝成精準座標。
- 衝突合併時優先保留現場證據，再由 SCC/UCC 決定正式狀態。

## Minimum Acceptance

- 可以從地圖點擊 worksite，看見 sector、ASR、RCM、任務、照片、危險與醫療摘要。
- 可以從任務回到地圖定位，並看見隊伍最後位置與安全邊界。
- 可以從 AAR timeline 回放關鍵地圖狀態變更。
- 可以在無網路下建立現場回報，恢復連線後保留來源與審核狀態。

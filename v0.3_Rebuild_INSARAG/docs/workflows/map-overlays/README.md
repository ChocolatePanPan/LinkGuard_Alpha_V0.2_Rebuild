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

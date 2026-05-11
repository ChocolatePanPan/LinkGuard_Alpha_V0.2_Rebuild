# Map Overlay Workflow

v0.3 地圖需要支援 GPS 地圖與離線平面圖/航照 overlay。

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

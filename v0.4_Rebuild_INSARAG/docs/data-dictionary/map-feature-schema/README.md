# Map Feature Schema

地圖資料需要支援點、線、面與校正後的離線圖資。

地圖整體功能架構與圖層規格見 `docs/architecture/map-system/README.md`。

## Fields

- feature id
- feature type
- geometry type
- coordinates
- coordinate mode
- created by
- updated by
- visibility level
- severity
- related incident id
- attachment references

## Geometry types

- point
- polyline
- polygon
- image overlay

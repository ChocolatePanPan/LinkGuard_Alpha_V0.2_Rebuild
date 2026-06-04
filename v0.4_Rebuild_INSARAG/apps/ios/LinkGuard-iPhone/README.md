# LinkGuard-iPhone

v0.4 單一 iPhone 現場入口。

## 啟動身分

`LinkGuard-iPhone` 開啟後先選擇身分，再載入對應 appID、deviceID、權限矩陣與功能頁籤。

- `TL-01` 分隊長：小隊指揮與任務派遣。
- `TL-02` 副分隊長：協助指揮與安全回報。
- `TE-01` 搜救員：任務執行、GPS、照片與 SOS。
- `EMT-01` 救護組長：醫療分流與病患後送。
- `EMT-02` 救護員：START、Vitals、病患照片。
- `VO-01` 志工：支援任務、照片、災情與 SOS。
- `VO-02` 後勤志工：物資支援與位置回報。

## 實作方式

此 target 引用既有 `LinkGuardV03FieldUI`。v0.4 先沿用 shared package 名稱，避免破壞既有 Xcode package 參照；差異集中在 unified iPhone app target 與 `FieldLaunchIdentityOption` 的跨角色啟動資料。

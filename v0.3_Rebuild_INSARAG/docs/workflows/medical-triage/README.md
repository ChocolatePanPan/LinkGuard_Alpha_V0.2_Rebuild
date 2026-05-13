# Medical Triage Workflow

醫療流程必須獨立於搜救流程。

LinkGuard-EMT 是醫療版本，使用對象為 EMT、醫療後送人員與醫療支援組；核心定位是「醫療後送與傷患管理系統」。

## Flow

1. 建立傷患或接收傷患回報
2. START 檢傷
3. 記錄生命徵象
4. 拍攝傷勢照片
5. 指派 Triage 區或 CCP
6. 排定後送順序
7. 配置救護車與醫院
8. 追蹤後送結果

## EMT first

EMT 版不應被 ICS 指揮、分區建立或搜救進度干擾。

## EMT phase roadmap

| Phase | 功能模組 | 功能內容 | 開發目的 |
| --- | --- | --- | --- |
| EMT Phase 1 | 傷患建立 | 傷患資料 | 傷患管理 |
| EMT Phase 2 | START檢傷 | 紅黃綠黑分類 | 醫療排序 |
| EMT Phase 3 | 生理監測 | 心率血氧 | 傷患監控 |
| EMT Phase 4 | 傷患狀態更新 | 病況更新 | 醫療同步 |
| EMT Phase 5 | 後送管理 | 醫院派送 | 醫療調度 |
| EMT Phase 6 | 醫療照片 | 傷勢照片 | 醫療紀錄 |
| EMT Phase 7 | 醫療語音紀錄 | 語音輸入 | 高壓輸入 |
| EMT Phase 8 | 離線模式 | 離線病歷 | 災後運作 |
| EMT Phase 9 | 多語翻譯 | 外籍患者 | 國際災援 |
| EMT Phase 10 | 醫療AI預警 | 惡化預測 | 緊急優先 |
| EMT Phase 11 | 醫院資訊 | 可收治醫院 | 後送決策 |
| EMT Phase 12 | 手錶整合 | Apple Watch等 | 生理感測 |

此表的程式來源是 `EMTMedicalPhaseCatalog`；Phase 1-9 與 11 目前有 shared core / FieldUI gate 支撐，Phase 10 與 Phase 12 分別標示為 AI 預警與裝置整合後續工作。

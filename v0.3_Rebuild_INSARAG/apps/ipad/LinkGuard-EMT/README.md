# LinkGuard-EMT iPad

EMT iPad 版用於醫療站、CCP 與後送管理，核心定位是「醫療後送與傷患管理系統」。

## 適用對象

- EMT
- 醫療後送人員
- 醫療支援組

## 主要畫面

- START 檢傷清單
- 傷患詳情
- 生命徵象趨勢
- 醫療地圖
- 後送排序
- 醫院容量

## Phase roadmap

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

`EMTMedicalPhaseCatalog` 是此表的 shared core 來源；FieldUI 透過 `FieldAppController.emtMedicalPhases` 取得同一份 roadmap。

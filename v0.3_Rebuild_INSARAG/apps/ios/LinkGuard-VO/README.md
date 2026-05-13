# LinkGuard-VO

志工版本，面向民間志工、災民協助人員與後勤支援人員。

## 核心定位

「最低操作複雜度的災情回報工具」

VO 不是小型指揮端，也不是搜救隊員端；它只保留現場民間支援最需要、最不容易誤操作的回報與安全能力。

## 適用對象

- 民間志工。
- 災民協助人員。
- 後勤支援人員。

## Phase roadmap

| Phase | 功能模組 | 功能內容 | 開發目的 |
| --- | --- | --- | --- |
| VO Phase 1 | 基礎帳號 | 登入、身分驗證 | 基本使用管理 |
| VO Phase 2 | GPS 定位 | 即時位置回傳 | 掌握人員位置 |
| VO Phase 3 | SOS 功能 | 緊急求救 | 人員安全 |
| VO Phase 4 | 照片回報 | 現場照片上傳 | 災情回報 |
| VO Phase 5 | 災情回報 | 倒塌、火災、受困回報 | 民間資訊收集 |
| VO Phase 6 | 離線暫存 | 無網路暫存資料 | 災後環境運作 |
| VO Phase 7 | 語音輸入 | 語音轉文字 | 高壓快速回報 |
| VO Phase 8 | 多語翻譯 | 中英日韓越翻譯 | 外籍人士協助 |
| VO Phase 9 | 安全警告 | 危險區提醒 | 防止誤入 |
| VO Phase 10 | 超簡化模式 | 大按鈕、少頁面 | 降低誤操作 |

## 允許功能

- 基礎帳號與身分驗證。
- GPS heartbeat 與位置回傳。
- SOS、照片回報、災情回報。
- 離線暫存與網路恢復後送出。
- 語音輸入、語音回報與中英日韓越翻譯支援。
- 危險區、禁止區與安全警告讀取。
- 集合點、臨時支援點等點位標記。
- 群組訊息與有限任務狀態回報。

## 限制

- 不可發布命令。
- 不可建立分區。
- 不可查看完整傷患資訊。
- 不可操作 ICS 指揮功能。
- 不可建立危險區或修改安全管制規則。

## Shared core 對應

- `LinkGuardVolunteerBlueprint`：定義 VO Phase 1-10、使用對象、支援語言與必要 feature gate。
- `DisasterReport` / `disasterReportUpsert`：承載倒塌、火災、受困等民間災情回報。
- `LinkGuardFeatureAccessMatrix`：VO 對 `sosSending`、`photoReport`、`disasterReport`、`voiceReport`、`realtimeTranslation`、`hazardWarning` 與 `simplifiedMode` 具備操作入口。
- `FieldAppController.queueDisasterReport(...)`：Field UI 可直接排入災情回報 envelope，離線時進入本機 outbox。

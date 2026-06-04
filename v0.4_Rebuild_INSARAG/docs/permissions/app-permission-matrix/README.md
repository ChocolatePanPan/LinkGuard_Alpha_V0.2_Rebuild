# App Permission Matrix

此資料夾規劃各版本的權限矩陣。

## Permission dimensions

- 可以看
- 可以新增
- 可以修改
- 可以刪除或撤回
- 可以發布命令
- 可以確認警報
- 可以強制確認
- 可以離線建立
- 可以查看醫療敏感資料

## High level rules

- VO 最小權限。
- TE 可回報，不可指揮。
- TL 可指揮小隊與分區，可建立會報。
- EMT 可管理醫療資料，但不等同擁有 ICS 指揮權。
- SCC 可現場指揮。
- UCC 可全局協調與資料權威管理。

## VO primary gates

VO 以「最低操作複雜度的災情回報工具」為定位，主要入口只能是回報與安全能力，不得包含指揮、分區、醫療敏感資料或安全規則管理。

| Feature gate | VO access | 對應目的 |
| --- | --- | --- |
| `accountIdentity` | Primary | 基礎帳號與身分驗證 |
| `gpsTracking` | Primary | 即時位置回傳 |
| `sosSending` | Primary | 緊急求救 |
| `photoReport` | Primary | 現場照片上傳 |
| `disasterReport` | Primary | 倒塌、火災、受困回報 |
| `offlineDraftQueue` | Primary | 無網路暫存資料 |
| `voiceReport` | Primary | 語音轉文字與快速回報 |
| `realtimeTranslation` | Primary | 中英日韓越協助 |
| `hazardWarning` / `alertRead` | Primary | 危險區提醒 |
| `simplifiedMode` | Primary | 大按鈕、少頁面 |

# Role Profiles

角色 profile 決定每個 app 版本的首頁、功能與資料可見性。

v0.3 現在採「安裝入口與角色模組分離」：

- 行動端可用同一個 LinkGuard Mobile shell，登入後依帳號、裝置與角色權限啟用 VO/TE/TL/EMT/SCC Mobile 模組。
- 指揮端可用 LinkGuard Command shell，登入後依 UCC/SCC 權限啟用 CEOC dashboard、SCC command、map operations、agency messaging、resource coordination 與 AAR replay。
- Admin / provisioning 模組只在 session 具備 `provisionDevice` 權限時啟用。
- 斷網時可使用最後有效 session 的 module activation snapshot，但高風險操作仍需回到 sync/audit 流程。

## V0.25 功能回填

舊版 V0.25/V0.2 的既有能力先回填到 `ModuleActivationCatalog`，不要只在 UI 做假入口：

- `fieldAIAssistant`：對應 `FieldAIReportView`、`FieldAIChatManager`、雙 AI 共識上報。
- `photoEvidence`：對應 `PhotoReportView`、`photo_server.py`、縮圖/原圖與照片備份。
- `voicePTT`：對應 `RadioView`、`VoiceInputManager`、`whisper_server.py`、LGAP/UDP audio。
- `fieldTranslation`：對應 `TranslatorView` 與離線/線上翻譯 fallback。
- `patientTriage`：對應 `PatientFormView`、`start_triage.py`、`triage.py`。
- `nfcPatientTagging`：對應 `NFCReaderView`、`PatientIDConfig`、`NFCTagWriteRecord`。
- `hospitalDirectory`：對應 `FieldHospitalView`、`FieldHospitalData`、醫院容量/支援點查詢。
- `personalNotifications`：對應 `FieldNotificationView`、`PersonalNotification` 與訊息已讀確認。
- `backupReplay`：對應 `usb_backup.py`、`replay/server.py`、`report_generator.py`。

這些模組目前代表「帳號/角色應啟用的產品能力」，不代表每個舊版畫面都已完整移植成 v0.3 UI。

## Profiles

- UCC
- SCC
- VO
- TE
- TL
- EMT

## Fields

- app id
- display name
- default modules
- allowed actions
- hidden modules
- medical data level
- command authority level

## Module activation

`ModuleActivationCatalog` 是登入後的模組啟用契約來源。它會從 `LoginSession` 推導出：

- product shell：`mobile`、`command` 或 `adminProvisioning`
- enabled modules
- hidden modules
- session/account/device/expiry metadata

這讓「同一安裝包、登入後啟用不同模組」成為可測的 shared core 行為，而不是只存在於 UI 或文件裡。

`AccountDirectory.moduleActivationSnapshot(sessionID:at:)` 與 `AccountDirectory.authorize(sessionID:moduleID:at:)` 是 server/provisioning 或 UI 進入模組前應使用的授權入口；不要在各畫面自行重算角色模組。

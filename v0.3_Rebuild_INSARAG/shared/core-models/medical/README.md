# Medical Core Models

Medical model 只屬於授權醫療流程。

## Models

- patient
- triage record
- vital sign record
- care location
- evacuation request
- hospital capacity
- handoff record
- EMT medical phase catalog

## EMT medical phase catalog

`EMTMedicalPhaseCatalog` 固定 LinkGuard-EMT 醫療版本 12 phase 產品契約：傷患建立、START檢傷、生理監測、傷患狀態更新、後送管理、醫療照片、醫療語音紀錄、離線模式、多語翻譯、醫療AI預警、醫院資訊與手錶整合。

FieldUI 只對 EMT / EMT iPad 回傳 `FieldAppController.emtMedicalPhases`，其他角色不直接取得完整醫療 phase 清單。

## Rule

非 EMT app 只讀取 medical summary，不直接讀完整 patient record。

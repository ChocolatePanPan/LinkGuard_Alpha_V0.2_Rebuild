# Medical Schema

醫療資料需獨立定義，避免被搜救流程欄位稀釋。

## Patient record

- patient id
- triage category
- injury summary
- vital signs
- location
- care location
- evacuation priority
- evacuation status
- destination hospital
- attachment references

## EMT phase coverage

- 傷患建立：`PatientRecord.displayCode`、`injurySummary`、`location`、`careLocationID`。
- START檢傷：`PatientRecord.triageCategory` 固定使用 red/yellow/green/black。
- 生理監測：`VitalSigns.heartRate`、`spo2`、`respiratoryRate`、blood pressure、GCS。
- 傷患狀態更新：`PatientRecord.updatedAt` 與 clinical summary 更新。
- 後送管理：`EvacuationRequest` 記錄 priority、destination hospital、vehicle 與 status。
- 醫療照片/語音：透過 attachment id、`photoReportUpsert` 與 `voiceReportAppend` 保留證據鏈。
- 離線病歷：醫療 envelope 進入 `OfflineQueue`，恢復連線後同步。
- 多語翻譯：以固定醫療詞彙與 translation feature gate 控制。
- 醫療AI預警：以 `aiPatientWarning` gate 管控，避免非醫療角色看到完整病歷。
- 醫院資訊：`HospitalCapacity` 提供急診、外傷、燒燙傷與兒科容量。
- 手錶整合：生命徵象仍寫回 `VitalSigns`，來源可由裝置整合層標記。

## Access rule

完整病患資料只給 EMT 與授權醫療角色。其他角色預設只能看統計與狀態摘要。

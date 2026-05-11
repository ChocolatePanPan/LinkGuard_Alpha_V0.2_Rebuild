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

## Access rule

完整病患資料只給 EMT 與授權醫療角色。其他角色預設只能看統計與狀態摘要。

# Message Types

Message type 決定跨 app 同步的語意。

## Families

- command
- role assignment
- map feature
- task
- team capability profile
- alert
- acknowledgement
- SOS
- medical
- logistics
- finance
- AAR audit

## Rule

每個 message type 都需要 idempotency key 與 created time。

## Added in v0.3

- `teamCapabilityReportUpsert`：正式 USAR「城市搜索與救援隊隊伍概況表」A/B/C/D 欄位，包含隊伍資訊、支援需求、聯絡方式與撤離資訊。此訊息走 personnel overview chain，Field 端可離線排隊，UCC/SCC/TL 端可彙整隊伍能力與後勤需求。

# Audit Fields

Audit 欄位要讓 AAR 可以追出完整決策與執行過程。

## Fields

- audit id
- actor id
- actor role
- app id
- device id
- action
- target type
- target id
- old value reference
- new value reference
- timestamp
- sync timestamp
- command chain reference

## Rule

只要會改變任務狀態、醫療狀態、警報狀態或資源狀態，就必須產生 audit event。

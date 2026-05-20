# Conflict Resolution

離線同步必須處理多人修改同一資料。

## Strategies

- command authority wins for commands
- medical authority wins for patient clinical fields
- latest verified update for location
- merge acknowledgement states
- append-only for audit events

## Rule

衝突不可靜默覆蓋，必須留下 AAR 可追蹤紀錄。

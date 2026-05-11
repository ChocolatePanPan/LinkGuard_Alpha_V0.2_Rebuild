# Offline Chaos Testing

離線測試要刻意製造不穩定網路。

## Cases

- duplicate event resend
- delayed photo upload
- command acknowledged offline
- SOS created offline
- medical red patient update offline
- two devices update same task
- SCC reconnect after UCC outage

## Expected result

事件不可遺失，重送不可重複，AAR 必須顯示建立時間與送達時間差。

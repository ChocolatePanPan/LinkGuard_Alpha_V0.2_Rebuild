# Retry Policy

Retry policy 確保弱網路下資料可送達。

## Rules

- exponential backoff for normal events
- immediate retry when network returns for priority events
- attachment upload can be delayed
- payload metadata must sync before large attachment
- failed messages remain visible to user

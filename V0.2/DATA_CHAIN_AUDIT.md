# LinkGuard 數據鏈審計報告

> 審計日期：2025-07  
> 範圍：Python 後端（9 服務）↔ iOS 前線 ↔ Android 前線 ↔ HQ 指揮中心  
> 方法：逐行比對 JSON_FORMAT_SPEC.md 規範與各平台實作，追蹤 12 條數據流端到端

---

## 一、架構資料流總覽

```
前線裝置 (iOS/Android)
   ↕ WiFiMessage {msgType, payload}
HQ 指揮中心 (iOS/Android, port 8930)
   ↕ Base Format {type, device_id, timestamp, data}
tcp_server.py (port 9000)
   ↕ HTTP / Internal
後端服務群 (Qwen:8001, Whisper:8002, HTTP:8003, Photo:8004, Stats:8005, Resource:8006, UDP:9001)
```

---

## 二、發現的問題與修復狀態

### P0 — 嚴重（功能完全中斷）

| # | 問題 | 檔案 | 影響 | 狀態 |
|---|------|------|------|------|
| 1 | iOS 照片上傳端口錯誤 `:8003` → 應為 `:8004` | `linkguard/PhotoReportView.swift` L206 | http_server(:8003) 無 `/photo` 路由 → iOS 照片上傳一律 404 | ✅ 已修 |
| 2 | HQ BackendBridge 缺少 5 種訊息類型處理 | `LinkGuardHQ/HQBackendBridge.swift` | `report_summary`, `voice_broadcast_rx`, `stats_update`, `resource_update`, `photo_alert` 全部被 `default` 分支丟棄 → 前線裝置永遠收不到這些推播 | ✅ 已修 |
| 3 | TCP Server 位置資料未持久化到資料庫 | `win11/tcp_server.py` location handler | 只存 in-memory dict，從未呼叫 `linkguard_db.save_location()` → `locations` 表永遠為空 → stats_server 的 `wifi_devices` 和 `personnel` 統計永遠為 0 | ✅ 已修 |

### P1 — 重要（部分功能異常）

| # | 問題 | 檔案 | 影響 | 狀態 |
|---|------|------|------|------|
| 4 | Android 會報上傳硬編碼 fallback IP | `Android/.../RadioScreen.kt` L630 | `serverHost` 為空時 fallback 到 `192.168.50.34` → 可能連到錯誤主機 | ✅ 已修 |
| 5 | HQ Bridge 轉發決策時缺少氣象資料 | `LinkGuardHQ/HQBackendBridge.swift` decision handler | `HQDecisionPayload` 建構時未傳入 `weather` → 前線裝置 DecisionView 永遠看不到氣象欄位 | ✅ 已修 |
| 6 | HQ Bridge 轉發傷員報告缺少 `notes` 欄位 | `LinkGuardHQ/HQBackendBridge.swift` forwardPatient | `notes` 未包含在 patientData dict → Qwen AI 分析時缺少備註資訊 | ✅ 已修 |
| 7 | Bonjour/NSD 服務類型衝突 | `tcp_server.py` + `HQCommandServer.swift` | 兩者都註冊 `_linkguard._tcp`，前線裝置可能誤連 tcp_server → 所有 WiFiMessage 格式推播失敗 | ⚠️ 建議修改 |

### P2 — 輕微（邊界情況）

| # | 問題 | 檔案 | 影響 |
|---|------|------|------|
| 8 | `8.8.8.8` IP 偵測法在離線環境失效 | `http_server.py`, `photo_server.py`, `tcp_server.py` | 離線部署時 `_get_local_ip()` 回傳 `127.0.0.1` → 照片/音訊 URL 無法被其他裝置存取 |
| 9 | iOS/Android 傷員 `device_id` 位置不一致 | `CommandEngine.swift` vs `CommandClient.kt` | iOS 把 device_id 放在 data 內層，Android 放在外層（但不影響 triage_START 結果） |

---

## 三、各數據流追蹤結果

### 1. 傷員回報 (Patient Report)
```
iOS/Android → WiFiMessage{msgType:"patient"} → HQ → BackendBridge → tcp_server
→ patient_queue.append(data) → call_qwen_server() → triage_START()
→ decision broadcast → BackendBridge → HQ → WiFiMessage{msgType:"decision"} → 前線
```
- **欄位**: `id`, `breathing_rate`, `capillary_refill`, `can_follow_commands`, `location`, `gps`, `notes` ✅
- **問題 #6**: HQ Bridge 未轉發 `notes` → **已修**

### 2. GPS 位置更新 (Location)
```
iOS/Android → WiFiMessage{msgType:"location"} → HQ → BackendBridge → tcp_server
→ device_locations dict (in-memory) + linkguard_db.save_location() (NEW)
```
- **欄位**: `lat`, `lon`, `accuracy`, `role`, `name` ✅
- **問題 #3**: 原本未呼叫 save_location → **已修**

### 3. 即時語音廣播 (PTT UDP)
```
iOS/Android → UDP:9001 (LGBD binary) → udp_server.py → whisper_server.py:8002
→ voice_result → tcp_server:9000 → broadcast → BackendBridge → HQ → 前線
```
- **二進位格式**: Magic(4) + DevIDLen(2) + DevID(N) + Seq(4) + Timestamp(8) + PCM ✅
- **流程正確** ✅

### 4. 固定會報 (Briefing Report)
```
iOS/Android → POST http://{host}:8003/report (multipart/form-data)
→ http_server.py → whisper_server.py:8002 → 轉錄
→ report_summary → tcp_server:9000 → broadcast
→ BackendBridge → HQ → WiFiMessage{msgType:"report_summary"} → 前線
```
- **欄位**: `audio`, `device_id`, `sender_name`, `location_lat/lon`, `patients_snapshot`, `weather_snapshot` ✅
- **問題 #2**: BackendBridge 原本無 report_summary handler → **已修**

### 5. 照片回報 (Photo)
```
iOS → POST http://{host}:8004/photo → photo_server.py → compress + thumbnail
→ photo_alert → tcp_server:9000 → broadcast → BackendBridge → HQ → 前線
```
- **問題 #1**: iOS 送到 `:8003` → **已修為 `:8004`**
- **問題 #2**: BackendBridge 無 photo_alert handler → **已修**
- **Android**: 目前無照片上傳功能（P2，未來實作）

### 6. AI 決策 (Decision)
```
tcp_server → qwen_server:8001/generate → {decision, patients}
→ broadcast → BackendBridge → HQ → WiFiMessage{msgType:"decision"} → 前線
```
- **問題 #5**: weather 未轉發 → **已修**

### 7. 氣象推播 (Weather)
```
tcp_server → pws_fetcher → broadcast{type:"weather_update"}
→ BackendBridge → 轉為 PWSAlert → HQ → 前線
```
- **欄位**: `temperature`, `humidity`, `wind_speed`, `rainfall` ✅

### 8. 資源管理 (Resource)
```
resource_server:8006 → resource_update → tcp_server → broadcast
→ BackendBridge → HQ → WiFiMessage{msgType:"resource_update"} → 前線
```
- **問題 #2**: BackendBridge 原本無 handler → **已修**

### 9. 即時統計 (Stats)
```
stats_server:8005 → stats_update (every 30s) → tcp_server → broadcast
→ BackendBridge → HQ → WiFiMessage{msgType:"stats_update"} → 前線
```
- **問題 #2**: BackendBridge 原本無 handler → **已修**
- **問題 #3**: stats_server 查 `locations` 表（原本永遠為空）→ **已修**

### 10. 電台控制 (Radio Control)
```
前線 → WiFiMessage{msgType:"radio_control"} → HQ → tcp_server
→ broadcast{type:"voice_broadcast_rx"} → BackendBridge → HQ → 前線
```
- **senderName** 欄位：iOS/Android 都用 camelCase `senderName` ✅
- **tcp_server** 兼容 `sender_name` 和 `senderName` ✅
- **問題 #2**: BackendBridge 原本無 voice_broadcast_rx handler → **已修**

---

## 四、修改摘要

| 檔案 | 修改內容 |
|------|----------|
| `linkguard/PhotoReportView.swift` | `:8003` → `:8004` |
| `LinkGuardHQ/HQBackendBridge.swift` | +5 種訊息 handler, +weather 轉發, +notes 欄位 |
| `LinkGuardHQ/HQCommandServer.swift` | +`relayBackendJSON()` 通用中繼方法 |
| `win11/tcp_server.py` | +`import linkguard_db`, +`save_location()`, +`init_db()` |
| `Android/.../RadioScreen.kt` | 移除硬編碼 IP fallback，改為錯誤回傳 |
| `win11/tests/test_tcp_server.py` | 修復 fixture 引用不存在屬性的 AttributeError |

---

## 五、建議後續處理

1. **P1-7 Bonjour 衝突**：建議將 `tcp_server.py` 的 Bonjour 服務類型改為 `_linkguard-backend._tcp` 或移除註冊（僅 HQ 需要被前線裝置發現）
2. **P2-8 離線 IP 偵測**：改用 `socket.gethostbyname(socket.gethostname())` 作為 fallback
3. **Android 照片上傳**：目前 Android 端尚無照片上傳功能，未來可參考 iOS PhotoReportView 實作
4. **Python 測試**：安裝 `pytest-asyncio` 以啟用 tcp_server async 測試；修復引用已移除屬性的測試案例

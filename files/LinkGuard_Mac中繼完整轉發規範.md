# LinkGuard Mac HQ 完整中繼轉發規範

> 版本：1.0 | 日期：2026-04-10 | 架構原則：iOS → Mac HQ → Windows 全鏈路

---

## 一、架構總覽

```
┌──────────┐                   ┌───────────┐                   ┌───────────┐
│ iOS/     │   TCP 8930        │  Mac HQ   │   TCP 9000        │ Windows   │
│ Android  │◄═════════════════►│  (M2 Air) │◄═════════════════►│ Backend   │
│ 前線裝置 │   Bonjour 自動發現 │           │   HQBackendBridge  │ (3080)    │
│          │   HTTP 8003/8004  │           │   HTTP 8003/8004  │           │
│          │─────────────────► │           │─────────────────► │           │
│          │   UDP 9001→/←9002 │           │                   │           │
│          │◄─────────────────►│           │                   │           │
│          │                   │           │                   │           │
│          │   BLE 914B        │           │   BLE 915B        │           │
│          │◄════════════════► │ LoRa HW   │                   │           │
└──────────┘                   └───────────┘                   └───────────┘
```

**核心原則**：iOS 前線裝置**不直接連線 Windows**。所有流量 100% 經由 Mac HQ 中繼。

---

## 二、TCP 8930 命令通道：所有 msgType 轉發總表

### iOS → Mac → Windows（上行）

| # | msgType | iOS 來源 | Mac 本地處理 | →Windows 轉發方法 | Windows 處理 |
|---|---------|----------|-------------|-------------------|-------------|
| 1 | `status_report` | 每10秒自動 | 更新 fieldUnits | `forwardStatusReport()` | 存 `status_reports` 表 |
| 2 | `location` | 每15秒 GPS | 更新 deviceLocations | `forwardLocation()` | 存 `locations` 表 |
| 3 | `patient` | 傷員表單 | 加入 patientReports + timeline | `forwardPatient()` | 存 `patients` 表 + 觸發 AI 決策 |
| 4 | `chat_message` | 即時聊天 | 中繼給其他 iOS + 記錄 | `forwardChat()` | 存 `chats` 表 |
| 5 | `quick_status` | 快速狀態 | 中繼廣播 + timeline | `forwardQuickStatus()` | 存 `system_events` 表 |
| 6 | `task_update` | 任務進度 | 更新 tasks + timeline | `forwardTaskUpdate()` | 存 `system_events` 表 |
| 7 | `hazard_report` | 危險回報 | 中繼廣播 + timeline | `forwardHazardReport()` | 存 `system_events` 表 + 廣播 |
| 8 | `reinforcement_request` | 增援請求 | 中繼廣播 + timeline | `forwardReinforcementRequest()` | 存 `system_events` 表 |
| 9 | `reinforcement_reply` | 增援回覆 | 中繼廣播 | `forwardReinforcementReply()` | 存 `system_events` 表 |
| 10 | `radio_control` | PTT 開始/結束 | 中繼廣播，更新 currentBroadcaster | `forwardRadioControl()` | 廣播 `voice_broadcast_rx` |
| 11 | `radio_report` | 會報語音 | Apple Speech 辨識 → HQRadioReport | `forwardVoiceResult()` | 觸發 AI 決策 |
| 12 | `sos` | 緊急呼叫 | 中繼 sos_alert + timeline | `forwardSOS()` | 存 `system_events` 表 + 廣播 |
| 13 | `sos_cancel` | 取消 SOS | 中繼 sos_cancel_alert + timeline | `forwardSOSCancel()` | 存 `system_events` 表 + 廣播 |
| 14 | `photo_alert` | 照片回報 | 中繼廣播 + photoAlerts | `forwardPhotoAlert()` | 存 `system_events` 表 + 廣播 |
| 15 | `text_broadcast` | 文字廣播 | 中繼 text_broadcast_rx + 已讀追蹤 | `forwardTextBroadcast()` | 廣播 `text_broadcast_rx` |
| 16 | `message_ack` | 已讀回條 | 更新 readStatuses + 廣播 read_status | `forwardMessageAck()` | 更新已讀追蹤 |
| 17 | `translate_request` | 翻譯請求 | 呼叫 qwen_server /translate | `forwardTranslateRequest()` | （記錄用） |
| 18 | `patient_warning` | 傷患惡化 | 中繼廣播 + timeline | `forwardPatientWarning()` | 廣播 `patient_warning` |
| 19 | `ping` | 每30秒心跳 | 回覆 pong | （不轉發） | — |

### Windows → Mac → iOS（下行）

| # | type | Windows 來源 | Mac 接收處理 | →iOS 轉發 |
|---|------|-------------|------------|----------|
| 1 | `decision` | AI 指揮決策 | 儲存 backendDecisions | `broadcastDecision()` |
| 2 | `weather_update` | 氣象 API | 儲存 backendWeather | `broadcastPWSAlert()` |
| 3 | `node_status` | MQTT LoRa 節點 | 更新 loraNodes | ❌ 僅 HQ 本地顯示 |
| 4 | `report_summary` | 會報摘要 | — | `relayBackendJSON()` |
| 5 | `voice_broadcast_rx` | 語音廣播狀態 | — | `relayBackendJSON(radio_control)` |
| 6 | `stats_update` | 統計更新 | 更新 latestStatsUpdate | `relayBackendJSON()` |
| 7 | `resource_update` | 資源更新 | 更新 latestResourceUpdate | `relayBackendJSON()` |
| 8 | `photo_alert` | 照片回報 | 更新 photoAlerts | `relayBackendJSON()` |

---

## 三、HTTP 多媒體轉發

### 照片（HQPhotoServer :8004）

| 步驟 | 流程 |
|------|------|
| 1 | iOS POST `/photo` multipart → Mac HQPhotoServer |
| 2 | Mac 存照片到 `~/Documents/LinkGuardData/photos/` |
| 3 | Mac 回呼 `onPhotoReceived` → HQ 照片牆 + 廣播 |
| 4 | **Mac `forwardPhotoToBackend()` → HTTP POST 到 Windows :8004/photo** |
| 5 | Windows 壓縮 + 縮圖 + 入 DB + USB 備份 |

### 語音會報（HQSpeechServer :8003）

| 步驟 | 流程 |
|------|------|
| 1 | iOS POST `/report` multipart → Mac HQSpeechServer |
| 2 | Mac 用 Apple Speech 辨識 → 產生 transcription |
| 3 | Mac 回呼 `onTranscriptionComplete` → 廣播摘要 |
| 4 | **Mac `forwardVoiceResult()` → TCP :9000 轉發文字** |
| 5 | **Mac `forwardReportToBackend()` → HTTP POST 到 Windows :8003/report 原始音訊** |
| 6 | Windows Whisper 辨識 + 入 DB + 報告 |

### 語音轉錄（HQSpeechServer :8003）

| 步驟 | 流程 |
|------|------|
| 1 | iOS POST `/transcribe` multipart → Mac HQSpeechServer |
| 2 | Mac 用 Apple Speech 辨識 → 回傳 JSON |
| 3 | 僅即時回應，不轉發到 Windows |

---

## 四、UDP 語音廣播（:9001 / :9002）

| 元件 | Port | 用途 |
|------|------|------|
| iOS 發送 | →Mac :9001 | PTT 音訊封包 LGBD |
| iOS 接收 | :9002← | Mac 中繼後的音訊 |
| Mac UDPAudioServer | :9001 | 接收 + 中繼到所有其他 iOS |
| Mac 靜音偵測 | — | 靜音後送 Apple Speech 辨識 |

**UDP 音訊純 Mac 中繼，不送 Windows udp_server**（頻寬與延遲考量）。語音辨識結果透過 TCP 9000 轉發文字。

---

## 五、資料庫 Schema（Windows 新增表）

### `status_reports`（裝置狀態記錄）

```sql
CREATE TABLE IF NOT EXISTS status_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT,
    device_id TEXT,
    battery INTEGER,
    ble_connected INTEGER,
    data_json TEXT          -- 完整 JSON 快照
);
```

### `chats`（聊天記錄）

```sql
CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT,
    device_id TEXT,
    sender_name TEXT,
    content TEXT
);
```

### 通用事件（使用既有 `system_events` 表）

`hazard_report` / `reinforcement_request` / `reinforcement_reply` / `sos` / `sos_cancel` / `quick_status` / `task_update` / `photo_alert` 統一存入 `system_events`，以 `event_type` 區分。

---

## 六、開發準則

### 6.1 新增 iOS 功能的通訊規範

1. iOS 所有網路呼叫**必須指向 Mac HQ IP**（從 Bonjour `_linkguard._tcp` 取得）
2. 禁止在 iOS 程式碼中寫入 Windows IP 或 port
3. 新增 msgType 時必須同時：
   - 在 `HQCommandServer.handleWiFiMessage` 加入 case
   - 在 `HQBackendBridge` 加入 `forward*()` 方法
   - 在 `HQCommandServer` 的對應 case 中呼叫 `backendBridge?.forward*()`
   - 在 `tcp_server.py#handle_message` 加入對應 handler

### 6.2 Mac-only 離線模式保障

以下功能在無 Windows 連線時仍可運作：

| 功能 | 離線可用 | 說明 |
|------|---------|------|
| 傷員回報 | ✅ | Mac 本地記錄 |
| 聊天 | ✅ | Mac 中繼 iOS ↔ iOS |
| 照片上傳 | ✅ | Mac 本地存儲 |
| 語音廣播 PTT | ✅ | Mac UDP 中繼 |
| 語音辨識 | ✅ | Apple Speech 本地辨識 |
| AI 決策 | ⚠️ | 需 Windows qwen_server |
| 氣象資料 | ❌ | 需 Windows pws_fetcher |
| PDF 報告 | ❌ | 需 Windows report_generator |
| 翻譯 | ⚠️ | 需 Ollama（Mac 本地或 Windows） |

### 6.3 HQBackendBridge 轉發方法清單

所有 forward 方法遵循統一簽章 `forward*(data: [String: Any], deviceId: String)`，內部呼叫 `sendToBackend(type:data:deviceId:)`。

二進位檔案轉發（照片/音訊）使用 HTTP multipart POST：
- `forwardPhotoToBackend(photoData: Data, metadata: [String: String])` → Windows :8004/photo
- `forwardReportToBackend(audioData: Data, metadata: [String: String])` → Windows :8003/report

### 6.4 通訊鏈路驗證檢查表

對每個 iOS 功能，確認以下鏈路完整：

- [ ] iOS → Mac TCP 8930（`WiFiMessage { msgType, payload }`）
- [ ] Mac 本地處理（UI 更新、中繼廣播、timeline 記錄）
- [ ] Mac → Windows TCP 9000（`{ type, data, device_id, timestamp }`）
- [ ] Windows handler 存 DB + 回應 ack
- [ ] Windows → Mac → iOS 反向通知（若有）

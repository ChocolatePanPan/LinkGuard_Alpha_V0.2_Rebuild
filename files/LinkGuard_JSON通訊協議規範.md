# LinkGuard — 統一 JSON 通訊協議規範

> 含電台功能、完整數據流定義、WiFiMessage 清單

新竹高工 × 新竹數位實中 ｜ 科展展示版本 2026

---

## 一、系統數據流總覽

### 1.1 主要數據流（13 條）

| # | 數據流 | 來源 | 目標 | 協議 |
|---|--------|------|------|------|
| 1 | 傷員回報流 | 手機 APP | tcp_server → qwen_server | TCP |
| 2 | 語音廣播流 | 手機 APP | udp_server → 所有裝置 | UDP |
| 3 | 語音轉錄流 | 手機 APP / udp_server | whisper_server → tcp_server | HTTP POST |
| 4 | 固定會報流 | 手機 APP | http_server → SQLite → 儀表板 | HTTP POST |
| 5 | 氣象數據流 | pws_fetcher | qwen_server → tcp_server | 內部函式 |
| 6 | LoRa 節點流 | mqtt_broker | → 儀表板 | MQTT → 內部 |
| 7 | 決策推播流 | qwen_server | tcp_server → 所有裝置 | TCP |
| 8 | GPS 位置流 | 手機 APP | tcp_server → 儀表板 | TCP |
| 9 | 指揮命令流 | HQ App | → 前線裝置 | TCP (WiFi) |
| 10 | 裝置狀態流 | 前線裝置 | → HQ App | TCP (WiFi) |
| 11 | 聊天訊息流 | 雙向 | HQ ↔ 前線裝置 | TCP (WiFi) |
| 12 | 電台控制流 | 手機 APP | tcp_server → 所有裝置 | TCP |
| 13 | USAR 指揮鏈流 | UCC / Sector / Worksite / Squad Leader | HQ ↔ 前線裝置 | TCP (WiFi) |

---

## 二、基礎封包格式

### 2.1 基礎封包 (Python 後端 ↔ 裝置)

所有 TCP 訊息統一使用以下結構，以換行符 `\n` 分隔封包：

```json
{
  "type": "<訊息類型>",
  "device_id": "<裝置ID>",
  "timestamp": "<ISO 8601 時間戳>",
  "data": { ... }
}
```

| 欄位 | 型別 | 範例 | 說明 |
|------|------|------|------|
| `type` | string | `"patient"` | 訊息類型識別碼 |
| `device_id` | string | `"RT-A3F"` | 發送者裝置 ID |
| `timestamp` | string | `"2026-04-06T14:30:00+08:00"` | ISO 8601 含時區 |
| `data` | object | `{...}` | 訊息內容（結構因 type 而異） |

### 2.2 WiFiMessage 封包 (HQ ↔ 前線裝置)

```json
{
  "msgType": "<訊息類型>",
  "deviceID": "<發送方裝置ID，可選>",
  "payload": "<JSON 字串化的內容>"
}
```

| 欄位 | 型別 | 說明 |
|------|------|------|
| `msgType` | string | 訊息類型（如 `"command"`, `"status_report"`, `"chat_message"`） |
| `deviceID` | string | 發送方裝置 ID；HQ 可省略，前線裝置建議帶入 |
| `payload` | string | JSON 編碼的字串（需二次解碼） |

### 2.3 格式正規化

`tcp_server.py` 的 `normalize_message()` 函式統一兩種格式：
- 收到 `{msgType, payload}` → 解碼 payload 字串，轉換為 `{type, data, device_id, timestamp}`
- 收到 `{type, data, ...}` → 直接使用

---

## 三、傷員回報流

### 3.1 傷員資料封包（手機 APP → tcp_server）

```json
{
  "type": "patient",
  "device_id": "RT-A3F",
  "timestamp": "2026-04-06T14:30:00+08:00",
  "data": {
    "id": "P1712345678",
    "breathing_rate": 20,
    "capillary_refill": 1.5,
    "can_follow_commands": true,
    "location": "三樓西側",
    "gps": { "lat": 24.8038, "lon": 120.9688 },
    "notes": "清醒，能溝通"
  }
}
```

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `id` | string | ✅ | 傷員 ID（格式 `P{timestamp}`） |
| `breathing_rate` | int | ✅ | 呼吸次數/分，`-1` = 無呼吸 |
| `capillary_refill` | float | ✅ | 微血管回填秒數，`-1` = 無脈搏 |
| `can_follow_commands` | bool | ✅ | 能否遵從指令 |
| `location` | string | ✅ | 文字位置描述 |
| `gps` | object | ❌ | GPS 座標 `{lat, lon}` |
| `notes` | string | ❌ | 備註 |

### 3.2 START 檢傷分類結果

```json
{ "priority": "紅色", "reason": "呼吸大於30次/分（呼吸過速）" }
```

| priority | 條件 |
|----------|------|
| `黑色` | `breathing_rate == -1` |
| `紅色` | 呼吸 >30、回填 >2s 或 -1、無法遵從指令 |
| `綠色` | 三項檢查正常 |

### 3.3 tcp_server 確認回覆

```json
{
  "type": "ack",
  "device_id": "server",
  "timestamp": "...",
  "data": { "received": "patient", "queue_size": 3 }
}
```

---

## 四、語音廣播流

### 4.1 UDP 封包結構（手機 APP → udp_server，二進位格式）

```
┌──────────┬─────────┬──────────┬──────────┬─────────────┬──────────────┐
│ Magic    │ DevID   │ Device   │ Sequence │ Timestamp   │ Audio Data   │
│ 4 bytes  │ Len 2B  │ ID (var) │ 4 bytes  │ 8 bytes(ms) │ (variable)   │
└──────────┴─────────┴──────────┴──────────┴─────────────┴──────────────┘
```

| 欄位 | 位元組 | 格式 | 說明 |
|------|--------|------|------|
| Magic | 4 | `0x4C474244` ("LGBD") | 封包識別碼 |
| DevID Len | 2 | uint16 BE | 裝置 ID 長度 |
| Device ID | N | UTF-8 | 裝置 ID 字串 |
| Sequence | 4 | uint32 BE | 封包序號（防重複） |
| Timestamp | 8 | uint64 BE | 毫秒時間戳 |
| Audio Data | 剩餘 | PCM 16bit | 16kHz 單聲道 signed PCM |

### 4.2 電台控制封包（手機 APP → tcp_server）

```json
{
  "type": "radio_control",
  "device_id": "RT-A3F",
  "timestamp": "...",
  "data": { "action": "start", "sender_name": "小王" }
}
```

| action | 說明 |
|--------|------|
| `"start"` | PTT 按下，開始廣播 |
| `"stop"` | PTT 放開，結束廣播 |

**別名**：`voice_broadcast` 與 `radio_control` 等效（tcp_server 同時處理）。

### 4.3 廣播通知（tcp_server → 所有裝置）

```json
{
  "type": "voice_broadcast_rx",
  "device_id": "server",
  "timestamp": "...",
  "data": { "sender_id": "RT-A3F", "sender_name": "小王", "action": "start" }
}
```

---

## 五、語音轉錄流

### 5.1 轉錄請求（POST `/transcribe` :8002）

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `file` | binary | ✅ | WAV 或 M4A 音訊檔 |
| `source` | string | ❌ | `"broadcast"` / `"report"`（預設 `"broadcast"`） |
| `sender_id` | string | ❌ | 發送者 ID（預設 `"unknown"`） |

### 5.2 轉錄回應

```json
{ "text": "已發現受困者在三樓西側", "language": "zh", "duration": 3.45 }
```

### 5.3 轉錄結果轉送（whisper_server → tcp_server）

```json
{
  "type": "voice_result",
  "device_id": "whisper-server",
  "timestamp": "...",
  "data": {
    "text": "已發現受困者在三樓西側",
    "language": "zh",
    "duration": 3.45,
    "source": "broadcast",
    "sender_id": "RT-A3F"
  }
}
```

---

## 六、固定會報流

### 6.1 會報上傳（POST `/report` :8003）

| 欄位 | 型別 | 必填 |
|------|------|------|
| `audio` | binary | ✅ |
| `device_id` | string | ✅ |
| `sender_name` | string | ✅ |
| `location_lat` | float | ❌ |
| `location_lon` | float | ❌ |
| `location_desc` | string | ❌ |
| `patients_snapshot` | string (JSON) | ❌ |
| `weather_snapshot` | string (JSON) | ❌ |
| `timestamp` | string | ❌ |

### 6.2 會報回應

```json
{
  "status": "ok",
  "report_id": "RPT-20260406-001",
  "transcription": "已發現受困者在三樓西側",
  "timestamp": "2026-04-06T14:30:01+08:00"
}
```

### 6.3 會報摘要推播（tcp_server → 所有裝置）

```json
{
  "type": "report_summary",
  "device_id": "http-server",
  "timestamp": "...",
  "data": {
    "report_id": "RPT-20260406-001",
    "sender_name": "小王",
    "transcription": "已發現受困者在三樓西側",
    "location_desc": "三樓西側",
    "patients_count": 2,
    "weather": { "temperature": 28.5, "humidity": 75.0, "wind_speed": 5.2, "rainfall": 0.0 },
    "audio_url": "http://{local_ip}:8003/audio/RPT-20260406-001"
  }
}
```

---

## 七、氣象數據流

### 7.1 氣象推播（tcp_server → 所有裝置，每 5 分鐘）

```json
{
  "type": "weather_update",
  "device_id": "server",
  "timestamp": "...",
  "data": {
    "station_id": "C0A980",
    "temperature": 28.5,
    "humidity": 75.0,
    "wind_speed": 5.2,
    "rainfall": 0.0,
    "obs_time": "2026-04-06 12:00"
  }
}
```

---

## 八、LoRa 節點流

### 8.1 MQTT 節點狀態（Topic: `linkguard/nodes/{node_id}`）

```json
{
  "node_id": "HQ-1",
  "rssi": -75,
  "snr": 8.5,
  "battery": 92,
  "location": { "lat": 24.8038, "lon": 120.9688 },
  "pdr": 95,
  "timestamp": "2026-04-06T14:30:00Z"
}
```

### 8.2 節點狀態推播（tcp_server → 裝置，每 60 秒）

```json
{
  "type": "node_status",
  "device_id": "server",
  "timestamp": "...",
  "data": {
    "nodes": [
      { "node_id": "HQ-1", "rssi": -75, "battery": 92, "location": {...}, "online": true, "last_seen": "..." }
    ]
  }
}
```

---

## 九、決策推播流

### 9.1 決策生成請求（tcp_server → qwen_server POST `/generate`）

```json
{
  "voice_text": "已發現受困者在三樓西側，持續進行搜救",
  "patients": [
    { "id": "傷員1", "location": "A區", "breathing_rate": -1, "capillary_refill": 0.0, "can_follow_commands": false }
  ],
  "weather": { "temperature": 28.5, "humidity": 75.0, "wind_speed": 5.2, "rainfall": 0.0 },
  "resources": ""
}
```

### 9.2 決策回應

```json
{
  "decision": "【優先處置】...\n【資源調配】...\n【注意事項】...\n【與上次決策的差異】...",
  "patients": [
    { "id": "傷員1", "breathing_rate": -1, "capillary_refill": 0.0, "can_follow_commands": false, "priority": "黑色", "reason": "無呼吸" }
  ]
}
```

### 9.3 決策推播（tcp_server → 所有裝置）

```json
{
  "type": "decision",
  "device_id": "server",
  "timestamp": "...",
  "data": {
    "decision": "【優先處置】...",
    "patients": [ ... ],
    "weather": { ... },
    "trigger": "patient"
  }
}
```

| trigger | 觸發來源 |
|---------|----------|
| `"patient"` | 收到新傷員資料 |
| `"voice"` | 收到語音轉錄結果 |
| `"manual"` | 手動觸發 |

---

## 十、指揮命令流 (HQ ↔ 前線)

### 10.1 WiFiCommand（HQ → 前線裝置）

**WiFiMessage 外層**：
```json
{ "msgType": "command", "payload": "<JSON string>" }
```

**payload 解碼後結構**：
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "search",
  "priority": 0,
  "title": "搜索 B 區 3F",
  "detail": "請前往 B 區 3 樓西側走廊進行生命跡象掃描",
  "sender": "HQ-Alpha",
  "timestamp": 1712345678.0
}
```

| type | 說明 |
|------|------|
| `search` | 搜索 |
| `standby` | 待命 |
| `support` | 支援 |
| `report` | 回報 |
| `evacuation` | 撤離 |
| `medical` | 醫療 |
| `logistics` | 後勤 |
| `communication` | 通訊 |
| `alert` | 警報 |
| `statusReport` | 狀態回報 |
| `zoneAssignment` | 分區指派 |
| `hazardWarning` | 危險警告 |
| `briefingUpdate` | 會報更新 |
| `resourceRequest` | 資源請求 |
| `shiftChange` | 交班 |

| priority | 等級 | 行為 |
|----------|------|------|
| `0` | routine | 一般通知 |
| `1` | urgent | 震動提醒 |
| `2` | critical | 全螢幕覆蓋 + 持續震動 + 警報音 |

### 10.2 裝置狀態報告（前線 → HQ）

```json
{
  "msgType": "status_report",
  "payload": "{\"deviceID\":\"RT-A3F\",\"deptCode\":\"EMT\",\"battery\":85,\"bleConnected\":true,\"victims\":[{\"id\":\"VT-001\",\"heartRate\":92,\"battery\":75,\"rssi\":-65.0,\"isSOS\":true,\"isOnline\":true}],\"teamMembers\":[{\"id\":\"RT-B2E\",\"deptCode\":\"EMT\",\"battery\":60,\"rssi\":-70.0,\"isOnline\":true,\"victimCount\":2}],\"sosCount\":1,\"timestamp\":1712345678.0}"
}
```

### 10.3 完整 WiFiMessage msgType 清單

| msgType | 方向 | 說明 |
|---------|------|------|
| `command` | HQ → Field | 指揮命令 |
| `status_report` | Field → HQ | 裝置狀態報告 |
| `chat_message` | 雙向 | 聊天訊息 |
| `disaster_update` | HQ → Field | 災害狀態更新 |
| `personnel_assignment` | HQ → Field | 人員配置 |
| `pws_alert` | HQ → Field | 公開預警訊息 |
| `briefing` | HQ → Field | 會報 |
| `personal_notification` | HQ → Field | 個人通知 |
| `quick_status` | Field → HQ | 快速狀態回報 |
| `task_assignment` | HQ → Field | 任務指派 |
| `task_update` | Field → HQ | 任務進度更新 |
| `timer_sync` | HQ → Field | 倒數計時同步 |
| `timer_cancel` | HQ → Field | 取消倒數計時 |
| `hazard_report` | 雙向 | 危險標記 |
| `reinforcement_request` | Field → HQ → Field | 增援請求 |
| `reinforcement_reply` | Field → HQ → Field | 增援回覆 |
| `decision` | HQ → Field | AI 指揮決策 |
| `report_summary` | HQ → Field | 會報摘要 |
| `radio_control` | Field → HQ → Field | 電台 PTT 控制 |
| `patient` | Field → tcp_server | 傷員回報 |
| `location` | Field → tcp_server | GPS 位置 |
| `ping` / `pong` | 雙向 | 心跳 |
| `stats_update` | Backend → HQ → Field | 即時統計推播 |
| `resource_update` | Backend → HQ → Field | 資源變動推播 |
| `photo_alert` | Backend → HQ → Field | 照片上傳通知 |
| `voice_broadcast_rx` | Backend → HQ → Field | 語音廣播通知 |
| `translate_request` | Field → Backend | 翻譯請求 |
| `text_broadcast` | Field → Backend → Field | 文字廣播 |
| `message_ack` | Field → HQ | 訊息確認收到 |
| `hello` | Field → HQ | 連線握手（含 role 判斷 field_unit / hq_peer） |
| `usar_role_assignment` | UCC/HQ → Field | USAR 角色、分區、工作點與小隊 scope 派令 |
| `usar_worksite_upsert` | UCC/Sector/Worksite → HQ → Field | 工作場地建立或更新 |
| `usar_worksite_assignment` | UCC/Sector → HQ → Field | 工作場地指派 |
| `usar_squad_task` | UCC/Sector/Worksite → HQ → Squad Leader | 小隊任務下發 |
| `usar_squad_status` | Squad Leader → HQ → UCC/Sector/Worksite | 小隊狀態回報 |
| `usar_asr_observation` | Worksite/Squad Leader → HQ → UCC/Sector | ASR 觀察與建議 |
| `usar_hazard_report` | 任一角色 → HQ → 相關角色 | USAR 危害旗標 |
| `usar_resource_request` | Sector/Worksite/Squad Leader → HQ/UCC | USAR 支援與資源請求 |
| `usar_marking_update` | Worksite/Squad Leader → HQ → 相關角色 | RCM/場地標記更新 |
| `usar_medical_update` | Medical/Squad Leader → HQ → 相關角色 | 傷患後送與醫療狀態 |
| `usar_operational_log` | 任一角色 → HQ → 相關角色 | 作戰紀錄與審計日誌 |

### 10.4 USAR 指揮鏈封包（UCC → 小隊長）

USAR 指揮鏈沿用 WiFiMessage 外層；`msgType` 必須是 `usar_*`，`payload` 解碼後為 `USARWirePayload`。`payloadJSON` 再解碼成對應的 typed payload，例如 `USARSquadTaskPayload` 或 `USARSquadStatusPayload`。

```json
{
  "msgType": "usar_squad_task",
  "deviceID": "UCC-01",
  "payload": "{\"version\":1,\"messageID\":\"USAR-001\",\"messageType\":\"usar_squad_task\",\"incidentID\":\"INC-260506-HC\",\"originRole\":\"uccOperations\",\"originID\":\"UCC-01\",\"targetRole\":\"squadLeader\",\"targetIDs\":[\"SQ-3\"],\"timestamp\":1712345678,\"payloadJSON\":\"{...}\"}"
}
```

`USARWirePayload` 欄位：

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `version` | int | ✅ | USAR 協議版本，目前為 `1` |
| `messageID` | string | ✅ | 去重與審計用訊息 ID |
| `messageType` | string | ✅ | 必須與外層 `msgType` 相同 |
| `incidentID` | string | ✅ | 事件 ID |
| `originRole` | string | ✅ | 來源角色，例如 `uccOperations`, `sectorCommander`, `worksiteManager`, `squadLeader` |
| `originID` | string | ✅ | 來源人員、裝置或節點 ID |
| `targetRole` | string | ❌ | 目標角色；空值代表廣播或依 `targetIDs` 路由 |
| `targetIDs` | string[] | ❌ | 目標裝置、人員、小隊或 HQ peer ID |
| `timestamp` | number/date | ✅ | 產生時間 |
| `payloadJSON` | string | ✅ | typed payload 的 JSON 字串 |

typed payload 對應表：

| msgType | payloadJSON 解碼型別 | 主要內容 |
|---------|----------------------|----------|
| `usar_role_assignment` | `USARRoleAssignmentPayload` | `scope`, `assignedDeviceID`, `instructions` |
| `usar_worksite_upsert` | `USARWorksiteUpsertPayload` | `worksite`, `zones`, `currentASR` |
| `usar_worksite_assignment` | `USARWorksiteAssignmentPayload` | `sector`, `worksite`, `assignedTeamIDs`, `instructions` |
| `usar_squad_task` | `USARSquadTaskPayload` | `task`, `worksite` |
| `usar_squad_status` | `USARSquadStatusPayload` | `status`, `relatedTask` |
| `usar_asr_observation` | `USARASRObservationPayload` | `assessment`, `suggestedWorksiteUpdate` |
| `usar_hazard_report` | `USARHazardReportPayload` | `hazard` |
| `usar_resource_request` | `USARResourceRequestPayload` | `request` |
| `usar_marking_update` | `USARMarkingUpdatePayload` | `marking` |
| `usar_medical_update` | `USARMedicalUpdatePayload` | `transfer` |
| `usar_operational_log` | `USAROperationalLogPayload` | `log` |

---

## 十一、GPS 位置流

### 11.1 位置更新（手機 APP → tcp_server）

```json
{
  "type": "location",
  "device_id": "RT-A3F",
  "timestamp": "...",
  "data": {
    "lat": 24.8038,
    "lon": 120.9688,
    "accuracy": 5.0,
    "role": "rescue",
    "name": "小王"
  }
}
```

---

## 十二、照片回報流

### 12.1 照片上傳（POST `/photo` :8004）

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `photo` | binary | ✅ | 照片檔案 |
| `device_id` | string | ✅ | 裝置 ID |
| `sender_name` | string | ✅ | 發送者名稱 |
| `lat` | float | ❌ | 緯度 |
| `lon` | float | ❌ | 經度 |
| `caption` | string | ❌ | 照片說明 |

### 12.2 照片上傳通知（photo_server → tcp_server → 所有裝置）

```json
{
  "type": "photo_alert",
  "device_id": "server",
  "timestamp": "...",
  "data": {
    "photo_id": "...",
    "sender_name": "小王",
    "thumbnail_url": "http://{ip}:8004/thumb/{id}",
    "photo_url": "http://{ip}:8004/photo/{id}",
    "caption": "三樓西側走廊倒塌"
  }
}
```

---

## 十三、HQ BackendBridge 訊息對應表

HQ（macOS/Android）透過 BackendBridge 連接 Win11 tcp_server(:9000)：

### 發送方向（HQ → Backend）

| 訊息類型 | 用途 |
|---------|------|
| `ping` | 心跳（含 role=hq, name） |
| `request_decision` | 請求 AI 決策（帶 voice_text） |
| `patient` | 轉發傷員 JSON |
| `voice_result` | 轉發語音辨識結果 |

### 接收方向（Backend → HQ）

| 訊息類型 | 處理 |
|---------|------|
| `decision` | AI 決策結果 → 解析 PatientDecisionEntry 列表 |
| `weather` / `weather_update` | 氣象資料 → 轉為 PWSAlert |
| `pong` / `ack` | 心跳/確認回應 |
| `report_summary` | 會報摘要 → 中繼至前線 |
| `voice_broadcast_rx` | 語音廣播通知 → 中繼至前線 |
| `stats_update` | 即時統計 → 更新 HQ 狀態 |
| `resource_update` | 資源變動 → 更新 HQ 狀態 |
| `photo_alert` | 照片通知 → 更新照片牆 + 中繼至前線 |

---

## 十四、BLE 通訊協議

### 14.1 BLE UUID（Field 端）

| 用途 | UUID |
|------|------|
| Service | `4FAFC201-1FB5-459E-8FCC-C5C9C331914B` |
| 狀態通知 (Notify) | `BEB5483E-36E1-4688-B7F5-EA07361B26A8` |
| 命令寫入 (Write) | `BEB5483E-36E1-4688-B7F5-EA07361B26AB` |
| LoRa 命令 (Notify) | `BEB5483E-36E1-4688-B7F5-EA07361B26AC` |

### 14.2 韌體狀態 JSON（BLE Notify）

```json
{
  "id": "RT-A3F",
  "dept": "EMT",
  "bat": 85,
  "vbat": 3.92,
  "lvl": 3,
  "pair": "1234",
  "victims": [
    { "id": "VT-001", "hr": 92, "bat": 75, "rssi": -65, "sos": true, "online": true }
  ],
  "team": [
    { "id": "RT-B2E", "dept": "FD", "bat": 60, "rssi": -70, "vc": 2 }
  ]
}
```

### 14.3 BLE 命令（Write）

| 命令 | 格式 | 說明 |
|------|------|------|
| 設定部門 | `setdept:EMT` | EMT/FD/PD |
| 設定檔位 | `setlvl:3` | LoRa 檔位 0-8 |
| 設定配對碼 | `setpair:1234` | LoRa 配對碼 |
| 命令回執 | `cmd_ack:{cmdID}` | 通知韌體收到命令 |
| 增援請求 | `reinforce:{msg}\|{loc}` | 發送增援 |
| 增援回覆 | `rf_reply:{team}\|{JOIN/NAK}` | 回覆增援 |
| 團隊 Ping | `team_ping` | 發送團隊心跳 |

### 14.4 LoRa 命令轉發（Notify）

```json
{
  "cmd_id": "uuid",
  "type": "evacuation",
  "pri": 2,
  "title": "立即撤離",
  "detail": "偵測到餘震風險",
  "sender": "HQ-Alpha"
}
```

---

## 十五、串列通訊 (SerialManager)

**用途**：macOS USB 直連 Heltec 開發板

```
波特率：115200
格式：8-N-1

埠偵測篩選：usbserial*, usbmodem*, SLAB*, wchusbserial*, cu.*

命令：
├─ "STATUS"                              請求狀態 JSON
├─ "PING"                                Ping 測試
├─ "CMD:{cmdId}:{type}:{pri}:{title}:{detail}" 發送指揮命令
└─ 接收 "CMD_RX:{cmdId}:{type}:{pri}:{title}:{detail}:{sender}"
```

---

## 十六、數據流端到端追蹤

```
1. Patient Report:
   iOS/Android → WiFiMessage{patient} → HQ(:8930) → BackendBridge → tcp_server(:9000)
   → patient_queue → triage_START() → qwen_server(:8001)/generate
   → decision broadcast → BackendBridge → HQ → WiFiMessage{decision} → 前線

2. PTT Voice:
   iOS/Android → UDP:9001 (LGBD binary) → udp_server → whisper_server(:8002)
   → voice_result → tcp_server → broadcast → HQ → 前線

3. Briefing Report:
   iOS/Android → POST http://{host}:8003/report (multipart)
   → http_server → whisper_server → transcription
   → report_summary → tcp_server → broadcast → HQ → 前線

4. Photo:
   iOS → POST http://{host}:8004/photo (multipart)
   → photo_server → compress + thumbnail → photo_alert
   → tcp_server → broadcast → HQ → 前線

5. Weather:
   pws_fetcher → CWA OpenData API → tcp_server(每 300 秒)
   → weather_update broadcast → HQ → 轉為 PWSAlert → 前線

6. Stats:
   stats_server(:8005, 每 30 秒) → stats_update → tcp_server → broadcast
   → BackendBridge → HQ

7. Resources:
   resource_server(:8006, 每次變動) → resource_update → tcp_server → broadcast
   → BackendBridge → HQ

8. GPS Location:
   iOS/Android → WiFiMessage{location} → HQ → BackendBridge → tcp_server
   → linkguard_db.save_location()

9. Command:
   HQ → WiFiMessage{command} → 前線（可選 broadcast 或 selected targets）

10. USAR Command Chain:
  UCC/HQ 指派裝置角色 → WiFiMessage{usar_role_assignment} → Field role shell
  → UCC 建立/更新 Worksite → WiFiMessage{usar_worksite_upsert} → HQ → Sector/Worksite
  → Worksite 指派小隊任務 → WiFiMessage{usar_squad_task} → Squad Leader
  → Squad Leader 回報狀態/ASR/危害/資源 → WiFiMessage{usar_squad_status | usar_asr_observation | usar_hazard_report | usar_resource_request}
  → HQ `USAROperationStore` 去重與彙整 → UCC/Sector/Worksite 顯示更新
```


---

## 十七、三層 AI 架構協議擴充（Plan v2 / Phase A-C）

> 對應 `win11/dual_config.json`、`gemma4_server.py`、HQ Mac `HQGrandDashboardView`。
> 三層命名：`field` (Gemma4 e2b)、`hq_local` (Gemma4 e4b)、`hq_main` (Gemma4 26b a4b)。

### 17.1 Tier Routing（`/chat`）

POST `http://<gemma4_host>:8001/chat`：

`json
{
  "session_id": "field_RT-A3F",
  "message": "三樓有兩名傷患需擔架",
  "role": "field"
}
`

回應新增 `tier` 與選用的 `next_tier_response`：

`json
{
  "ok": true,
  "tier": "field",
  "model": "gemma4:e2b",
  "reply": "...",
  "proposals": [ /* AIProposal[] */ ],
  "next_tier_response": {
    "tier": "hq_local",
    "model": "gemma4:e4b",
    "reply": "升級後的詳細建議",
    "trigger": "auto_internal_escalate"
  }
}
`

| `session_id` 前綴 | 預設 tier | 自動升級規則 |
|---|---|---|
| `field_*`    | field    | 偵測 `ESCALATE`/低信心 → 同 host 升 e4b（`next_tier_response`） |
| `hq_*`       | hq_local | 由 HQ 操作員手動升 `hq_main` |
| `main_*`     | hq_main  | 不再升級 |

### 17.2 AI 主機健康度 `GET /ai/health`

`json
{
  "hosts": [
    {"name": "host_a", "models": ["gemma4:26b-a4b"], "ollama_ok": true, "queue": 0, "errors_5min": 0},
    {"name": "host_b", "models": ["gemma4:e2b", "gemma4:e4b"], "ollama_ok": true, "queue": 1, "errors_5min": 0}
  ],
  "tier_routing": {"field": "host_b", "hq_local": "host_b", "hq_main": "host_a"}
}
`

HQ 大儀表板每 10 秒輪詢一次。

### 17.3 AI 提案／自主下令（16 類）

提案物件 `AIProposal`（出現在 `/chat` 回應的 `proposals` 與 `/ai/command/list`）：

`json
{
  "id": "AIP-153021-3",
  "type": "dispatch",
  "priority": 2,
  "title": "派遣 RT-A3F 前往三樓",
  "detail": "...",
  "targets": ["RT-A3F"],
  "rationale": "兩名傷患待救",
  "timestamp": "2026-04-06T15:30:21+08:00",
  "mode": "auto",
  "countdown_sec": 5,
  "require_human_double_confirm": false
}
`

| `mode` | 行為 |
|---|---|
| `auto`   | 5 秒倒數後自動 dispatch；HQ 可在倒數內按取消 |
| `manual` | 必須由 HQ 按執行才會下發 |

| `require_human_double_confirm` | 適用 type | 行為 |
|---|---|---|
| true | `emergency_evacuation`、`zone_lockdown` | 即使 `auto` 也須二次確認 |

#### 16 類指令對照

| type | mode | double_confirm |
|---|---|---|
| dispatch                   | auto   | false |
| status_check               | auto   | false |
| escalate_to_main           | auto   | false |
| medical_priority_change    | auto   | false |
| resource_relocate          | auto   | false |
| recall                     | auto   | false |
| checkpoint                 | auto   | false |
| alert                      | manual | false |
| medical                    | manual | false |
| resource                   | manual | false |
| personnel                  | manual | false |
| evacuate                   | manual | false |
| force_broadcast            | manual | false |
| task_order                 | manual | false |
| emergency_evacuation       | manual | true  |
| zone_lockdown              | manual | true  |

### 17.4 AI 提案管理端點

| 方法 | 路徑 | 用途 |
|---|---|---|
| GET  | `/ai/command/list`                  | 列出所有待審/進行中提案 |
| POST | `/ai/command/propose`               | 由 HQ 或自動規則手動建立提案 |
| POST | `/ai/command/auto_dispatch`         | 立即執行（body: `{"id": "AIP-..."}`） |
| POST | `/ai/command/cancel/{id}`           | 取消倒數中的自動提案 |
| GET  | `/ai/models`                        | 列出可用模型清單 |

執行後伺服器寫入 `linkguard_db.events`，事件類型：`ai_proposal`、`ai_command_dispatched`、`ai_command_cancelled`。

### 17.5 回報整型化 `POST /report/formalize`

iOS Field App 用 `FieldAIReportView` 呼叫，後端固定走 `field` tier (gemma4:e2b)。

`json
// request
{ "report_type": "patient", "raw_text": "三樓兩個傷患要擔架" }

// response
{
  "ok": true,
  "tier": "field",
  "model": "gemma4:e2b",
  "formalized": {
    "report_type": "patient",
    "location": "三樓",
    "patient_count": 2,
    "severity": "中傷",
    "resources_needed": ["擔架x2"],
    "hazards": [],
    "request_action": "派擔架隊"
  },
  "raw_text": "三樓兩個傷患要擔架"
}
`

`report_type` 支援：`general` / `patient` / `resource` / `hazard`。

### 17.6 升級觸發廣播（TCP 9000）

當 backend 偵測升級事件，會以原 TCP 基礎封包格式廣播給已連線的 HQ：

`json
{
  "type": "escalation_trigger",
  "device_id": "gemma4_server",
  "timestamp": "2026-04-06T15:30:21+08:00",
  "data": {
    "request_id": "REQ-abc123",
    "from_tier": "field",
    "to_tier": "hq_local",
    "status": "queued",
    "queue_position": 1,
    "estimated_wait_sec": 1.8
  }
}
`

HQ Mac `HQBackendBridge.latestEscalationTrigger` 直接取此 payload。

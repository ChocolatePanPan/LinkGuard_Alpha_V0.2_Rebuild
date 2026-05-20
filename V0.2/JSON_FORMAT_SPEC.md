# LinkGuard 統一 JSON 格式規範文件

> 含電台功能完整數據流定義

新竹高工 × 新竹數位實中 ｜ 科展展示版本 2026

---

## 一、系統數據流總覽

LinkGuard 系統由五條主要數據流組成，所有模組間統一使用 JSON 格式傳輸。

### 1.1 主要數據流

| 數據流 | 來源 | 目標 | 協議 |
|--------|------|------|------|
| 傷員回報流 | 手機 APP | tcp_server → qwen_server | TCP |
| 語音廣播流 | 手機 APP | udp_server → 所有裝置 | UDP |
| 語音轉錄流 | 手機 APP / udp_server | whisper_server → tcp_server | HTTP POST |
| 固定會報流 | 手機 APP | http_server → SQLite → 儀表板 | HTTP POST |
| 氣象數據流 | pws_fetcher | qwen_server → tcp_server | 內部函式 |
| LoRa 節點流 | mqtt_broker | → 儀表板 | MQTT → 內部 |
| 決策推播流 | qwen_server | tcp_server → 所有裝置 | TCP |
| GPS 位置流 | 手機 APP | tcp_server → 儀表板 | TCP |
| 指揮命令流 | HQ App | → 前線裝置 | TCP (WiFi) |
| 裝置狀態流 | 前線裝置 | → HQ App | TCP (WiFi) |
| 聊天訊息流 | 雙向 | HQ ↔ 前線裝置 | TCP (WiFi) |
| 電台控制流 | 手機 APP | tcp_server → 所有裝置 | TCP |

---

## 二、基礎封包格式

所有 TCP 訊息統一使用以下基礎結構，以換行符 `\n` 分隔封包。

### 2.1 基礎封包 (Python 後端 ↔ 裝置)

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

HQ 指揮通訊使用 `WiFiMessage` 包裝格式：

```json
{
  "msgType": "<訊息類型>",
  "payload": "<JSON 字串化的內容>"
}
```

| 欄位 | 型別 | 說明 |
|------|------|------|
| `msgType` | string | 訊息類型（如 `"command"`, `"status_report"`, `"chat_message"`） |
| `payload` | string | JSON 編碼的字串（需二次解碼） |

### 2.3 格式相容性

`tcp_server` 的 `normalize_message()` 函式負責統一兩種格式：

- 收到 `{msgType, payload}` → 轉換為 `{type, data, device_id, timestamp}`
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
    "gps": {
      "lat": 24.8038,
      "lon": 120.9688
    },
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

`qwen_server` 收到傷員資料後，經 `triage_START()` 計算優先級：

```json
{
  "priority": "紅色",
  "reason": "呼吸大於30次/分（呼吸過速）"
}
```

| priority | 說明 | 條件 |
|----------|------|------|
| `黑色` | 已死亡/無法救治 | `breathing_rate == -1` |
| `紅色` | 危急，立即處置 | 呼吸 >30、回填 >2s 或 -1、無法遵從指令 |
| `綠色` | 輕傷/可行走 | 三項檢查正常 |

### 3.3 tcp_server 確認回覆

```json
{
  "type": "ack",
  "device_id": "server",
  "timestamp": "2026-04-06T14:30:01+08:00",
  "data": {
    "received": "patient",
    "queue_size": 3
  }
}
```

---

## 四、語音廣播流

### 4.1 UDP 封包結構（手機 APP → udp_server）

二進位格式，**非 JSON**：

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

**行為**：`udp_server` 累積同一 `device_id` 的 PCM chunks，寂靜 2 秒後自動送 Whisper 轉錄。

### 4.2 電台控制封包（手機 APP → tcp_server）

```json
{
  "type": "radio_control",
  "device_id": "RT-A3F",
  "timestamp": "2026-04-06T14:30:00+08:00",
  "data": {
    "action": "start",
    "sender_name": "小王"
  }
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
  "timestamp": "2026-04-06T14:30:00+08:00",
  "data": {
    "sender_id": "RT-A3F",
    "sender_name": "小王",
    "action": "start"
  }
}
```

---

## 五、語音轉錄流

### 5.1 轉錄請求（udp_server / 手機 APP → whisper_server）

**Endpoint**: `POST http://<server>:8002/transcribe`

**Content-Type**: `multipart/form-data`

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `file` | binary | ✅ | WAV 或 M4A 音訊檔 |
| `source` | string | ❌ | 來源：`"broadcast"` / `"report"`（預設 `"broadcast"`） |
| `sender_id` | string | ❌ | 發送者 ID（預設 `"unknown"`） |

### 5.2 轉錄回應

```json
{
  "text": "已發現受困者在三樓西側",
  "language": "zh",
  "duration": 3.45
}
```

### 5.3 轉錄結果轉送（whisper_server → tcp_server）

Whisper 自動將結果以 TCP 送至 `tcp_server`：

```json
{
  "type": "voice_result",
  "device_id": "whisper-server",
  "timestamp": "2026-04-06T14:30:05+08:00",
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

### 6.1 會報上傳（手機 APP → http_server）

**Endpoint**: `POST http://<server>:8003/report`

**Content-Type**: `multipart/form-data`

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `audio` | binary | ✅ | M4A 音訊檔 |
| `device_id` | string | ✅ | 裝置 ID |
| `sender_name` | string | ✅ | 發送者名稱 |
| `location_lat` | float | ❌ | 緯度 |
| `location_lon` | float | ❌ | 經度 |
| `location_desc` | string | ❌ | 文字位置描述 |
| `patients_snapshot` | string | ❌ | JSON 字串化的傷員快照 |
| `weather_snapshot` | string | ❌ | JSON 字串化的氣象快照 |
| `timestamp` | string | ❌ | ISO 8601 時間戳 |

### 6.2 會報回應

```json
{
  "status": "ok",
  "report_id": "RPT-20260406-001",
  "transcription": "已發現受困者在三樓西側",
  "timestamp": "2026-04-06T14:30:01+08:00"
}
```

### 6.3 會報摘要推播（http_server → tcp_server → 所有裝置）

```json
{
  "type": "report_summary",
  "device_id": "http-server",
  "timestamp": "2026-04-06T14:30:01+08:00",
  "data": {
    "report_id": "RPT-20260406-001",
    "sender_name": "小王",
    "transcription": "已發現受困者在三樓西側",
    "location_desc": "三樓西側",
    "patients_count": 2,
    "weather": {
      "temperature": 28.5,
      "humidity": 75.0,
      "wind_speed": 5.2,
      "rainfall": 0.0,
      "timestamp": "2026-04-06 12:00"
    },
    "audio_url": "http://192.168.50.34:8003/audio/RPT-20260406-001"
  }
}
```

---

## 七、氣象數據流

### 7.1 氣象API取得（pws_fetcher → 內部）

`fetch_weather()` 回傳格式：

```json
{
  "temperature": 28.5,
  "humidity": 75.0,
  "wind_speed": 5.2,
  "rainfall": 0.0,
  "timestamp": "2026-04-06T12:00:00+08:00"
}
```

### 7.2 氣象推播（tcp_server → 所有裝置）

每 5 分鐘自動推播：

```json
{
  "type": "weather_update",
  "device_id": "server",
  "timestamp": "2026-04-06T14:30:00+08:00",
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

### 8.1 MQTT 節點狀態

**Topic**: `linkguard/nodes/{node_id}`

```json
{
  "node_id": "HQ-1",
  "rssi": -75,
  "snr": 8.5,
  "battery": 92,
  "location": {
    "lat": 24.8038,
    "lon": 120.9688
  },
  "pdr": 95,
  "timestamp": "2026-04-06T14:30:00Z"
}
```

| 欄位 | 型別 | 說明 |
|------|------|------|
| `node_id` | string | 節點 ID |
| `rssi` | int | 接收信號強度 (dBm) |
| `snr` | float | 信噪比 |
| `battery` | int | 電量百分比 |
| `location` | object | GPS 座標 `{lat, lon}` |
| `pdr` | int | 封包交付率 (%) |
| `timestamp` | string | ISO 8601 時間戳 |

### 8.2 節點狀態推播（tcp_server → 裝置）

每 60 秒聚合推播：

```json
{
  "type": "node_status",
  "device_id": "server",
  "timestamp": "2026-04-06T14:30:00+08:00",
  "data": {
    "nodes": [
      {
        "node_id": "HQ-1",
        "rssi": -75,
        "battery": 92,
        "location": { "lat": 24.8038, "lon": 120.9688 },
        "online": true,
        "last_seen": "2026-04-06T14:29:30Z"
      }
    ]
  }
}
```

---

## 九、決策推播流

### 9.1 Qwen 決策生成請求（tcp_server → qwen_server）

**Endpoint**: `POST http://localhost:8001/generate`

```json
{
  "voice_text": "已發現受困者在三樓西側，持續進行搜救",
  "patients": [
    {
      "id": "傷員1",
      "location": "A區",
      "breathing_rate": -1,
      "capillary_refill": 0.0,
      "can_follow_commands": false
    }
  ],
  "weather": {
    "temperature": 28.5,
    "humidity": 75.0,
    "wind_speed": 5.2,
    "rainfall": 0.0
  },
  "resources": ""
}
```

### 9.2 Qwen 決策回應

```json
{
  "decision": "【優先處置】立即搶救紅色傷患...\n【資源調配】...\n【注意事項】...\n【與上次決策的差異】...",
  "patients": [
    {
      "id": "傷員1",
      "breathing_rate": -1,
      "capillary_refill": 0.0,
      "can_follow_commands": false,
      "priority": "黑色",
      "reason": "無呼吸"
    }
  ]
}
```

### 9.3 決策推播（tcp_server → 所有裝置）

```json
{
  "type": "decision",
  "device_id": "server",
  "timestamp": "2026-04-06T14:30:10+08:00",
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

```json
{
  "msgType": "command",
  "payload": "{\"id\":\"UUID\",\"type\":\"search\",\"priority\":0,\"title\":\"搜索 B 區 3F\",\"detail\":\"...\",\"sender\":\"HQ-Alpha\",\"timestamp\":1712345678.0}"
}
```

**WiFiCommand 結構（payload 解碼後）**：

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
| `"search"` | 搜索命令 |
| `"standby"` | 待命命令 |
| `"support"` | 支援請求 |
| `"report"` | 回報要求 |
| `"evacuation"` | 撤離命令 |

| priority | 等級 |
|----------|------|
| `0` | routine（例行） |
| `1` | urgent（緊急） |
| `2` | critical（危急） |

### 10.2 裝置狀態報告（前線 → HQ）

```json
{
  "msgType": "status_report",
  "payload": "{...FieldStatusReport JSON...}"
}
```

**FieldStatusReport 結構**：

```json
{
  "deviceID": "RT-A3F",
  "deptCode": "EMT",
  "battery": 85,
  "bleConnected": true,
  "victims": [
    {
      "id": "VT-001",
      "heartRate": 92,
      "battery": 75,
      "rssi": -65.0,
      "isSOS": true,
      "isOnline": true
    }
  ],
  "teamMembers": [
    {
      "id": "RT-B2E",
      "deptCode": "EMT",
      "battery": 60,
      "rssi": -70.0,
      "isOnline": true,
      "victimCount": 2
    }
  ],
  "sosCount": 1,
  "timestamp": 1712345678.0
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

---

## 十一、GPS 位置流

### 11.1 位置更新（手機 APP → tcp_server）

```json
{
  "type": "location",
  "device_id": "RT-A3F",
  "timestamp": "2026-04-06T14:30:00+08:00",
  "data": {
    "lat": 24.8038,
    "lon": 120.9688,
    "accuracy": 10.5,
    "role": "EMT",
    "name": "RT-A3F"
  }
}
```

---

## 十二、聊天訊息

### 12.1 ChatMessage 結構

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "senderID": "RT-A3F",
  "senderName": "小王",
  "recipientID": null,
  "content": "已到達搜救區域",
  "timestamp": 1712345678.0,
  "isRead": false
}
```

| 欄位 | 說明 |
|------|------|
| `recipientID` | `null` 或空字串 = 廣播，指定對象 = 私訊 |

---

## 十三、BLE LoRa 韌體通訊

### 13.1 Field 端 BLE UUID

| 用途 | UUID |
|------|------|
| Service | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| TX (韌體 → APP) | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |

### 13.2 韌體狀態上報（JSON via BLE）

```json
{
  "bat": 85,
  "lvl": 3,
  "victims": [
    {
      "id": "VT-001",
      "hr": 92,
      "bat": 75,
      "rssi": -65,
      "sos": true,
      "online": true
    }
  ]
}
```

### 13.3 韌體命令（APP → 韌體 BLE 寫入）

| 命令 | 格式 | 說明 |
|------|------|------|
| 設定部門 | `setdept:EMT` | 設定節點所屬部門 |
| 設定層級 | `setlvl:3` | 設定節點監管等級 |
| 設定配對碼 | `setpair:1234` | 設定 LoRa 配對碼 |

### 13.4 LoRa 命令轉發（APP → 韌體 → LoRa）

```json
{
  "cmd_id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "evacuation",
  "pri": 2,
  "title": "立即撤離",
  "detail": "偵測到餘震風險",
  "sender": "HQ-Alpha"
}
```

---

## 十四、錯誤封包

### 14.1 錯誤回應（tcp_server → 裝置）

```json
{
  "type": "error",
  "device_id": "server",
  "timestamp": "2026-04-06T14:30:00+08:00",
  "data": {
    "code": "JSON_PARSE_ERROR",
    "message": "JSON 解析失敗"
  }
}
```

| code | 說明 |
|------|------|
| `JSON_PARSE_ERROR` | JSON 格式錯誤或未知 type |
| `QWEN_TIMEOUT` | Qwen 決策生成失敗 |

---

## 十五、服務 Port 總覽

| Port | 服務 | 協議 | 說明 |
|------|------|------|------|
| 8930 | HQCommandServer | TCP + Bonjour | WiFi 指揮通訊 |
| 9000 | tcp_server.py | TCP + Bonjour | 後端中樞聚合 |
| 9001 | udp_server.py | UDP | 語音廣播接收 |
| 8001 | qwen_server.py | HTTP | Qwen LLM 推理 |
| 8002 | whisper_server.py | HTTP | Whisper 語音轉錄 |
| 8003 | http_server.py | HTTP | 會報上傳與儲存 |
| 1883 | mqtt_broker.py | MQTT | LoRa 節點狀態 |

---

## 十六、Bonjour 服務發現

| 服務類型 | 名稱 | 用途 |
|----------|------|------|
| `_linkguard._tcp` | `LinkGuard-Command` | tcp_server 自動發現 |
| `_linkguard._tcp` | `LinkGuard-CMD` | HQ Command Server 發現 |

前線裝置透過 Bonjour 自動搜尋 `_linkguard._tcp` 服務，無需手動設定 IP。

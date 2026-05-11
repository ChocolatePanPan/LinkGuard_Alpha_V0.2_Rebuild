# LinkGuard — AI 災害救援指揮系統

## 系統架構規範

新竹高工 × 新竹數位實中 ｜ 科展展示版本 2026

---

## 一、系統總覽

### 1.1 硬體配置

| 裝置 | 角色 | 主要任務 |
|------|------|----------|
| 3080 主機 | 推理伺服器 | Qwen2.5 14B、START 評分、TCP、MQTT、PWS、備份 |
| 2060 筆電 | 語音辨識 | Whisper Large-v3、FastAPI |
| M2 Air | 指揮中心 | LinkGuardHQ macOS、31.5 吋外接顯示 |
| iPad Air M2 | 現場醫療站 | LinkGuard iPadOS 傷員列表 |
| iOS 手機 | 現場終端 | LinkGuard iOS 回報+電台 |
| Android 手機 | 現場終端 | LinkGuard Android 回報+電台 |
| RT-AX1800S | 區網骨幹 | 指揮站 WiFi、連接所有設備 |
| LoRa 節點 | 現場通訊 | 長距離廣播通訊（Heltec WiFi LoRa 32 V3） |

### 1.2 完整服務清單

| 服務 | 主機 | 埠口 | 協議 | 說明 |
|------|------|------|------|------|
| tcp_server | 3080 主機 | 9000 | TCP + Bonjour | 訊息聚合中樞 |
| qwen_server | 3080 主機 | 8001 | HTTP (FastAPI) | AI 決策引擎 + 翻譯 |
| whisper_server | 2060 筆電 | 8002 | HTTP (FastAPI) | 語音轉錄 |
| http_server | 3080 主機 | 8003 | HTTP (FastAPI) | 會報管理 + Web Dashboard |
| photo_server | 3080 主機 | 8004 | HTTP (FastAPI) | 照片上傳/管理 |
| stats_server | 3080 主機 | 8005 | HTTP (FastAPI) | 即時統計 |
| resource_server | 3080 主機 | 8006 | HTTP (FastAPI) | 資源管理 CRUD |
| udp_server | 3080 主機 | 9001 | UDP | 語音廣播接收 |
| mqtt_broker | 3080 主機 | 1883 | MQTT v5 | LoRa 節點狀態 |
| HQCommandServer | M2 Air | 8930 | TCP + Bonjour | HQ 指揮通訊 |
| HQSpeechServer | M2 Air | 8003 | TCP (NWListener) | Mac 本地語音辨識（Apple Speech） |
| HQPhotoServer | M2 Air | 8004 | TCP (NWListener) | Mac 本地照片伺服器 |
| HQ UDP Relay | M2 Air | 9001→9002 | UDP | 音訊中繼 |

### 1.3 系統架構圖

```
┌─────────────────────────────────────────────────────────────────┐
│                    WiFi 指揮層 (TCP 8930)                        │
│                                                                 │
│   ┌──────────────┐          ┌──────────────────────┐            │
│   │ linkguard    │◄────────►│ HQCommandServer      │            │
│   │ (Field iOS)  │ WiFi     │ (M2 Air macOS :8930) │            │
│   └──────────────┘ Command  │ Bonjour: _linkguard  │            │
│   ┌──────────────┐          │   ._tcp/LinkGuard-CMD│            │
│   │ linkguard    │◄────────►└──────────┬───────────┘            │
│   │ (Field Andr) │                     │                        │
│   └──────────────┘          ┌──────────┴───────────┐            │
│                             │ HQPeerClient         │            │
│   ┌──────────────┐          │ (Peer Sync —         │            │
│   │ Android HQ   │◄────────►│  hq_peer role)       │            │
│   │ (:8930 NSD)  │          └──────────────────────┘            │
│   └──────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
                              │ TCP 9000
┌─────────────────────────────┴───────────────────────────────────┐
│                  Python 後端層 (3080 主機)                        │
│                                                                 │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│   │tcp_server│  │qwen_serv │  │http_serv │  │udp_server│       │
│   │ :9000    │  │ :8001    │  │ :8003    │  │ :9001    │       │
│   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
│        │             │             │             │               │
│   ┌────┴────┐  ┌─────┴────┐  ┌────┴─────┐  ┌────┴────┐         │
│   │mqtt_brok│  │pws_fetch │  │whisper_s │  │photo_s  │         │
│   │ :1883   │  │(CWA API) │  │ :8002    │  │ :8004   │         │
│   └─────────┘  └──────────┘  └──────────┘  └─────────┘         │
│                                                                 │
│   ┌──────────┐  ┌──────────┐  ┌──────────────────────┐          │
│   │stats_s   │  │resource_s│  │ linkguard_db.py      │          │
│   │ :8005    │  │ :8006    │  │ data/linkguard.db    │          │
│   └──────────┘  └──────────┘  └──────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    LoRa 無線層 (長距離)                           │
│                                                                 │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐                  │
│   │ HQ Node  │◄──►│ Rescue   │◄──►│ Victim   │                  │
│   │ (912MHz) │    │ (910MHz) │    │ (910MHz) │                  │
│   └──────────┘    └──────────┘    └──────────┘                  │
│                                                                 │
│   BLE 近端：iOS/Android ◄──► Heltec LoRa 32 V3 (ESP32-S3)      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Mac-Only 獨立模式（無 Win11）                     │
│   HQSpeechServer(:8003) = 取代 whisper_server                   │
│   HQPhotoServer(:8004) = 取代 photo_server                      │
│   computeLocalStats() = 取代 stats_server                        │
│   computeLocalResources() = 取代 resource_server                 │
│   翻譯離線 fallback = 回傳「翻譯服務不可用」                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、Python 後端服務

### 2.1 tcp_server.py — TCP 聚合中樞（Port 9000）

> 接收所有前線裝置的訊息、聚合多來源數據、呼叫 AI 決策引擎、將結果推播給所有連線裝置。

**Bonjour 服務註冊**：
- 服務類型：`_linkguard._tcp.local.`
- 服務名稱：`LinkGuard-Command`

**訊息處理器**：

| 訊息類型 | 處理邏輯 |
|---------|---------|
| `ping` | 回傳 pong + 連線統計 |
| `patient` | 加入傷員佇列 → 觸發 AI 決策 |
| `location` | 更新裝置 GPS 位置 + 存入 `linkguard_db.save_location()` |
| `voice_result` | 更新語音文字 → 觸發 AI 決策 |
| `voice_broadcast` / `radio_control` | 中繼 PTT 控制 |
| `report_summary` | 中繼會報摘要到所有裝置 |
| `text_broadcast` | 中繼文字廣播 |
| `translate_request` | 中繼翻譯請求 |
| `message_ack` | 確認收到 |

**定時任務**：

| 定時器 | 週期 | 功能 |
|--------|------|------|
| `periodic_weather()` | 300 秒 | 推播氣象（type: `weather_update`） |
| `periodic_node_status()` | 60 秒 | 推播 LoRa 節點狀態（type: `node_status`） |

**格式正規化** `normalize_message()`：
- 收到 `{msgType, payload}` → 轉換為 `{type, data, device_id, timestamp}`
- 收到 `{type, data, ...}` → 直接使用

**AI 決策流程**：

```
1. 聚合：語音文字 + 傷員佇列 + 氣象資料
2. 對每名傷員執行 triage_START() 檢傷分類
3. format_for_llm() 生成傷員摘要
4. format_weather_for_llm() 生成氣象摘要
5. get_recent_decisions(5) 取得最近 5 筆歷史決策
6. 組合 system_prompt + user_prompt
7. ollama.chat() 生成決策
8. save_decision() 存入 SQLite
9. 推播決策結果給所有裝置
```

---

### 2.2 qwen_server.py — AI 決策引擎（Port 8001）

**模型配置**：

```
模型名稱：linkguard-qwen (Ollama 本機部署)
Ollama 主機：http://localhost:11434
執行參數：
  ├─ num_ctx: 4096      (上下文視窗)
  ├─ temperature: 0.3   (低溫度 → 一致性高)
  └─ num_gpu: 99        (全 GPU 加速)
```

**端點**：

| 端點 | 方法 | 功能 |
|------|------|------|
| `/generate` | POST | AI 決策生成 |
| `/translate` | POST | 醫療翻譯（context: medical） |

**System Prompt**：

```
你是災害救援指揮AI助理。

【START 檢傷分類標準】
步驟1 呼吸評估: 無呼吸(-1) → 黑色（已死亡，不急救，集中資源於紅色傷患）
步驟2 循環評估: 呼吸>30次/分 → 紅色；微血管回填>2秒或無脈搏(-1) → 紅色
步驟3 意識評估: 無法遵從指令 → 紅色
全部正常 → 綠色（輕傷/可行走）

根據歷史記錄和當前資訊生成新的指揮決策，避免重複已執行的指令。
輸出格式:
【優先處置】...
【資源調配】...
【注意事項】...
【與上次決策的差異】...
```

---

### 2.3 whisper_server.py — 語音轉錄（Port 8002）

**模型配置**：

```
模型：large-v3 (faster-whisper)
裝置：CUDA (GPU)
精度：float16
語言：zh (中文優先)
```

**端點**：

```
POST /transcribe
Content-Type: multipart/form-data
Fields:
  ├─ file: 音訊二進位 (WAV 或 M4A)
  ├─ source: "broadcast" | "report" (預設 "broadcast")
  └─ sender_id: 裝置 ID (預設 "unknown")

Response: { "text", "language", "duration" }
```

---

### 2.4 http_server.py — 會報管理（Port 8003）

**端點**：

| 端點 | 方法 | 功能 |
|------|------|------|
| `POST /report` | POST | 上傳語音會報（multipart/form-data） |
| `GET /audio/{report_id}` | GET | 回傳音訊檔案（Range Request 支援） |
| `GET /dashboard` | GET | **Web Dashboard 靜態頁面** |

**會報上傳欄位**：`audio`, `device_id`, `sender_name`, `location_lat`, `location_lon`, `location_desc`, `patients_snapshot`, `weather_snapshot`, `timestamp`

**會報 ID 格式**：`RPT-YYYYMMDD-NNN`（每日流水號 001 起算）

**會報處理流程**：

```
1. 接收音訊 + 附帶資料
2. 存音訊到 reports/audio/RPT-xxx.m4a
3. 送 Whisper 轉錄
4. 存入 SQLite reports.db
5. 推播會報摘要至 tcp_server → 所有裝置
```

**重試機制**：轉錄失敗 → 暫存 pending/ → 每 60 秒重試 → 最多 3 次

---

### 2.5 photo_server.py — 照片伺服器（Port 8004）

**端點**：

| 端點 | 方法 | 功能 |
|------|------|------|
| `POST /photo` | POST | 接收照片上傳（multipart/form-data） |
| `GET /photo/{id}` | GET | 取得原圖 |
| `GET /thumb/{id}` | GET | 取得 300×300 縮圖 |
| `GET /health` | GET | 健康檢查 |

**處理流程**：接收照片 → 壓縮至 1MB → 生成 300×300 縮圖 → 存 SQLite → 廣播 `photo_alert` 至 TCP 9000 → USB 備份

---

### 2.6 stats_server.py — 即時統計（Port 8005）

**端點**：

| 端點 | 方法 | 功能 |
|------|------|------|
| `GET /stats` | GET | 即時統計概況 |
| `GET /stats/history?hours=N` | GET | 歷史統計 |

**統計內容**：傷患分類（紅/黃/綠/黑）、人員統計（WiFi 裝置+LoRa 節點）、資源概況、通訊狀態、決策/照片數、事件持續時間

**推播**：每 30 秒推送 `stats_update` 至 TCP 9000

---

### 2.7 resource_server.py — 資源管理（Port 8006）

**端點**：

| 端點 | 方法 | 功能 |
|------|------|------|
| `GET /resources` | GET | 列出所有資源 |
| `POST /resources` | POST | 新增資源 |
| `PATCH /resources/{id}` | PATCH | 更新資源 |
| `POST /resources/{id}/deploy` | POST | 部署資源 |
| `POST /resources/{id}/return` | POST | 回收資源 |

**推播**：每次變動廣播 `resource_update` 至 TCP 9000

---

### 2.8 udp_server.py — 語音廣播接收（Port 9001）

**UDP 封包結構（二進位格式）**：

```
┌──────────┬─────────┬──────────┬──────────┬─────────────┬──────────────┐
│ Magic    │ DevID   │ Device   │ Sequence │ Timestamp   │ Audio Data   │
│ 4 bytes  │ Len 2B  │ ID (var) │ 4 bytes  │ 8 bytes(ms) │ (variable)   │
└──────────┴─────────┴──────────┴──────────┴─────────────┴──────────────┘
```

| 欄位 | 格式 | 說明 |
|------|------|------|
| Magic | `0x4C474244` ("LGBD") | 封包識別碼 |
| DevID Len | uint16 BE | 裝置 ID 長度 |
| Device ID | UTF-8 | 裝置 ID 字串 |
| Sequence | uint32 BE | 封包序號（防重複） |
| Timestamp | uint64 BE | 毫秒時間戳 |
| Audio Data | PCM 16bit | 16kHz 單聲道 signed PCM |

**行為邏輯**：
1. 接收 UDP 封包 → 驗證 Magic → 解析標頭
2. 去重：維護 `_seq_sets[device_id]`
3. 累積 PCM chunks 至 `audio_buffer[device_id]`
4. 超過 2 秒無新封包 → 廣播結束
5. PCM → WAV 轉換 → 送 Whisper 轉錄
6. 清空 buffer

---

### 2.9 mqtt_broker.py — LoRa 節點狀態（Port 1883）

**訂閱主題**：`linkguard/nodes/#`

**全域狀態字典**：`node_status[node_id]` 持續更新，供 tcp_server 定時推播。

---

### 2.10 pws_fetcher.py — 中央氣象署 API

**API**：`https://opendata.cwa.gov.tw/api/v1/rest/datastore/O-A0001-001`

**測站代碼**：C0A980

**回傳欄位**：`temperature`, `humidity`, `wind_speed`, `rainfall`, `timestamp`

**LLM 格式化**：`"氣溫:28.5°C | 濕度:75% | 風速:5.2m/s | 雨量:0mm"`

---

### 2.11 START 檢傷分類演算法 (triage.py / start_triage.py)

```
函式：triage_START(patient) → {priority, reason}

決策樹（順序評估）：

  Step 1: 呼吸評估
  ├─ breathing_rate == -1 → 黑色「無呼吸」
  │
  Step 2: 循環評估
  ├─ breathing_rate > 30 → 紅色「呼吸大於30次/分」
  ├─ capillary_refill > 2 或 == -1 → 紅色「微血管回填>2秒或無橈動脈脈搏」
  │
  Step 3: 意識評估
  ├─ can_follow_commands == false → 紅色「無法遵從指令」
  │
  Step 4: 全部正常
  └─ → 綠色「三項檢查正常」

優先級：
  黑色 = 已死亡（不急救，集中資源於紅色傷患）
  紅色 = 危急（立即處置）
  綠色 = 輕傷/可行走
```

---

### 2.12 linkguard_db.py — 統一資料庫

**資料庫**：`data/linkguard.db`（SQLite WAL 模式）

**8 張表**：

| 表名 | 用途 | 主要欄位 |
|------|------|---------|
| `decisions` | AI 決策記錄 | timestamp, voice_text, patients_summary, weather_summary, decision_text, trigger_type |
| `patients` | 傷員資料 | patient_id UNIQUE, breathing_rate, capillary_refill, can_follow_commands, priority, reason, gps |
| `locations` | 裝置 GPS 軌跡 | device_id, lat, lon, accuracy, role, name |
| `reports` | 會報記錄 | report_id UNIQUE, audio_path, transcription, patients_snapshot, weather_snapshot |
| `weather_log` | 氣象歷史 | station_id, temperature, humidity, wind_speed, rainfall |
| `transcriptions` | 語音轉錄記錄 | sender_id, text, source, duration |
| `node_status_log` | LoRa 節點狀態歷史 | node_id, rssi, snr, battery, pdr |
| `system_events` | 系統事件日誌 | event_type, device_id, description, severity |

---

### 2.13 usb_backup.py — 雙備份機制

```
├─ 本機即時備份：data/linkguard_local_backup.db
├─ USB 同步：每 15 分鐘（900 秒）
├─ 定時完整備份：每 60 分鐘
│  └─ 保留最近 48 份（= 48 小時）
└─ 備份路徑：USB/LinkGuard/backup/linkguard_YYYYMMDD_HHMMSS.db

USB 目錄結構：
LinkGuard/
├─ data/linkguard.db          (即時同步)
├─ reports/audio/*.m4a        (音訊檔案)
├─ backup/*.db                (定時備份)
├─ backup_manifest.json       (備份清單)
└─ replay/
   ├─ server.py               (離線回放伺服器)
   └─ start.bat / start.sh    (啟動腳本)
```

---

### 2.14 replay/server.py — 離線回放 Web 介面

| 端點 | 說明 |
|------|------|
| `/api/timeline` | 所有事件時序（決策, 傷員, 會報, 節點, 氣象） |
| `/api/snapshot?timestamp=T` | 指定時間點的狀態快照 |
| `/api/decisions` | 所有決策記錄 |
| `/api/patients` | 所有傷員記錄 |
| `/api/locations` | 所有位置軌跡 |
| `/api/reports` | 所有會報記錄 |
| `/api/transcriptions` | 所有轉錄記錄 |
| `/api/nodes` | 所有節點狀態 |
| `/audio/{report_id}` | 音訊串流（Range Request） |

---

## 三、Win10 Web Dashboard

### 3.1 路由

`GET /dashboard` — 由 `http_server.py` (port 8003) 回傳靜態 `dashboard/index.html`

### 3.2 功能

NV 深色主題（與 iOS/Android 相同色系），5 個分頁：

| 分頁 | 功能 | API 端口 |
|------|------|---------|
| 即時統計 | 傷患分類（紅/黃/綠/黑）、人員、資源概況、通訊狀態；自動每 5 秒刷新 | stats:8005 |
| 資源管理 | 資源 CRUD 表格（部署/回收操作） | resources:8006 |
| 照片牆 | 從 photo_server 取得縮圖，支援點擊放大 modal | photos:8004 |
| 會報紀錄 | 會報轉錄列表 + PDF 報告生成 | reports:8003 |
| 事件歷史 | 事件 timeline（可選 1/3/6/12/24 小時） | stats:8005 |

**連線設定**：可自訂後台 IP，預設 `localhost`

---

## 四、Mac-Only 獨立模式

當沒有 Win11 後端時，Mac HQ 可完全獨立運作：

### 4.1 HQSpeechServer.swift（Port 8003）

- 使用 Apple `SFSpeechRecognizer`（zh-TW）取代 Win11 Whisper
- 端點：
  - `POST /report` — 接收 multipart 音訊上傳，辨識後產生 `SpeechResult` 回呼
  - `POST /transcribe` — 純音訊轉文字
  - `GET /health` — 健康檢查（回傳 `engine: apple_speech`）
- 回呼：`onTranscriptionComplete`

### 4.2 HQPhotoServer.swift（Port 8004）

- 使用 `NWListener` 實作嵌入式 HTTP 伺服器
- 端點：
  - `POST /photo` — 接收 multipart 照片上傳（device_id, sender_name, lat, lon, caption）
  - `GET /photo/{id}` — 取得原圖
  - `GET /thumb/{id}` — 取得縮圖
  - `GET /health` — 健康檢查
  - `OPTIONS` — CORS preflight
- 儲存目錄：`~/Documents/LinkGuardData/photos/`
- 回呼：`onPhotoReceived` 通知 HQViewModel 更新照片牆

### 4.3 本地統計計算

- `startLocalStatsTimer()` — 每 30 秒觸發本地統計（僅在後端未提供時啟用）
- `computeLocalStats()` — 從本地資料計算：
  - 傷患分類（內建 START 檢傷邏輯：immediate/delayed/minor/expectant）
  - 人員數（personnelAssignments + teamMembers）
  - 通訊數（chatMessages, radioReports, sentCommands）
  - 決策/照片數、事件持續時間
- `computeLocalResources()` — 從 fieldUnits 產生資源概況
- **`_source` 欄位**：`"local"` vs `"backend"` 區分資料來源

### 4.4 翻譯離線 Fallback

- `requestTranslation()` — 向 `http://{host}:8001/translate` 發送請求（5 秒 timeout）
- 離線處理：catch 區塊回傳 `"（翻譯服務不可用 — 離線模式）"` + `"error": "offline"` 給請求裝置
- `translateHost` 智慧選擇：優先用 backend bridge host，fallback 到 `127.0.0.1`

---

## 五、NV 夜視儀主題

### OLED 暗色主色盤

| 名稱 | Hex | 用途 |
|------|-----|------|
| green | #14B840 | 主色 |
| greenMid | #0F942E | 中調 |
| greenDark | #0A6220 | 暗調 |
| greenDim | #083812 | 極暗 |
| background | #000000 | 純黑背景 |
| card | #0A0A0A | 卡片背景 |

### 語義色彩

| 名稱 | Hex | 用途 |
|------|-----|------|
| danger | #D13838 | SOS/求救（紅色） |
| warning | #B79420 | 警告（琥珀色） |
| heartRate | #B84040 | 心率顯示 |
| info | #1AAE8C | 資訊（青綠） |
| simulation | #6B1FA5 | 模擬模式（紫色） |
| command | #4066B8 | 指揮命令（藍色） |
| team | #1A8FB8 | 團隊成員（淺藍） |
| reinforce | #D08014 | 增援請求（橘色） |

---

## 六、警報音 (AlarmPlayer.swift)

**模擬國家級地震警報 (ANSI Attention Signal)**：

```
雙頻合唱：853 Hz + 960 Hz（方波同時播放）

節奏：1 秒響 + 0.5 秒靜 = 1.5 秒一週期
總長：6 秒（4 週期），無限循環

波形參數：
  ├─ 波形：方波（±0.9 振幅）
  ├─ 淡入：8ms / 淡出：8ms

輸出格式：
  ├─ WAV (RIFF) / PCM 16-bit signed
  ├─ 樣本率：44100 Hz / mono
  └─ 忽視靜音開關（override mute）
```

---

## 七、本地通知 (NotificationManager.swift)

| 通知類型 | 聲音 | 中斷等級 | 內容格式 |
|---------|------|----------|---------|
| SOS 求救 | critical | timeSensitive | "SOS 求救警報：{ID}，心率:{HR}，距離:{dist}" |
| 裝置離線 | default | active | "{ID} 已失去訊號連線" |
| 低電量 | default | active | "{ID} 電量僅剩 {bat}%" |
| 指揮命令 | critical/active | 依優先級 | "[優先級]：{title}，{detail}" |

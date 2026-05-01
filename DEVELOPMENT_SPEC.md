# LinkGuard

## AI 災害救援指揮系統

### 完整系統開發提示詞總文件

新竹高工 × 新竹數位實中

科展展示版本 ｜ 2026

**4/23 科展展示**

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
| LoRa 節點 | 現場通訊 | 長距離廣播通訊 |

### 1.2 服務清單

| 服務 | 主機 | 埠口 | 協議 |
|------|------|------|------|
| tcp_server | 3080 主機 | 9000 | TCP + Bonjour |
| qwen_server | 3080 主機 | 8001 | HTTP (FastAPI) |
| udp_server | 3080 主機 | 9001 | UDP |
| whisper_server | 2060 筆電 | 8002 | HTTP (FastAPI) |
| http_server | 3080 主機 | 8003 | HTTP (FastAPI) |
| mqtt_broker | 3080 主機 | 1883 | MQTT v5 |
| HQCommandServer | M2 Air | 8930 | TCP + Bonjour |

### 1.3 系統架構圖

```
┌─────────────────────────────────────────────────────────────┐
│                    WiFi 指揮層 (TCP 8930)                    │
│                                                             │
│   ┌──────────────┐          ┌──────────────────┐            │
│   │ linkguard    │◄────────►│ HQCommandServer  │            │
│   │ (Field iOS)  │ WiFi     │ (M2 Air macOS)   │            │
│   └──────────────┘ Command  └──────────────────┘            │
│   ┌──────────────┐          ┌──────────────────┐            │
│   │ linkguard    │◄────────►│ HQPeerClient     │            │
│   │ (Field Andr) │          │ (Peer Sync)      │            │
│   └──────────────┘          └──────────────────┘            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Python 後端層 (3080 主機)                    │
│                                                             │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│   │tcp_server│  │qwen_serv │  │http_serv │  │udp_server│   │
│   │ :9000    │  │ :8001    │  │ :8003    │  │ :9001    │   │
│   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│        │             │             │             │           │
│   ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐                 │
│   │mqtt_brok │  │pws_fetch │  │whisper_s │                  │
│   │ :1883    │  │(API 呼叫)│  │ :8002    │   (2060 筆電)    │
│   └──────────┘  └──────────┘  └──────────┘                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    LoRa 無線層 (長距離)                       │
│                                                             │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│   │ HQ Node  │◄──►│ Rescue   │◄──►│ Victim   │              │
│   │ (hq.ino) │    │ (rescue) │    │ (victim) │              │
│   └──────────┘    └──────────┘    └──────────┘              │
│                                                             │
│   BLE 近端：iOS ◄──► Heltec LoRa 32 V3 (ESP32-S3+SX1262)   │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、Python 後端提示詞

### 2.1 tcp_server.py — TCP 聚合中樞（Port 9000）

**角色提示詞**：

> 你是 LinkGuard 系統的 TCP 聚合伺服器，負責接收所有前線裝置的訊息、聚合多來源數據、呼叫 AI 決策引擎、並將結果推播給所有連線裝置。

**核心功能**：

```
1. Bonjour 服務註冊
   - 服務類型：_linkguard._tcp.local.
   - 服務名稱：LinkGuard-Command
   - 前線裝置自動發現，無需手動輸入 IP

2. 訊息處理器
   ├─ "ping"    → 回傳 pong + 連線統計
   ├─ "patient" → 加入傷員佇列 → 觸發 AI 決策
   ├─ "location"→ 更新裝置 GPS 位置
   ├─ "voice_result" → 更新語音文字 → 觸發 AI 決策
   ├─ "voice_broadcast" / "radio_control" → 中繼 PTT 控制
   └─ "report_summary" → 中繼會報摘要到所有裝置

3. 定時任務
   ├─ periodic_weather()      → 每 300 秒推播氣象
   └─ periodic_node_status()  → 每 60 秒推播 LoRa 節點狀態

4. AI 決策流程
   ├─ 聚合：語音文字 + 傷員佇列 + 氣象資料
   ├─ 呼叫 qwen_server /generate
   └─ 推播決策結果給所有裝置
```

**基礎封包格式**（所有 TCP 訊息，以 `\n` 分隔）：

```json
{
  "type": "<訊息類型>",
  "device_id": "<裝置ID>",
  "timestamp": "<ISO 8601>",
  "data": { ... }
}
```

**WiFiMessage 相容格式**（HQ ↔ 前線）：

```json
{
  "msgType": "<訊息類型>",
  "payload": "<JSON 字串>"
}
```

`normalize_message()` 負責將兩種格式統一為基礎封包。

---

### 2.2 qwen_server.py — AI 決策引擎（Port 8001）

**角色提示詞**：

> 你是災害救援指揮 AI 助理。根據 START 檢傷分類標準、傷員狀態、現場氣象、歷史決策記錄，生成實時指揮決策建議。

**模型配置**：

```
正式模型：gemma4:26b (Ollama 本機部署)
輕量模型：gemma4:4b (速度快、VRAM 需求低)
備用模型：linkguard-qwen (Qwen2.5 14B)
測試模型：gemma3:4b (速度快、資源需求低)
Ollama 主機：http://localhost:11434
執行參數（Gemma 4 26B）：
  ├─ num_ctx: 8192      (上下文視窗，較 Qwen 4096 擴大)
  ├─ temperature: 0.3   (低溫度 → 一致性高)
  └─ num_gpu: 99        (全 GPU 加速)
```

**System Prompt**：

```
你是災害救援指揮AI助理。

【START 檢傷分類標準】
步驟1 呼吸評估: 無呼吸(-1) → 黑色（已死亡，不急救，集中資源於紅色傷患）
步驟2 循環評估: 呼吸>30次/分 → 紅色；微血管回填>2秒或無脈搏(-1) → 紅色
步驟3 意識評估: 無法遵從指令 → 紅色
全部正常 → 綠色（輕傷/可行走）
黑色=已死亡，不進行急救，將所有資源集中於紅色（危急）傷患。

以下是本次事件的歷史決策記錄：
{recent_decisions}

根據歷史記錄和當前資訊生成新的指揮決策，避免重複已執行的指令。
輸出格式:
【優先處置】...
【資源調配】...
【注意事項】...
【與上次決策的差異】...
```

**User Prompt 模板**：

```
現在時間：{now}

語音報告：
{voice_text}

傷員概況：
{patient_summary}

天氣狀況：
{weather_summary}

請根據以上資訊生成指揮決策。
```

**決策流程**：

```
1. 對每名傷員執行 triage_START() 檢傷分類
2. format_for_llm() 生成傷員摘要
3. format_weather_for_llm() 生成氣象摘要
4. get_recent_decisions(5) 取得最近 5 筆歷史決策
5. 組合 system_prompt + user_prompt
6. ollama.chat() 生成決策
7. save_decision() 存入 SQLite memory.db
8. 回傳 {decision, patients}
```

**SQLite 記憶庫 (memory.db)**：

```sql
CREATE TABLE decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    voice_text TEXT,
    patients_summary TEXT,
    weather_summary TEXT,
    decision_text TEXT
);

CREATE TABLE context (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT UNIQUE NOT NULL,
    value TEXT
);
```

---

### 2.3 whisper_server.py — 語音轉錄（Port 8002）

**角色提示詞**：

> 你是 LinkGuard 的語音轉錄服務，接收前線搜救人員的音訊檔案，使用 OpenAI Whisper 模型轉為文字，並自動回傳結果。

**模型配置**：

```
模型：large-v3 (faster-whisper)
裝置：CUDA (GPU)
精度：float16
語言：zh (中文優先)
```

**API 端點**：

```
POST /transcribe
Content-Type: multipart/form-data
Fields:
  ├─ file: 音訊二進位 (WAV 或 M4A)
  ├─ source: "broadcast" | "report" (預設 "broadcast")
  └─ sender_id: 裝置 ID (預設 "unknown")

Response:
{
  "text": "轉錄文字",
  "language": "zh",
  "duration": 3.45
}
```

**自動轉送**：轉錄完成後以 TCP 送至 tcp_server（`voice_result` 訊息）。

---

### 2.4 http_server.py — 會報管理（Port 8003）

**角色提示詞**：

> 你是 LinkGuard 的會報管理服務，接收前線人員的語音會報、傷員快照、氣象資料，存入 SQLite 資料庫，並推播會報摘要至指揮中心。

**API 端點**：

```
POST /report
Content-Type: multipart/form-data
Fields:
  ├─ audio: M4A 音訊檔
  ├─ device_id: 裝置 ID
  ├─ sender_name: 發送者名稱
  ├─ location_lat, location_lon: GPS 座標
  ├─ location_desc: 位置文字描述
  ├─ patients_snapshot: JSON 字串化的傷員快照
  ├─ weather_snapshot: JSON 字串化的氣象快照
  └─ timestamp: ISO 8601

Response:
{
  "status": "ok",
  "report_id": "RPT-20260423-001",
  "transcription": "轉錄文字",
  "timestamp": "2026-04-23T..."
}

GET /audio/{report_id}
→ 回傳音訊檔案 (Range Request 支援)
```

**會報 ID 格式**：`RPT-YYYYMMDD-NNN`（每日流水號 001 起算）

**流程**：

```
1. 接收音訊 + 附帶資料
2. 存音訊到 reports/audio/RPT-xxx.m4a
3. 送 Whisper 轉錄
4. 存入 SQLite reports.db
5. 推播會報摘要至 tcp_server → 所有裝置
```

**重試機制**：轉錄失敗 → 暫存 pending/ → 每 60 秒重試 → 最多 3 次。

---

### 2.5 udp_server.py — 語音廣播接收（Port 9001）

**角色提示詞**：

> 你是 LinkGuard 的語音廣播接收器，監聽 UDP 封包，接收前線人員的 PCM 音訊流，自動偵測廣播結束，送至 Whisper 轉錄。

**UDP 封包結構**（二進位格式）：

```
┌──────────┬──────────┬──────────┬──────────┬─────────────┬──────────────┐
│ Magic    │ DevID    │ Device   │ Sequence │ Timestamp   │ Audio Data   │
│ 4 bytes  │ Len 2B   │ ID (var) │ 4 bytes  │ 8 bytes(ms) │ (variable)   │
└──────────┴──────────┴──────────┴──────────┴─────────────┴──────────────┘

Magic: 0x4C474244 ("LGBD")
DevID Len: uint16 big-endian
Sequence: uint32 big-endian (防重複)
Timestamp: uint64 big-endian (毫秒)
Audio: PCM 16-bit signed, 16kHz, mono
```

**行為邏輯**：

```
1. 接收 UDP 封包 → 驗證 Magic → 解析標頭
2. 去重：維護 _seq_sets[device_id] = set(sequence)
3. 累積 PCM chunks 至 audio_buffer[device_id]
4. 超過 2 秒無新封包 → 廣播結束
5. PCM → WAV 轉換 → 送 Whisper 轉錄
6. 清空 buffer
```

---

### 2.6 mqtt_broker.py — LoRa 節點狀態（Port 1883）

**訂閱主題**：`linkguard/nodes/#`

**節點狀態格式**：

```json
{
  "node_id": "HQ-1",
  "rssi": -75,
  "snr": 8.5,
  "battery": 92,
  "location": { "lat": 24.8038, "lon": 120.9688 },
  "pdr": 95,
  "timestamp": "2026-04-23T..."
}
```

**全域狀態字典**：`node_status[node_id]` 持續更新，供 tcp_server 定時推播。

---

### 2.7 pws_fetcher.py — 中央氣象署 API

**API 端點**：`https://opendata.cwa.gov.tw/api/v1/rest/datastore/O-A0001-001`

**測站代碼**：C0A980

**回傳欄位**：

```json
{
  "temperature": 28.5,    // °C
  "humidity": 75.0,       // %
  "wind_speed": 5.2,      // m/s
  "rainfall": 0.0,        // mm
  "timestamp": "2026-04-23T12:00:00+08:00"
}
```

**LLM 格式化**：`"氣溫:28.5°C | 濕度:75% | 風速:5.2m/s | 雨量:0mm"`

---

### 2.8 START 檢傷分類演算法 (triage.py / start_triage.py)

```
函式：triage_START(patient) → {priority, reason}

輸入：
  ├─ breathing_rate: int    (-1 = 無呼吸)
  ├─ capillary_refill: float (-1 = 無脈搏)
  └─ can_follow_commands: bool

決策樹（順序評估）：

  Step 1: 呼吸評估
  ├─ breathing_rate == -1
  │  → 黑色「無呼吸」（已死亡，不急救）
  │
  Step 2: 循環評估
  ├─ breathing_rate > 30
  │  → 紅色「呼吸大於30次/分（呼吸過速）」
  ├─ capillary_refill > 2 或 == -1
  │  → 紅色「微血管回填>2秒或無橈動脈脈搏」
  │
  Step 3: 意識評估
  ├─ can_follow_commands == false
  │  → 紅色「無法遵從指令」
  │
  Step 4: 全部正常
  └─ → 綠色「三項檢查正常」

優先級對照：
  黑色 = 已死亡/無法救治（不急救，集中資源）
  紅色 = 危急（立即處置）
  綠色 = 輕傷/可行走
```

---

### 2.9 linkguard_db.py — 統一資料庫

**資料庫**：`data/linkguard.db`（SQLite WAL 模式）

**8 張表**：

| 表名 | 用途 |
|------|------|
| `decisions` | AI 決策記錄（timestamp, voice_text, patients_summary, weather_summary, decision_text, trigger_type） |
| `patients` | 傷員資料（patient_id UNIQUE, breathing_rate, capillary_refill, can_follow_commands, priority, reason, gps） |
| `locations` | 裝置 GPS 軌跡（device_id, lat, lon, accuracy, role, name） |
| `reports` | 會報記錄（report_id UNIQUE, audio_path, transcription, patients_snapshot, weather_snapshot） |
| `weather_log` | 氣象歷史（station_id, temperature, humidity, wind_speed, rainfall） |
| `transcriptions` | 語音轉錄記錄（sender_id, text, source, duration） |
| `node_status_log` | LoRa 節點狀態歷史（node_id, rssi, snr, battery, pdr） |
| `system_events` | 系統事件日誌（event_type, device_id, description, severity） |

---

### 2.10 usb_backup.py — 雙備份機制

**備份策略**：

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
   ├─ start.bat / start.sh    (啟動腳本)
```

---

### 2.11 replay/server.py — 離線回放 Web 介面

**API 端點**：

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

## 三、iOS 前線應用提示詞

### 3.1 應用入口 (linkguardApp.swift)

**角色提示詞**：

> 你是 LinkGuard 前線搜救應用，部署在搜救人員的 iPhone/iPad 上，負責接收 LoRa 受困者訊號、回報傷員狀態、接收指揮命令、與指揮中心即時通訊。

**App 配置**：

```swift
@main struct linkguardApp: App {
    WindowGroup {
        ContentView
            .preferredColorScheme(.dark)  // 強制暗色模式
            .tint(NV.green)              // 夜視儀螢光綠主色
    }
}
```

---

### 3.2 主畫面結構 (ContentView.swift)

**導航架構**：`TabView(.sidebarAdaptable)`

```
┌─ 主分頁
│  ├─ 總覽           (gauge)                     Dashboard
│  ├─ 受困者         (person.wave.2)              + badge(受困者數)
│  ├─ SOS            (exclamationmark.triangle)   + badge(SOS 數)
│  ├─ 災情           (building.2)                 災害狀態
│  ├─ 通訊           (bubble)                     + badge(未讀數)
│  ├─ 增援           (person.badge.plus)          + badge(待處理)
│  ├─ 團隊           (person.3.fill)              團隊成員
│  ├─ 命令           (megaphone.fill)             + badge(未讀數)
│  └─ 通知           (bell.fill)                  + badge(未讀數)
│
└─ TabSection("工具")
   ├─ 電台           (antenna.radiowaves.left.and.right)
   ├─ 連線           (link)                       BLE/WiFi 連線管理
   ├─ 傷員回報       (cross.case.fill)            PatientFormView
   └─ 指揮決策       (megaphone.fill)             + badge(決策數)
```

**Dashboard 區塊**：

```
1. 標題列 + 系統狀態指示燈（模擬/BLE/WiFi）
2. 統計卡片 Grid（iPad 4 欄 / iPhone 2 欄）
   ├─ 受困者（線上/總數）
   ├─ SOS 計數
   ├─ 團隊（線上/總數）
   ├─ 增援待處理
   ├─ 訊息計數
   └─ 命令未讀數
3. 節點連線狀態（BLE + LoRa 檔位）
4. 快速狀態回報 6 按鈕
5. 倒數計時器
6. 待處理任務
7. 危險標記（前 3 個）
8. 受困者即時狀態列表
9. 交班摘要生成
```

---

### 3.3 核心 ViewModel (LinkGuardViewModel.swift)

**節點識別**：

```
Device ID 格式：RT-{隨機 3 位 HEX}（如 RT-A3F）
  └─ 持久化：UserDefaults["linkguard_node_hex_id"]

完整 Node ID：RT-{HEX}-{DEPT}（如 RT-A3F-EMT）
  └─ 部門碼：EMT(救護) / FD(消防) / PD(警察)
  └─ 持久化：UserDefaults["linkguard_dept_code"]
```

**@Published 狀態（40+ 項）**：

```
節點自身：
  ├─ victims: [VictimNode]           受困者列表
  ├─ sosRecords: [SOSRecord]         SOS 記錄
  ├─ nodeStatus: RescueNodeStatus    節點自身狀態
  ├─ teamMembers: [TeamMember]       團隊成員
  └─ isBluetoothConnected: Bool      BLE 連線狀態

WiFi 指揮通訊：
  ├─ commandOrders: [CommandOrder]   指揮命令列表
  ├─ latestCriticalCommand           最新危急命令（全螢幕覆蓋）
  └─ reinforcementRequests           增援請求列表

災害與任務：
  ├─ disasterSite: DisasterSite      災害狀態
  ├─ chatMessages: [ChatMessage]     聊天訊息
  ├─ pwsAlerts: [PWSAlert]           PWS 警報
  ├─ briefings: [BriefingReport]     會報
  ├─ personalNotifications           個人通知
  ├─ tasks: [TaskAssignment]         任務
  ├─ countdownTimers                 倒數計時
  ├─ hazardReports: [HazardReport]   危險標記
  └─ radioReports                    電台會報

UI 控制：
  ├─ isSimulating: Bool              模擬模式
  ├─ uptimeSeconds: Int              運行時間
  └─ latestSOSVictim                 SOS 全螢幕覆蓋
```

**定時任務**：

| 定時器 | 週期 | 功能 |
|--------|------|------|
| 模擬更新 | 2 秒 | SimulationEngine 更新受困者數據 |
| 運行計時 | 1 秒 | uptimeSeconds++ |
| 狀態回報 | 10 秒 | sendStatusReport() → HQ |
| GPS 回報 | 15 秒 | sendLocationUpdate() → tcp_server |
| 危急震動 | 持續 | Critical 命令持續震動提醒 |

**WiFi 回呼（15+ 個）**：

```
onCommand(WiFiCommand)                → 解析為 CommandOrder
onChatMessage(ChatMessage)            → 加入聊天列表
onDisasterUpdate(DisasterSite)        → 更新災害狀態
onPersonnelAssignment([PersonnelAssignment]) → 更新人員配置
onPWSAlert(PWSAlert)                  → 加入 PWS 警報 + AlarmPlayer
onBriefing(BriefingReport)            → 加入會報
onPersonalNotification(PersonalNotification) → 加入通知
onQuickStatus(QuickStatus)            → 快速狀態
onTaskAssignment(TaskAssignment)      → 加入任務
onTimerSync(CountdownTimerModel)      → 同步倒數計時
onTimerCancel(String)                 → 取消倒數計時
onHazardReport(HazardReport)          → 加入危險標記
onReinforcementRequest(ReinforcementRequest) → 加入增援
onReinforcementReply(ReinforcementRequest)   → 更新增援狀態
onDecision(HQDecision)                → 加入 AI 決策
onReportSummary(RadioReportSummary)   → 加入會報摘要
onRadioControl(RadioControlPayload)   → PTT 控制
```

---

### 3.4 資料模型 (LinkGuardModels.swift)

**VictimNode（受困者）**：

```
id: String                  (VT-A3F)
heartRate: Int              (BPM, 0=無資料)
battery: Int                (0-100%)
rssi: Double                (dBm)
snr: Double
isSOS: Bool
lastSeen: Date
isOnline: Bool              (30 秒 timeout)
estimatedDistance: Double    (公式：d = 10^((A-rssi)/(10*n)), A=-30, n=2.7)
distanceText: String        ("1.2m", "48m", "2.5km")
```

**LoRa 檔位（9 檔）**：

| 檔位 | SF | BW (kHz) | CR | 特性 |
|------|----|---------|----|------|
| L0 | 7 | 500.0 | 5 | 極速 |
| L1 | 7 | 250.0 | 5 | 高速 |
| L2 | 8 | 250.0 | 5 | 敏捷 |
| L3 | 9 | 250.0 | 6 | 平衡 |
| L4 | 9 | 125.0 | 6 | 標準 |
| L5 | 10 | 125.0 | 7 | 穿透 |
| L6 | 10 | 62.5 | 8 | 強穿 |
| L7 | 11 | 62.5 | 8 | 極限 |
| L8 | 12 | 62.5 | 8 | 最遠 |

**指揮命令類型 (CommandType)**：

```
search          搜索
standby         待命
support         支援
report          回報
evacuation      撤離
medical         醫療
logistics       後勤
communication   通訊
alert           警報
statusReport    狀態回報
zoneAssignment  分區指派
hazardWarning   危險警告
briefingUpdate  會報更新
resourceRequest 資源請求
shiftChange     交班
全面撤離、暫停搜索、繼續搜索、集合、裝備檢查...
```

**命令優先級 (CommandPriority)**：

| 值 | 等級 | 行為 |
|----|------|------|
| 0 | routine | 一般通知 |
| 1 | urgent | 震動提醒 |
| 2 | critical | 全螢幕覆蓋 + 持續震動 + 警報音 |

**災害相關枚舉**：

```
CollapseType: partial, pancake, lean, vShape, none, unknown
FloorCondition: collapsed, partial, accessible, cleared, restricted, unknown
ZoneStatus: active, standby, cleared, dangerous, restricted
HazardType: gasLeak, fire, flooding, structural, electrical, chemical
PWSAlertType: earthquake, aftershock, tsunami, typhoon, flood, landslide, other
PWSSeverity: info, minor, moderate, severe, extreme (Comparable)
BriefingType: initial, progress, shift, final
PersonnelRole: search, rescue, medical, logistics, safety, commander, support
```

---

### 3.5 BLE 通訊 (BluetoothManager.swift)

**硬體**：Heltec WiFi LoRa 32 V3（ESP32-S3 + SX1262）

**BLE UUID**：

| 用途 | UUID |
|------|------|
| Service | `4FAFC201-1FB5-459E-8FCC-C5C9C331914B` |
| 狀態通知 (Notify) | `BEB5483E-36E1-4688-B7F5-EA07361B26A8` |
| 命令寫入 (Write) | `BEB5483E-36E1-4688-B7F5-EA07361B26AB` |
| LoRa 命令 (Notify) | `BEB5483E-36E1-4688-B7F5-EA07361B26AC` |

**韌體狀態 JSON（BLE Notify）**：

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

**BLE 命令（Write）**：

| 命令 | 格式 | 說明 |
|------|------|------|
| 設定部門 | `setdept:EMT` | 設定所屬部門 |
| 設定檔位 | `setlvl:3` | 設定 LoRa 檔位 (0-8) |
| 設定配對碼 | `setpair:1234` | 設定 LoRa 配對碼 |
| 命令回執 | `cmd_ack:{cmdID}` | 通知韌體收到命令 |
| 增援請求 | `reinforce:{msg}\|{loc}` | 發送增援 |
| 增援回覆 | `rf_reply:{team}\|{JOIN/NAK}` | 回覆增援 |
| 團隊 Ping | `team_ping` | 發送團隊心跳 |

**LoRa 命令轉發（Notify）**：

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

### 3.6 串列通訊 (SerialManager.swift)

**用途**：macOS 開發時直接 USB 連線 Heltec 開發板

```
波特率：115200
格式：8-N-1 (8 bits, no parity, 1 stop bit)

埠偵測篩選：
usbserial*, usbmodem*, SLAB*, wchusbserial*, cu.*

命令格式：
├─ "STATUS"                              請求狀態 JSON
├─ "PING"                                Ping 測試
├─ "CMD:{cmdId}:{type}:{pri}:{title}:{detail}" 發送指揮命令
└─ 接收 "CMD_RX:{cmdId}:{type}:{pri}:{title}:{detail}:{sender}"
```

---

### 3.7 語音錄音 (VoiceInputManager.swift)

**錄音配置**：

```
格式：MPEG4 AAC
樣本率：44100 Hz
聲道：mono
品質：high

上傳：POST multipart/form-data
  URL: http://{serverHost}:8002/transcribe
  Field: "file" (audio/mp4)
  Timeout: 30 秒
```

---

### 3.8 模擬引擎 (SimulationEngine.swift)

**初始受困者池**：

| ID | 心率 | 電量 | RSSI | SOS |
|----|------|------|------|-----|
| VT-A3F | 78 | 65% | -62 | ✅ |
| VT-B72 | 92 | 43% | -78 | ❌ |
| VT-C1E | 0 | 12% | -91 | ✅ |

**模擬更新（2 秒週期）**：

```
RSSI 漂移：-3 ~ +3 dBm
SNR 漂移：-0.5 ~ +0.5
心率漂移：-3 ~ +3 bpm
電量衰減：每 15 次更新 -1%
上線/離線：30 秒無更新 → 離線
新受困者：低機率觸發
SOS 切換：低機率隨機
```

---

### 3.9 夜視儀主題 (NightVisionTheme.swift)

**OLED 暗色主色盤**：

| 名稱 | RGB | Hex | 用途 |
|------|-----|-----|------|
| green | (0.08, 0.72, 0.25) | #14B840 | 主色 |
| greenMid | (0.06, 0.58, 0.18) | #0F942E | 中調 |
| greenDark | (0.04, 0.38, 0.12) | #0A6220 | 暗調 |
| greenDim | (0.03, 0.22, 0.07) | #083812 | 極暗 |
| background | (0, 0, 0) | #000000 | 純黑背景 |
| card | (0.04, 0.04, 0.04) | #0A0A0A | 卡片背景 |

**語義色彩**：

| 名稱 | Hex | 用途 |
|------|-----|------|
| danger | #D13838 | SOS/求救 |
| warning | #B79420 | 警告（琥珀色） |
| heartRate | #B84040 | 心率顯示 |
| info | #1AAE8C | 資訊（青綠） |
| simulation | #6B1FA5 | 模擬模式（紫色） |
| command | #4066B8 | 指揮命令（藍色） |
| team | #1A8FB8 | 團隊成員（淺藍） |
| reinforce | #D08014 | 增援請求（橘色） |

---

### 3.10 警報音 (AlarmPlayer.swift)

**模擬國家級地震警報 (ANSI Attention Signal)**：

```
雙頻合唱：853 Hz + 960 Hz（方波同時播放）

節奏：1 秒響 + 0.5 秒靜 = 1.5 秒一週期
總長：6 秒（4 週期），無限循環

波形參數：
  ├─ 波形：方波（±0.9 振幅）
  ├─ 淡入：8ms
  └─ 淡出：8ms

輸出格式：
  ├─ WAV (RIFF) / PCM 16-bit signed
  ├─ 樣本率：44100 Hz / mono
  └─ 忽視靜音開關（override mute）
```

---

### 3.11 本地通知 (NotificationManager.swift)

**通知類型**：

| 類型 | 聲音 | 中斷等級 | 內容 |
|------|------|----------|------|
| SOS 求救 | critical | timeSensitive | "SOS 求救警報：{ID}，心率:{HR}，距離:{dist}" |
| 裝置離線 | default | active | "{ID} 已失去訊號連線" |
| 低電量 | default | active | "{ID} 電量僅剩 {bat}%" |
| 指揮命令 | critical/active | 依優先級 | "[優先級]：{title}，{detail}" |

---

## 四、HQ 指揮中心提示詞

### 4.1 應用入口 (LinkGuardHQApp.swift)

**角色提示詞**：

> 你是 LinkGuard 指揮中心應用，部署在 macOS（含 31.5 吋外接顯示器）或 iPad 上，負責接收所有前線裝置的狀態、下達指揮命令、管理災害資訊、顯示 AI 決策建議。

```swift
@main struct LinkGuardHQApp: App {
    @StateObject var vm = HQViewModel()
    WindowGroup {
        HQDashboardView(vm: vm)
    }
    #if os(macOS)
    .defaultSize(width: 1200, height: 800)
    #endif
}
```

---

### 4.2 核心 ViewModel (HQViewModel.swift)

**雙角色模式**：

| 模式 | 說明 |
|------|------|
| `.server` | 本機啟動 TCP 伺服器 (8930)，接收前線連線 |
| `.peer` | 連接至其他 HQ 伺服器，同步全部狀態 |

**PADOS 多裝置定向指揮**：

```
.broadcast → 廣播全體（effectiveTargetIDs = nil）
.selected  → 指定裝置群（effectiveTargetIDs = [deviceID1, ...]）
```

**傷員管理**：

```
victimPriorities[victimID] = VictimPriority
victimNotes[victimID] = String
allVictimRecords → 聚合視圖（含優先級、備註、來源設備）
```

---

### 4.3 指揮伺服器 (HQCommandServer.swift)

**TCP 伺服器配置**：

```
埠口：8930
Bonjour：_linkguard._tcp / LinkGuard-CMD
最大連線：無限制
歷史命令：最近 100 筆
```

**WiFiMessage 處理器**：

| msgType | 方向 | 處理 |
|---------|------|------|
| `hello` | Field → HQ | 識別 field_unit / hq_peer |
| `status_report` | Field → HQ | 更新 fieldUnits 列表 |
| `chat_message` | 雙向 | 中繼轉發（私訊/廣播） |
| `quick_status` | Field → HQ | 快速狀態回報 + 中繼 |
| `task_update` | Field → HQ | 任務進度更新 |
| `hazard_report` | Field → HQ | 危險標記 + 中繼 |
| `reinforcement_request` | Field → HQ | 增援請求 + 中繼 |
| `reinforcement_reply` | Field → HQ | 增援回覆 + 中繼 |
| `patient` | Field → HQ | 傷員回報 |
| `location` | Field → HQ | GPS 位置更新 |
| `radio_control` | Field → HQ | PTT 控制 + 中繼 |
| `radio_report` | Field → HQ | 會報摘要 |
| `ping` | 雙向 | 回覆 pong |

**發送功能**：

```
broadcastCommand(WiFiCommand, targetDeviceIDs?)  → 命令推播
broadcastDisasterUpdate(DisasterSite)             → 災害狀態
broadcastPersonnelAssignment([PersonnelAssignment]) → 人員配置
broadcastPWSAlert(PWSAlert)                        → PWS 警報
broadcastBriefing(BriefingReport)                  → 會報
sendPersonalNotification(PersonalNotification, to:) → 個人通知
broadcastTaskAssignment(TaskAssignment)            → 任務
broadcastCountdownTimer(CountdownTimerModel)       → 倒數計時
broadcastDecision(HQDecision)                      → AI 決策
```

---

### 4.4 HQ Peer 同步 (HQPeerClient.swift)

**角色**：以 `hq_peer` 身份連線至另一台 HQ 伺服器

**同步項目（全部雙向）**：

```
├─ 命令、聊天、災害狀態
├─ 人員配置、PWS 警報、會報
├─ 個人通知、時間線、任務
├─ 倒數計時、危險標記
└─ 增援請求
```

---

### 4.5 HQ BLE (HQBluetoothManager.swift)

**HQ 端 LoRa 韌體 UUID**（與 Field 不同）：接收全域 LoRa 訊息。

---

### 4.6 側邊欄導航 (HQDashboardView.swift)

**12 個分類**：

```
├─ 儀表板         (gauge)
├─ 災害狀態       (building.2)
├─ 人員總覽       (person.3.fill)
├─ 受困者總覽     (person.wave.2)
├─ 人員配置       (person.badge.key.fill)
├─ 通訊頻道       (bubble.left.and.bubble.right)
├─ PWS 警報       (exclamationmark.triangle)
├─ 會報系統       (doc.text.fill)
├─ 個人通知       (bell.fill)
├─ 事件日誌       (clock.arrow.circlepath)
├─ 分區地圖       (map.fill)
└─ 會報儀表板     (chart.bar.fill)
```

---

## 五、WiFi 命令協議 (CommandEngine.swift)

### 5.1 WiFiCommand 結構

```json
{
  "id": "UUID",
  "type": "search|standby|support|report|evacuation|...",
  "priority": 0,
  "title": "搜索 B 區 3F",
  "detail": "請前往 B 區 3 樓西側走廊進行生命跡象掃描",
  "sender": "HQ-Alpha",
  "timestamp": 1714000000.0
}
```

### 5.2 FieldStatusReport 結構

```json
{
  "deviceID": "RT-A3F-EMT",
  "deptCode": "EMT",
  "battery": 85,
  "bleConnected": true,
  "victims": [
    { "id": "VT-001", "heartRate": 92, "battery": 75, "rssi": -65.0, "isSOS": true, "isOnline": true }
  ],
  "teamMembers": [
    { "id": "RT-B2E", "deptCode": "FD", "battery": 60, "rssi": -70.0, "isOnline": true, "victimCount": 2 }
  ],
  "sosCount": 1,
  "timestamp": 1714000000.0
}
```

### 5.3 完整 msgType 清單

| msgType | 方向 | Payload 類型 |
|---------|------|-------------|
| `command` | HQ → Field | WiFiCommand |
| `status_report` | Field → HQ | FieldStatusReport |
| `chat_message` | 雙向 | ChatMessage |
| `disaster_update` | HQ → Field | DisasterSite |
| `personnel_assignment` | HQ → Field | [PersonnelAssignment] |
| `pws_alert` | HQ → Field | PWSAlert |
| `briefing` | HQ → Field | BriefingReport |
| `personal_notification` | HQ → Field | PersonalNotification |
| `quick_status` | Field → HQ | QuickStatus |
| `task_assignment` | HQ → Field | TaskAssignment |
| `task_update` | Field → HQ | TaskAssignment |
| `timer_sync` | HQ → Field | CountdownTimerModel |
| `timer_cancel` | HQ → Field | {"id": "timerID"} |
| `hazard_report` | 雙向 | HazardReport |
| `reinforcement_request` | Field → HQ → Field | ReinforcementRequest |
| `reinforcement_reply` | Field → HQ → Field | ReinforcementRequest |
| `decision` | HQ → Field | HQDecision |
| `report_summary` | HQ → Field | RadioReportSummary |
| `radio_control` | Field → HQ → Field | RadioControlPayload |
| `patient` | Field → tcp_server | PatientData |
| `location` | Field → tcp_server | LocationData |
| `ping` / `pong` | 雙向 | 心跳 |

---

## 六、模擬命令引擎 (SimulatedCommandEngine)

**用途**：無 WiFi 指揮中心時，用 NTP 時間同步產生模擬命令

**指令槽週期**：20 秒

**模擬命令模板（13 種）**：

| 類型 | 標題 | 優先級 |
|------|------|--------|
| search | 搜索 B 區 3F | 0 |
| search | 緊急搜索 A 區地下室 | 1 |
| search | 擴大搜索範圍至 C 區 | 0 |
| standby | 原地待命 | 0 |
| standby | 暫停推進 | 1 |
| support | 請求醫療支援 | 1 |
| support | 請求重型設備 | 0 |
| support | 緊急增援 | 2 |
| report | 回報搜索進度 | 0 |
| report | 回報人員狀態 | 0 |
| evacuation | 立即撤離 | 2 |
| evacuation | 部分撤離 D 區 | 1 |
| evacuation | 撤離準備 | 0 |

**發送者輪替**：`HQ-Alpha`, `HQ-Bravo`, `CMD-Central`, `OPS-South`

---

## 七、LoRa 韌體

### 7.1 硬體

**MCU**：Heltec WiFi LoRa 32 V3（ESP32-S3 + SX1262 LoRa）

### 7.2 韌體目標

| 目錄 | 用途 | 配合端 |
|------|------|--------|
| `LoRa/hq/` | HQ LoRa 節點 | HQ App (macOS/iPad) |
| `LoRa/rescue/` | 搜救隊 LoRa 節點 | Field App (iOS/Android) |
| `LoRa/victim/` | 受困者 LoRa 節點 | 受困者配戴 |

### 7.3 通訊參數

```
頻率：依 LoRa 檔位 (L0-L8) 設定 SF/BW/CR
心跳間隔：3 秒
離線判定：30 秒無更新
配對碼：4 位數字
```

---

## 八、Android 端

### 8.1 Field App (Android/)

**語言**：Kotlin

**架構**：對應 iOS linkguard，功能同步

**關鍵 Class**：
- `CommandClient.kt` — WiFi 命令收發
- `BluetoothManager.kt` — BLE 連線 LoRa 韌體
- `LinkGuardViewModel.kt` — MVVM 狀態管理

### 8.2 HQ App (LinkGuardHQ-Android/)

**語言**：Kotlin

**架構**：對應 iOS LinkGuardHQ

**關鍵 Class**：
- `HQCommandServer.kt` — TCP 伺服器 + Bonjour
- `HQViewModel.kt` — 指揮中心邏輯

---

## 九、資料流向圖

### 9.1 前線 → 指揮中心

```
LoRa Victim Node
  → LoRa Rescue Node (LoRa 長距離接收)
    → BLE → linkguard iOS (BluetoothManager)
      → WiFi TCP → HQCommandServer (:8930)
        → HQViewModel → 儀表板顯示
          → HQPeerClient (同步其他 HQ)
```

### 9.2 指揮中心 → 前線

```
HQ Dashboard (下達命令)
  → HQCommandServer (WiFiCommand 廣播/PADOS 指定)
    → WiFi TCP → linkguard iOS (CommandClient)
      → BLE Write → Rescue Node (Heltec)
        → LoRa 轉發 → Victim Node
```

### 9.3 AI 決策流

```
前線語音輸入
  → Whisper (:8002) 轉錄
    → TCP Server (:9000) 聚合
      + 傷員佇列 (triage_START)
      + 氣象資料 (pws_fetcher)
      + 歷史決策 (SQLite memory.db)
    → Qwen LLM (:8001) 生成決策
      → TCP 推播 → 所有裝置顯示
```

### 9.4 會報流

```
前線搜救員
  → 按下錄音 (VoiceInputManager)
    → HTTP POST → http_server (:8003)
      → 存音訊到 reports/audio/
      → 送 Whisper 轉錄
      → 存 SQLite reports.db
      → 推播摘要 → tcp_server → 所有裝置
```

### 9.5 備份流

```
所有資料 → linkguard.db (SQLite WAL)
  → 本機即時備份
  → USB 同步 (每 15 分鐘)
  → 定時完整備份 (每 60 分鐘, 保留 48 份)
  → USB 離線回放 (replay/server.py)
```

---

## 十、Bonjour 服務發現

| 服務類型 | 名稱 | 來源 | 用途 |
|----------|------|------|------|
| `_linkguard._tcp` | `LinkGuard-Command` | tcp_server.py | Python 後端發現 |
| `_linkguard._tcp` | `LinkGuard-CMD` | HQCommandServer | HQ 指揮伺服器發現 |

**前線裝置自動搜尋** `_linkguard._tcp` → 發現 HQ → 自動 TCP 連線

---

## 十一、HQ vs Field 對照表

| 面向 | HQ（指揮中心） | Field（現場搜救） |
|------|---------------|-----------------|
| 平台 | macOS + 31.5 吋外接 / iPad | iPhone / iPad |
| App | LinkGuardHQ | linkguard |
| 角色 | 中央指揮、AI 決策、資源配置 | 現場搜救、受困者追蹤、狀況回報 |
| 通訊 | TCP Server (8930) + Bonjour + Peer Sync | WiFi Client + Bonjour 自動發現 |
| LoRa | HQ 節點（接收全域） | Rescue 節點（現場收發） |
| 導航 | 側邊欄（12 分類） | TabView（13+ tabs, .sidebarAdaptable） |
| 決策 | Qwen AI + START 檢傷 + 氣象整合 | 接收 HQ 命令、上報狀況 |
| 多裝置 | PADOS 目標指定 | 單一前線單位視角 |

---

## 十二、4/23 科展展示檢查清單

### 12.1 啟動順序

```
1. 啟動 RT-AX1800S 路由器
2. 啟動 3080 主機
   ├─ mqtt_broker.py
   ├─ tcp_server.py
   ├─ qwen_server.py
   ├─ http_server.py
   └─ udp_server.py
3. 啟動 2060 筆電
   └─ whisper_server.py
4. 開啟 LoRa 節點（HQ + Rescue + Victim）
5. 啟動 M2 Air → LinkGuardHQ macOS
6. 啟動 iPad Air M2 → LinkGuard iPadOS
7. 啟動 iOS 手機 → LinkGuard iOS
8. 啟動 Android 手機 → LinkGuard Android
```

### 12.2 展示流程建議

```
1. 展示系統架構圖
2. Demo: 受困者 LoRa 發信 → iOS 接收顯示
3. Demo: iOS 語音回報 → Whisper 轉錄
4. Demo: 傷員 START 檢傷 → AI 決策生成
5. Demo: HQ 下達指揮命令 → 前線接收
6. Demo: 即時聊天 + PTT 廣播
7. Demo: 災害狀態管理
8. Demo: USB 離線備份 + 回放
```

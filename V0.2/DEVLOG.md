# LinkGuard — 開發日誌

> **專案**：LinkGuard Beta V0.1 — AI 災害救援指揮系統  
> **團隊**：新竹高工 × 新竹數位實中  
> **科展展示**：2026-04-23  
> **Repository**：`jarry050599/linkguard_beta_V0.1`

---

## 完整開發時間軸

```
2025-04         系統初始設計與規格制定
2025-04-06      資料鏈稽核報告（第一次稽核）
2025-07         數據鏈審計報告（第二次完整審計，涵蓋 12 條數據流）
2026-04-10      Mac HQ 完整中繼轉發規範 v1.0 定案
          Phase 1  P0 修復：iOS 照片埠、Android hardcode IP
          Phase 2  P0/P1 修復：BackendBridge、location 持久化、決策 weather
          Phase 3  Mac-only 架構確立：嵌入式 Speech/Photo server
2026-04-14 23:44  git commit 783536e — 初版完整推送，Bonjour 服務類型定案
2026-04-15 00:04  git commit c17f9ee — Mac-only hard-cut，移除 Windows 轉發路徑
2026-04-23      ★ 科展展示目標日
```

---

## 一、系統設計期（2025-04 前）

### 1.1 系統定位

LinkGuard 定位為**災害現場 AI 指揮決策系統**，解決以下痛點：

- 現場通訊混亂，缺乏統一指揮頻道
- 傷員資訊分散，無法即時彙整
- 傳統 START 初篩依賴人工判斷，缺乏輔助決策

### 1.2 技術選型決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| AI 推理引擎 | Qwen 2.5 14B（Ollama 本地） | 離線部署，不依賴雲端，符合災害現場斷網場景 |
| 語音辨識 | Whisper Large-v3（FastAPI） | 高精度、多語言，RTX 2060 可即時推理 |
| 主要通訊協議 | TCP + Bonjour 自動發現 | 零設定，前線裝置開機即可連線，無需手動輸入 IP |
| 長距離通訊 | LoRa（Heltec WiFi LoRa 32 V3） | SX1262 最遠 5 km，適合建築廢墟場景 |
| 資料庫 | SQLite WAL 模式 | 無伺服器依賴，USB 備份可行，單機即完整 |
| iOS/macOS 開發 | SwiftUI + NWListener/NWConnection | 原生效能，支援 BLE/Bonjour/UDP 多通道 |
| Android 開發 | Kotlin + Coroutines | 協程非同步，NSD 服務發現 |

### 1.3 硬體配置定案

| 裝置 | 角色 | 主要任務 |
|------|------|----------|
| RTX 3080 桌機 | 推理伺服器 | Qwen 2.5 14B、START 評分、TCP/HTTP、MQTT、PWS、USB 備份 |
| RTX 2060 筆電 | 語音辨識 | Whisper Large-v3、FastAPI :8002 |
| M2 MacBook Air | 指揮中心 | LinkGuardHQ macOS、31.5 吋外接顯示 |
| iPad Air M2 | 現場醫療站 | LinkGuard iPadOS 傷員列表 |
| iOS 手機 | 現場終端 | LinkGuard iOS 回報 + 電台 |
| Android 手機 | 現場終端 | LinkGuard Android 回報 + 電台 |
| RT-AX1800S 路由器 | 區網骨幹 | 指揮站 WiFi，連接所有裝置 |
| Heltec LoRa 32 V3 | 現場通訊節點 | ESP32-S3 + SX1262，長距離廣播 |

---

## 二、第一次稽核（2025-04-06）

### 2.1 稽核範圍

- Python 後端（`win11/`）
- iOS 前端（`linkguardMB/linkguard/`）
- Android 前端（`linkguardMB/Android/`）

### 2.2 發現問題

| 等級 | 數量 | 說明 |
|------|------|------|
| P0 — 執行時中斷 | 3 | 會在執行中產生錯誤或完全無法運作 |
| P1 — 資料不完整 | 6 | 不會 crash 但資料遺漏或語意偏差 |
| P2 — 風格不一致 | 7 | 次要觀察，不影響核心功能 |

**P0 清單**

| # | 問題描述 | 定位 |
|---|---------|------|
| P0-1 | iOS 照片上傳目標埠 `:8003`，應為 `:8004`（`photo_server.py` 監聽 8004） | `PhotoReportView.swift` L206 |
| P0-2 | Android 會報上傳 hardcode fallback IP `192.168.50.34` | `RadioScreen.kt` L619 |
| P0-3 | iOS（扁平 payload）與 Android（巢狀 payload）patient 封包結構不一致 | `CommandEngine.swift` / `CommandClient.kt` |

**P1 清單**

| # | 問題描述 |
|---|---------|
| P1-1 | iOS `RadioReport` 遺失 `patientsCount`、`audioUrl`、`weather` 欄位 |
| P1-2 | iOS `RadioControlPayload.senderName` 使用 camelCase，Python 慣例為 snake_case |
| P1-3 | Android `text_broadcast`/`translate_request` 缺少 `device_id` |
| P1-4 | Android `translate_request` 缺少 `context: "medical"` 欄位 |
| P1-5 | `report_summary` 廣播不含 `timestamp` |
| P1-6 | HQ `HQCommandServer.swift` 翻譯端點硬編碼 `127.0.0.1:8001` |

---

## 三、Phase 1 — P0 緊急修復

**對應問題**：P0-1、P0-2

### 修復項目

| 修復項目 | 影響範圍 | 說明 |
|---------|---------|------|
| iOS 照片上傳埠 `:8003` → `:8004` | `PhotoReportView.swift` | `http_server.py`（:8003）無 `/photo` 路由，`photo_server.py`（:8004）才有 |
| Android fallback IP 移除 | `RadioScreen.kt` | 改為提示「需先連線指揮中心」，避免打到錯誤主機 |

### 修復後驗證

- iOS 照片上傳：HTTP 200，`photo_server.py` 正確接收並回傳縮圖 URL ✅
- Android 會報上傳：`serverHost` 為空時顯示錯誤提示，不再誤發請求 ✅

---

## 四、第二次審計（2025-07）

### 4.1 審計範圍

完整 12 條數據流端到端追蹤：

| # | 數據流 |
|---|--------|
| 1 | 傷員回報（Patient Report） |
| 2 | GPS 位置更新（Location） |
| 3 | 即時語音廣播（PTT UDP） |
| 4 | 固定會報（Briefing Report） |
| 5 | 照片回報（Photo Upload） |
| 6 | AI 指揮決策（Decision） |
| 7 | 氣象推播（Weather） |
| 8 | 資源管理（Resource） |
| 9 | 即時統計（Stats） |
| 10 | 即時通訊（Chat） |
| 11 | SOS 緊急呼叫 |
| 12 | LoRa 節點狀態 |

### 4.2 新發現問題（Phase 1 後殘留）

| 等級 | # | 問題 | 定位 |
|------|---|------|------|
| P0 | 4 | HQ BackendBridge 缺少 5 種訊息類型處理（`report_summary`、`voice_broadcast_rx`、`stats_update`、`resource_update`、`photo_alert`） | `HQBackendBridge.swift` |
| P0 | 5 | TCP Server location 資料未持久化到資料庫（只存 in-memory dict，`locations` 表永遠為空） | `tcp_server.py` location handler |
| P1 | 6 | HQ Bridge 轉發決策時缺少氣象資料（`HQDecisionPayload` 未傳 `weather`） | `HQBackendBridge.swift` decision handler |
| P1 | 7 | HQ Bridge 轉發傷員報告缺少 `notes` 欄位 | `HQBackendBridge.swift` forwardPatient |
| P1 | 8 | Bonjour/NSD 服務類型衝突（`tcp_server.py` 和 `HQCommandServer.swift` 都註冊 `_linkguard._tcp`） | 兩處 Bonjour 註冊 |

---

## 五、Phase 2 — 後端與 HQ Bridge 修復

**對應問題**：P0-4、P0-5、P1-6（舊）、P1-7、P1-8

### 修復項目

| 修復項目 | 影響範圍 | 說明 |
|---------|---------|------|
| HQ BackendBridge 5 handler 補齊 | `HQBackendBridge.swift` | 新增 `report_summary`、`voice_broadcast_rx`、`stats_update`、`resource_update`、`photo_alert` 完整處理 |
| tcp_server location 持久化 | `tcp_server.py` | `location` handler 呼叫 `linkguard_db.save_location()`，`locations` 表正常寫入，stats_server 統計恢復正確 |
| HQ Bridge 決策 weather 補齊 | `HQBackendBridge.swift` | `HQDecisionPayload` 建構時傳入 `weather`，前線裝置 DecisionView 氣象欄位顯示正常 |
| HQ Bridge 傷員 `notes` 補齊 | `HQBackendBridge.swift` | `forwardPatient()` 的 patientData dict 加入 `notes`，Qwen AI 可獲得完整備註資訊 |

### Phase 2 後驗證

- `stats_server.py` 統計：`wifi_devices` 和 `personnel` 計數正確 ✅
- 前線裝置 DecisionView：顯示完整氣象欄位 ✅
- AI 決策：備註資訊正常納入 Qwen 分析 ✅

---

## 六、Mac HQ 完整中繼轉發規範定案（2026-04-10）

### 6.1 架構確立

Mac HQ 定位為**唯一中繼層**，所有前線裝置流量 100% 經由 Mac HQ 轉發，不直接連線 Windows 後端：

```
前線裝置 (iOS/Android)
    ↕ TCP :8930 (Bonjour _linkguard-hq._tcp)
Mac HQ (M2 Air)
    ↕ TCP :9000 (HQBackendBridge)
Windows 後端 (3080 主機)
```

### 6.2 上行訊息類型（前線 → Mac → Windows）共 19 種

| msgType | Mac 本地處理 | Windows 轉發 |
|---------|------------|------------|
| `status_report` | 更新 fieldUnits | `forwardStatusReport()` |
| `location` | 更新 deviceLocations | `forwardLocation()` |
| `patient` | 加入 patientReports + timeline | `forwardPatient()` |
| `chat_message` | 中繼給其他裝置 | `forwardChat()` |
| `quick_status` | 中繼廣播 + timeline | `forwardQuickStatus()` |
| `task_update` | 更新 tasks + timeline | `forwardTaskUpdate()` |
| `hazard_report` | 中繼廣播 + timeline | `forwardHazardReport()` |
| `reinforcement_request` | 中繼廣播 + timeline | `forwardReinforcementRequest()` |
| `reinforcement_reply` | 中繼廣播 | `forwardReinforcementReply()` |
| `radio_control` | 更新 currentBroadcaster | `forwardRadioControl()` |
| `radio_report` | Apple Speech 辨識 | `forwardVoiceResult()` |
| `sos` | 中繼 sos_alert + timeline | `forwardSOS()` |
| `sos_cancel` | 中繼 sos_cancel_alert + timeline | `forwardSOSCancel()` |
| `photo_alert` | 中繼廣播 + photoAlerts | `forwardPhotoAlert()` |
| `text_broadcast` | 中繼 + 已讀追蹤 | `forwardTextBroadcast()` |
| `message_ack` | 更新 readStatuses | `forwardMessageAck()` |
| `translate_request` | 呼叫 qwen_server /translate | `forwardTranslateRequest()` |
| `patient_warning` | 中繼廣播 + timeline | `forwardPatientWarning()` |
| `ping` | 回覆 pong（不轉發） | — |

### 6.3 下行訊息類型（Windows → Mac → 前線）共 8 種

| type | Mac 處理 | 前線轉發 |
|------|---------|---------|
| `decision` | 儲存 backendDecisions | `broadcastDecision()` |
| `weather_update` | 儲存 backendWeather | `broadcastPWSAlert()` |
| `node_status` | 更新 loraNodes | ❌ 僅 HQ 本地顯示 |
| `report_summary` | — | `relayBackendJSON()` |
| `voice_broadcast_rx` | — | `relayBackendJSON()` |
| `stats_update` | 更新 latestStatsUpdate | `relayBackendJSON()` |
| `resource_update` | 更新 latestResourceUpdate | `relayBackendJSON()` |
| `photo_alert` | 更新 photoAlerts | `relayBackendJSON()` |

---

## 七、Phase 3 — Mac-Only 架構建立

**背景**：展示環境確認以 M2 Air 為唯一 HQ 中繼節點，需要在 Windows 後端不可用時 Mac 仍能獨立運作。

### 修復與新增項目

| 項目 | 說明 |
|------|------|
| Mac 嵌入式 SpeechServer（:8003） | 使用 Apple Speech 取代 Whisper，無需 2060 筆電 |
| Mac 嵌入式 PhotoServer（:8004） | 本地照片存取，照片存 `~/Documents/LinkGuardData/photos/` |
| 本地統計計算 `computeLocalStats()` | 取代 `stats_server.py`，本地計算 wifi_devices / personnel |
| 本地資源計算 `computeLocalResources()` | 取代 `resource_server.py` |
| 翻譯離線 fallback | 後端不可用時回傳「翻譯服務不可用」，避免 UI 卡死 |
| HQ 翻譯端點動態化 | 優先使用 BackendBridge host，無連線時使用 `127.0.0.1` 作 fallback |
| tcp_server 4 handler 補齊 | 補完 `text_broadcast`、`translate_request`、`message_ack`、`patient_warning` |
| DecisionView trigger 標籤 | iOS DecisionView 顯示完整觸發類型文字 |

---

## 八、git commit — 2026-04-14 23:44

**提交 SHA**：`783536e`  
**訊息**：`feat: 更新 Bonjour 服務類型為 _linkguard-hq，優化自動發現與連接功能`

### 變更摘要

本次為 LinkGuard Beta V0.1 的首次完整代碼推送，包含：

**Python 後端（win11/）— 完整服務群**

| 服務 | 埠口 | 說明 |
|------|------|------|
| `tcp_server.py` | 9000 | TCP 聚合中樞、Bonjour `_linkguardpy._tcp`、AI 呼叫、訊息送達重試（最多 3 次，TTL 5 分鐘） |
| `qwen_server.py` | 8001 | Qwen 2.5 14B 本地推理（Ollama），`/generate` + `/translate` |
| `whisper_server.py` | 8002 | Whisper Large-v3 語音辨識（FastAPI，部署於 2060 筆電） |
| `http_server.py` | 8003 | 前線會報上傳（multipart）+ Web Dashboard |
| `photo_server.py` | 8004 | 照片上傳（壓縮 + 縮圖）+ 存取 |
| `stats_server.py` | 8005 | 每 30 秒廣播系統統計 |
| `resource_server.py` | 8006 | 救援資源追蹤與 CRUD |
| `udp_server.py` | 9001 | UDP 即時語音中繼（PCM 16 kHz mono，MAGIC `0x4C474244`） |
| `mqtt_broker.py` | 1883 | MQTT v5 Broker，LoRa 節點狀態訂閱 |
| `linkguard_db.py` | — | SQLite WAL（8 張資料表：decisions、patients、radio_reports、photos、lora_nodes、stats、resources、locations） |
| `start_triage.py` | — | START 初篩 + 六維度加權評分（黑/紅/黃/綠） |
| `pws_fetcher.py` | — | 氣象局 CWA Open Data API（站 ID：C0A980） |
| `utils.py` | — | `get_local_ip`、`now_iso`、`generate_msg_id` |
| `usb_backup.py` | — | 雙備份機制（USB + 本地） |

**iOS/iPadOS 前線應用（linkguardMB/linkguard/）**

- 15 分頁 TabView（iPhone/iPad 自適應，iPad 顯示側邊欄）
- 節點 ID 格式：`RT-{3 位 HEX}`，持久化於 UserDefaults
- 雙通道：TCP WiFi（指揮訊息）+ BLE（LoRa 近端）+ UDP（語音）
- 完整功能：傷員回報、PTT 電台、會報上傳、照片上傳、AI 翻譯、模擬引擎

**macOS HQ 指揮中心（linkguardMB/LinkGuardHQ/）**

- Bonjour 服務類型：`_linkguard-hq._tcp.local.`（本次提交更名，避免與 `tcp_server` 衝突）
- 31 個 Swift 檔案：Dashboard、Patient Warning、Photo Wall、Radio、Briefing、Zone Map、Personnel、Timeline、Decision、Chat、Notification

**Android 前線應用（linkguardMB/Android/）**

- Kotlin + Coroutines，NSD 服務發現（NSD 對應 Bonjour）
- 完整 15 個 Screen，資料模型與 iOS 對齊

**Android HQ（linkguardMB/LinkGuardHQ-Android/）**

- 14 個 Kotlin 檔案，16 分頁 HQ Dashboard，Port 8930 TCP Server

**LoRa 韌體（linkguardMB/LoRa/）**

- `hq.ino`：HQ 節點，912 MHz
- `rescue.ino`：搜救節點，910 MHz
- `victim.ino`：受困者節點，910 MHz
- BLE 近端：iOS/Android ↔ Heltec LoRa 32 V3（ESP32-S3 + SX1262）

**測試（win11/tests/）**

| 測試檔案 | 涵蓋範圍 |
|---------|---------|
| `test_start_triage.py` | START 四級分類、六維度計分 |
| `test_triage.py` | 檢傷邏輯邊界案例 |
| `test_tcp_server.py` | TCP 聚合邏輯（需 pytest-asyncio） |
| `test_http_server.py` | HTTP 端點 |
| `test_qwen_server.py` | Qwen AI 整合 |
| `test_mqtt_broker.py` | MQTT 節點狀態 |
| `test_pws_fetcher.py` | 氣象 API 擷取 |
| `test_delivery.py` | 訊息送達追蹤重試邏輯 |
| `test_api_format.py` | JSON 封包格式驗證 |

**規格文件**

- `README.md`（雙語：繁中 + English）
- `DEVELOPMENT_SPEC.md`（完整系統開發提示詞，1299 行）
- `JSON_FORMAT_SPEC.md`（14 種 msgType 規範，724 行）
- `AUDIT_REPORT.md`、`DATA_CHAIN_AUDIT.md`
- `files/` 目錄：6 份規範 markdown + 4 份 docx

**服務埠口總覽（截至此提交）**

| 服務 | 埠口 | 狀態 |
|------|------|------|
| HQCommandServer | 8930 | ✅ `_linkguard-hq._tcp`（本次更名） |
| tcp_server | 9000 | ✅ `_linkguardpy._tcp` |
| qwen_server | 8001 | ✅ |
| whisper_server | 8002 | ✅ |
| http_server | 8003 | ✅ |
| photo_server | 8004 | ✅ |
| stats_server | 8005 | ✅ |
| resource_server | 8006 | ✅ |
| udp_server | 9001 | ✅ |
| mqtt_broker | 1883 | ✅ |

---

## 九、git commit — 2026-04-15 00:04

**提交 SHA**：`c17f9ee`  
**訊息**：`feat(mac-only): hard-cut windows forwarding for core photo/speech/translation path`

### 背景

科展展示環境確定：以 M2 Air 為唯一 HQ 中繼節點，Windows 後端負責 AI 推理，但照片、語音辨識、翻譯等路徑改由 Mac 本地處理，不再繞道 Windows。

### 變更細節

| 檔案 | 行數變化 | 說明 |
|------|---------|------|
| `HQCommandServer.swift` | -138 行 | 刪除所有 `backendBridge?.forward*()` 呼叫中的 Windows 轉發路徑（`status_report`、`chat_message`、`quick_status`、`task_update`、`hazard_report`、`reinforcement_request`、`reinforcement_reply`、`location`）|
| `HQPhotoServer.swift` | +17 行 | 精簡照片轉發邏輯至 Mac 本地路徑 |
| `HQSpeechServer.swift` | -10 行 | 移除 Windows 語音辨識中繼，僅保留 Apple Speech 本地辨識 |
| `HQViewModel.swift` | -22 行 | 清除 Windows IP 設定相關欄位與顯示元素 |
| `VoiceInputManager.swift` | +2/-1 行 | 更新語音識別目標端點至 Mac 本地 SpeechServer |

**整體效益**：`HQCommandServer.swift` 從 ~220 行複雜雙路徑邏輯縮減至 ~82 行清晰的 Mac-only 邏輯。

### 最終架構（Mac-Only 模式）

```
前線裝置 (iOS/Android)
    │  HTTP multipart
    ▼
Mac HQPhotoServer (:8004)   ← 照片直接存 Mac 本地
Mac HQSpeechServer (:8003)  ← Apple Speech 本地辨識（無需 2060 筆電）

前線裝置 → HQCommandServer → translate_request → qwen_server (:8001)
  ↑ 無後端時回傳「翻譯服務不可用」

Mac HQ → HQBackendBridge → tcp_server (:9000) → Qwen AI (:8001) → 決策廣播
```

---

## 十、START 檢傷評分系統

### 10.1 兩層機制

**第一層：START 初篩**（粗篩，立即分級）

```
步驟 1：行走能力？
  ├─ 可行走 → 🟢 綠色（MINOR）
  └─ 不可行走 →
       步驟 2：自主呼吸？
         ├─ 無呼吸 → ⬛ 黑色（DECEASED）
         └─ 有呼吸 →
              步驟 3：循環（毛細血管充填）
                ├─ > 2 秒 → 🔴 紅色（IMMEDIATE）
                └─ ≤ 2 秒 →
                     步驟 4：意識（遵循指令）
                       ├─ 否 → 🟡 黃色（DELAYED）＋start_bonus=30
                       └─ 是 → 🔴 紅色（IMMEDIATE）
```

**第二層：六維度加權評分**（精排，同分再分高下）

| 維度 | 權重 | 評分項目範例 |
|------|------|------------|
| 生命危急程度（vitals） | ×1.5 | 呼吸困難(40)、大量出血(50)、心跳微弱(30) |
| 時間壓力（time_pressure） | ×1.4 | 1 小時內惡化(40)、3 小時內惡化(25) |
| 存活可能性（survival） | ×1.3 | 高存活(30)、極低存活(-40) |
| 傷勢嚴重度（injury） | ×1.2 | 重傷-內出血(40)、中等-骨折(20) |
| 環境風險（environment） | ×1.1 | 火災/瓦斯(40)、建築可能倒塌(30) |
| 救援成本（rescue_cost） | ×1.0 | 需大量人力(-15)、單人可處理(5) |

**輸出**：`Total Score = START 加成 + Σ(原始分數 × 維度權重)`，降序排列決定救援優先序；同分時 START 紅標優先。

---

## 十一、已知問題追蹤

| # | 問題 | 等級 | 狀態 |
|---|------|------|------|
| 1 | iOS 與 Android patient 封包結構不一致（iOS 扁平 / Android 巢狀） | P0 | ⚠️ 已知，`normalize_message()` 相容處理 |
| 2 | iOS `RadioReport` 遺失 `patientsCount`、`audioUrl`、`weather` | P1 | ⚠️ 待修復 |
| 3 | Android `text_broadcast`/`translate_request` 缺少 `device_id` | P1 | ⚠️ 待修復 |
| 4 | Android `translate_request` 缺少 `context: "medical"` | P1 | ⚠️ 待修復 |
| 5 | `report_summary` 廣播不含 `timestamp` | P1 | ⚠️ 建議修復 |
| 6 | Python IP 偵測（8.8.8.8）在離線環境 fallback 到 127.0.0.1 | P2 | ⚠️ 待處理 |
| 7 | Android 無照片上傳功能 | P2 | ⚠️ 功能缺失 |
| 8 | Bonjour/NSD 服務衝突（tcp_server 與 HQCommandServer） | P1 | ✅ 已解（Bonjour type 更名） |

---

## 十二、測試覆蓋狀態

| 平台 | 狀態 | 備註 |
|------|------|------|
| Python 後端 | ✅ 141 tests 全部通過 | `cd win11 && python -m pytest tests/ -v` |
| Android Rescue | ✅ BUILD SUCCESSFUL | Gradle build |
| Android HQ | ✅ BUILD SUCCESSFUL | Gradle build |
| iOS/macOS | ⚠️ 需 Xcode 實機編譯驗證 | 程式碼審查通過 |

**Python 測試執行指令**：

```bash
cd win11 && python -m pytest tests/ -v
```

> **注意**：以下測試存在已知的前置問題（非本次引入）：
> - `test_tcp_server.py`：需要 `pytest-asyncio`
> - `test_http_server.py`：引用不存在的 `_get_local_ip`
> - `test_qwen_server.py`：DB 路徑設定問題

---

## 十三、科展展示準備（目標 2026-04-23）

### 待完成事項

- [ ] 統一 iOS/Android patient 封包格式為巢狀結構（P0-3）
- [ ] iOS `RadioReport` 補齊 `patientsCount`、`audioUrl`、`weather`（P1-1）
- [ ] Android `text_broadcast`/`translate_request` 補齊 `device_id` 與 `context`（P1-3/P1-4）
- [ ] `http_server.py` report_data 加入 `timestamp`（P1-5）
- [ ] 離線環境 IP 偵測 fallback 改善（P2-3）
- [ ] 全裝置整合壓力測試（所有 8 台裝置同時連線）
- [ ] USB 備份驗證

### 展示架構確認

```
iPad Air M2（傷員列表）
iOS 手機（前線回報）        WiFi TCP :8930
Android 手機（前線回報） ────────────────► M2 Air HQ（LinkGuardHQ）
                                                    │ TCP :9000
                                                    ▼
                                    RTX 3080（Python 後端）
                                    ├─ Qwen 2.5 14B (Ollama)
                                    └─ SQLite DB + USB 備份
                                    │
                                    ▼
                            RTX 2060（Whisper）   ← 如 Mac 嵌入式 Speech 不足用時備援
                                    │
                                    ▼
                    Heltec LoRa 32 V3（HQ/Rescue/Victim 三節點）
```

---

---

## 十四、2026-05-06 開發日誌

### 14.1 概述

本次作業集中於 iOS 現場端（`linkguard`）與 macOS 指揮端（`LinkGuardHQ`）的穩定性修復，並完整移除通話語音功能模組。

---

### 14.2 修復：NFC 簽署授權錯誤（實機建置阻斷）

**問題**：使用個人開發團隊（Personal Team）簽署時，`linkguard.entitlements` 中包含 `com.apple.developer.nfc.readersession.formats`，該能力不受 Personal Team 支援，導致實機 Archive/Build 失敗。

**解法**：從 `linkguard.entitlements` 移除 NFC 授權鍵值，保留空 `<dict/>`。  
NFC 掃描程式碼保留於 `PatientFormView.swift`（純執行時呼叫，不影響編譯與簽署）。

**結果**：`generic/platform=iOS` 建置成功（EXIT_STATUS=0）。

---

### 14.3 修復：`PatientIDConfig` 找不到型別（編譯錯誤）

**問題**：`LinkGuardModels.swift` 中 `PersonnelAssignment` struct 的大括號縮排錯誤，導致其後宣告的 `PatientIDConfig` struct 被誤判為在前一 struct 內部，引發 `cannot find type 'PatientIDConfig' in scope` 編譯錯誤。

**解法**：修正 `PersonnelAssignment` 結尾大括號位置，使 `init` / `CodingKeys` / `Decoder` 正確收束於 struct 內，`PatientIDConfig` 還原至頂層作用域。

**結果**：編譯錯誤解除，模擬器與實機建置均通過（EXIT_STATUS=0）。

---

### 14.4 確認：FieldNotificationView 詳情頁已完整

確認 `FieldNotificationView.swift` 已針對所有 7 類通知實作 `NavigationLink` 詳情頁：
- 活動日誌、個人通知、HQ 廣播、決策通知、氣象警報、情況簡報、人員調度

---

### 14.5 功能移除：完整移除通話語音模組

**決策**：通話語音功能因架構複雜度與展示需求不符，決定從 iOS 現場端與 macOS 指揮端完整移除。

#### 14.5.1 刪除檔案

| 刪除檔案 | 說明 |
|----------|------|
| `linkguardMB/linkguard/FieldCallView.swift` | 現場端通話介面 |
| `linkguardMB/linkguard/CallAudioManager.swift` | 現場端通話音訊管理 |
| `linkguardMB/linkguard/CallKitManager.swift` | iOS CallKit 整合 |
| `linkguardMB/LinkGuardHQ/LinkGuardHQ/HQCallView.swift` | 指揮端通話介面 |
| `linkguardMB/LinkGuardHQ/LinkGuardHQ/HQCallAudioManager.swift` | 指揮端通話音訊管理 |

#### 14.5.2 修改檔案

| 檔案 | 移除內容 |
|------|----------|
| `linkguardMB/linkguard/LinkGuardModels.swift` | `CallStatus`、`CallInvite`、`CallResponse`、`CallEnd`、`CallSession` struct |
| `linkguardMB/LinkGuardHQ/LinkGuardHQ/HQModels.swift` | 同上（指揮端） |
| `linkguardMB/linkguard/ContentView.swift` | `AppTab.call` 列舉、`IncomingCallOverlay`、`CommunicationHubMode.call` 分頁 |
| `linkguardMB/linkguard/LinkGuardViewModel.swift` | 全部通話狀態屬性、callback 設定、`startCall/acceptCall/declineCall/endCall` |
| `linkguardMB/CommandEngine.swift` | `onCallInvite/onCallResponse/onCallEnd` callback；`case "call_invite/call_response/call_end"` 分派；`sendCallInvite/Response/End()` |
| `linkguardMB/NotificationManager.swift` | `CALL_INVITE` 通知類別；`sendCallInviteNotification()` |
| `linkguardMB/LinkGuardHQ/LinkGuardHQ/HQDashboardView.swift` | `HQSection.call` 列舉、導覽順序、圖示、面板內容、顏色設定 |
| `linkguardMB/LinkGuardHQ/LinkGuardHQ/HQViewModel.swift` | `callAudioManager`、通話狀態訂閱、`startCall/endCall/toggleCallMute()` |
| `linkguardMB/LinkGuardHQ/LinkGuardHQ/HQCommandServer.swift` | 通話邀請/回應/結束 handler 與中繼函式 |
| `linkguardMB/linkguard/L10n.swift` | 所有通話相關翻譯字串 |
| `linkguardMB/LinkGuardHQ/LinkGuardHQ/L10n.swift` | 所有通話相關翻譯字串（指揮端） |

#### 14.5.3 驗證結果

- 殘留符號搜尋（`CallInvite`、`CallStatus`、`CallSession` 等）：**0 筆符合**
- 殘留檔案搜尋（`*Call*`、`*call*`）：**0 筆符合**
- 建置驗證（模擬器）：**EXIT_STATUS=0**
- Xcode 診斷（`get_errors`）：**No errors found**

---

### 14.6 建置狀態（本日結束）

| 目標 | 結果 |
|------|------|
| iOS 模擬器（iphonesimulator） | ✅ EXIT_STATUS=0 |
| iOS 實機（generic/platform=iOS） | ✅ EXIT_STATUS=0 |
| Xcode 診斷錯誤 | ✅ 無 |
| 通話模組殘留 | ✅ 無 |

---

> 日誌版本：1.1 | 最後更新：2026-05-06

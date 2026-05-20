# LinkGuard — 審計與修復報告

> 合併資料鏈稽核報告 + 數據鏈審計報告

新竹高工 × 新竹數位實中 ｜ 科展展示版本 2026

---

## 一、埠號總覽

| 服務 | Python 設定 | iOS 使用 | Android 使用 | Mac HQ | Android HQ | 狀態 |
|------|------------|---------|-------------|--------|-----------|------|
| TCP Command Server (HQ) | — | 8930 (Bonjour) | 8930 (NSD) | 8930 (Server) | 8930 (Server) | ✅ |
| TCP Server (Python) | 9000 | — | — | 9000 (Bridge) | 9000 (Bridge) | ✅ |
| Qwen AI | 8001 | — | — | 8001 (翻譯) | — | ✅ |
| Whisper STT | 8002 | — | — | — | — | ✅ |
| HTTP Report | 8003 | 8003 ✅ | 8003 ✅ | 8003 (SpeechServer) | — | ✅ |
| Photo Server | 8004 | 8004 ✅ | — | 8004 (PhotoServer) | — | ✅ |
| Stats Server | 8005 | — | — | (本地計算) | — | ✅ |
| Resource Server | 8006 | — | — | (本地計算) | — | ✅ |
| UDP Audio | 9001 | 9001 ✅ | 9001 ✅ | 9001 (中繼) | — | ✅ |
| UDP Relay Out | 9002 | — | — | 9002 (中繼輸出) | — | ✅ |
| MQTT | 1883 | — | — | — | — | ✅ |

---

## 二、P0 — 資料鏈中斷（嚴重）

### P0-1｜iOS 照片上傳埠號錯誤（8003 → 8004）

| 項目 | 內容 |
|------|------|
| **檔案** | `linkguardMB/linkguard/PhotoReportView.swift` L206 |
| **原況** | `http://{serverHost}:8003/photo` |
| **修正** | 改為 `:8004/photo` |
| **狀態** | ✅ **已修復** |

### P0-2｜Android 會報上傳硬編碼 fallback IP

| 項目 | 內容 |
|------|------|
| **檔案** | `linkguardMB/Android/.../RadioScreen.kt` L619 |
| **原況** | `serverHost` 為空時 fallback 到 `192.168.50.34` |
| **修正** | 改為提示「需先連線指揮中心」 |
| **狀態** | ✅ **已修復** |

### P0-3｜iOS 與 Android patient 封包結構不一致

| 項目 | 內容 |
|------|------|
| **iOS** | `{msgType:"patient", payload:"{id, breathing_rate, ...}"}` — 扁平結構 |
| **Android** | `{msgType:"patient", payload:"{type:'patient', data:{...}}"}` — 巢狀結構 |
| **影響** | `normalize_message()` 正規化後結構一致，目前可正常運作，但跨平台維護風險 |
| **狀態** | ⚠️ 已知問題，建議統一格式 |

### P0-4｜HQ BackendBridge 缺少 5 種訊息處理

| 項目 | 內容 |
|------|------|
| **檔案** | `LinkGuardHQ/HQBackendBridge.swift` |
| **缺少** | `report_summary`, `voice_broadcast_rx`, `stats_update`, `resource_update`, `photo_alert` |
| **狀態** | ✅ **已修復**（全部 5 種 handler 已加入） |

### P0-5｜TCP Server 位置資料未持久化到資料庫

| 項目 | 內容 |
|------|------|
| **檔案** | `win11/tcp_server.py` location handler |
| **原況** | 只存 in-memory dict，未呼叫 `linkguard_db.save_location()` |
| **影響** | `locations` 表永遠為空 → stats_server 統計永遠為 0 |
| **狀態** | ✅ **已修復** |

---

## 三、P1 — 資料不完整或語意偏差

### P1-1｜iOS `RadioReport` 遺失伺服器回傳的欄位

| 項目 | 內容 |
|------|------|
| **iOS** | `RadioReport` 只有 `id, senderName, timestamp, transcription, location, reportId` |
| **Android** | 包含完整 `patientsCount, audioUrl, weather` |
| **狀態** | ⚠️ 待修復 |

### P1-2｜iOS `RadioControlPayload.senderName` camelCase

| 項目 | 內容 |
|------|------|
| **現況** | iOS 序列化為 `"senderName"` (camelCase) |
| **風險** | Python 慣例為 `sender_name`，目前 Python 只轉發不影響，未來增加處理可能壞掉 |
| **狀態** | ⚠️ 低風險 |

### P1-3｜Android `text_broadcast` 與 `translate_request` 缺少 `device_id`

| 項目 | 內容 |
|------|------|
| **Android** | payload 內不含 `device_id`，正規化後為空 |
| **iOS** | 有包含 `device_id` |
| **狀態** | ⚠️ 待修復 |

### P1-4｜Android `translate_request` 缺少 `context` 欄位

| 項目 | 內容 |
|------|------|
| **Android** | `{text, source_lang, target_lang}`，缺少 `context` |
| **iOS** | 包含 `"context": "medical"` |
| **狀態** | ⚠️ 待修復 |

### P1-5｜`report_summary` 廣播不含 `timestamp`

| 項目 | 內容 |
|------|------|
| **影響** | 輕微（Android 用 `System.currentTimeMillis()` 預設） |
| **狀態** | ⚠️ 建議加入 |

### P1-6｜HQ 翻譯端點硬編碼 `127.0.0.1:8001`

| 項目 | 內容 |
|------|------|
| **原況** | `URL(string: "http://127.0.0.1:8001/translate")` |
| **修正** | 改為動態 `translateHost`（優先 backend bridge host，fallback 127.0.0.1）+ 離線 fallback |
| **狀態** | ✅ **已修復** |

### P1-7｜HQ Bridge 轉發決策缺少氣象資料

| 項目 | 內容 |
|------|------|
| **原況** | `HQDecisionPayload` 建構時未傳入 `weather` |
| **狀態** | ✅ **已修復** |

### P1-8｜HQ Bridge 轉發傷員報告缺少 `notes`

| 項目 | 內容 |
|------|------|
| **原況** | `notes` 未包含在 patientData dict |
| **狀態** | ✅ **已修復** |

### P1-9｜Bonjour/NSD 服務類型衝突

| 項目 | 內容 |
|------|------|
| **問題** | `tcp_server` 和 `HQCommandServer` 都註冊 `_linkguard._tcp` |
| **風險** | 前線裝置可能誤連 tcp_server |
| **狀態** | ⚠️ 建議修改 tcp_server 服務名稱 |

---

## 四、P2 — 風格不一致或次要觀察

| # | 問題 | 影響 | 狀態 |
|---|------|------|------|
| P2-1 | `patients_snapshot` 使用 camelCase（兩端一致） | 無功能影響 | 已知 |
| P2-2 | Android `WeatherSnapshot` 內部欄位名與 wire 不同 | 解析正確 | 已知 |
| P2-3 | Python `8.8.8.8` IP 偵測法在離線環境失效 | fallback 到 127.0.0.1 | ⚠️ |
| P2-4 | `JSON_FORMAT_SPEC.md` 範例硬編碼 IP | 文件問題 | 已知 |
| P2-5 | iOS `message_ack` rawJSON vs Android WiFiMessage | 正規化後相容 | 已知 |
| P2-6 | HQ :8930 與 Python :9000 分離 | 設計決策非 bug | 已知 |
| P2-7 | Android 無照片上傳功能 | 功能缺失 | 待實作 |
| P2-8 | iOS/Android 傷員 `device_id` 位置不一致 | 不影響 triage_START | 已知 |

---

## 五、數據流追蹤總結

### 已驗證的 9 條數據流

| # | 數據流 | 路徑 | 狀態 |
|---|--------|------|------|
| 1 | 傷員回報 | iOS/Android → HQ → BackendBridge → tcp_server → qwen → decision → 回推 | ✅ |
| 2 | GPS 位置 | 前線 → HQ → BackendBridge → tcp_server → save_location() | ✅ 已修 |
| 3 | PTT 語音 | 前線 → UDP:9001 → udp_server → whisper → voice_result → broadcast | ✅ |
| 4 | 固定會報 | 前線 → POST :8003/report → whisper → report_summary → broadcast | ✅ 已修 |
| 5 | 照片回報 | iOS → POST :8004/photo → photo_alert → broadcast → HQ | ✅ 已修 |
| 6 | AI 決策 | tcp_server → qwen:8001/generate → decision → broadcast → HQ → 前線 | ✅ 已修 |
| 7 | 氣象推播 | pws_fetcher → tcp_server → weather_update → HQ → 轉為 PWSAlert | ✅ |
| 8 | 資源管理 | resource_server:8006 → resource_update → tcp_server → HQ | ✅ 已修 |
| 9 | 即時統計 | stats_server:8005 → stats_update → tcp_server → HQ | ✅ 已修 |

---

## 六、修復歷程

| 日期 | 修復項目 | 影響範圍 |
|------|---------|---------|
| Phase 1 | iOS 照片埠 8003→8004 | PhotoReportView.swift |
| Phase 1 | Android fallback IP 移除 | RadioScreen.kt |
| Phase 2 | HQ BackendBridge 5 handler 補齊 | HQBackendBridge.swift |
| Phase 2 | tcp_server location 持久化 | tcp_server.py |
| Phase 2 | HQ Bridge 決策 weather 補齊 | HQBackendBridge.swift |
| Phase 2 | HQ Bridge 傷員 notes 補齊 | HQBackendBridge.swift |
| Phase 3 | HQ 翻譯端點動態化 + 離線 fallback | HQCommandServer.swift |
| Phase 3 | Mac 嵌入式 SpeechServer | HQSpeechServer.swift (新增) |
| Phase 3 | Mac 嵌入式 PhotoServer | HQPhotoServer.swift (新增) |
| Phase 3 | 本地統計計算 | HQCommandServer.swift |
| Phase 3 | tcp_server 4 handler 補齊 | tcp_server.py (text_broadcast, translate_request, etc.) |
| Phase 3 | DecisionView trigger labels | iOS DecisionView.swift |

---

## 七、測試狀態

- **Python 後端**：141 tests **全部通過** ✅
- **Android Rescue**：BUILD SUCCESSFUL ✅
- **Android HQ**：BUILD SUCCESSFUL ✅
- **iOS/macOS**：程式碼審查通過（需 Xcode 實機編譯驗證）

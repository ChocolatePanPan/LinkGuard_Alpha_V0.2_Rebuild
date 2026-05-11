# LinkGuard 資料鏈稽核報告

> 稽核日期：2025-04-06  
> 範圍：Python 後端（win11/）、iOS 前端（linkguardMB/linkguard/）、Android 前端（linkguardMB/Android/）  
> 本報告為**唯讀審查**，不含任何程式碼修改。

---

## 執行摘要

共發現 **3 個 P0**、**6 個 P1**、**7 個 P2** 問題。  
最嚴重的 P0 包括：iOS 照片上傳目標埠號錯誤、Android 會報上傳使用硬編碼 fallback IP、以及 iOS 與 Android 傳送 patient 封包結構不一致。

---

## 埠號總覽

| 服務 | Python 設定 | iOS 使用 | Android 使用 | 狀態 |
|------|------------|---------|-------------|------|
| TCP Command Server (HQ Swift) | — | 8930 (Bonjour) | 8930 (NSD) | ✅ |
| TCP Server (Python) | 9000 | — | — | ✅ |
| Qwen AI | 8001 | — | — | ✅ |
| Whisper STT | 8002 | — | — | ✅ |
| HTTP Report | 8003 | 8003 ✅ | 8003 ✅ | ✅ |
| Photo Server | **8004** | **8003** ❌ | — (無上傳) | **P0** |
| Stats Server | 8005 | — | — | ✅ |
| Resource Server | 8006 | — | — | ✅ |
| UDP Audio | 9001 | 9001 ✅ | 9001 ✅ | ✅ |
| MQTT | 1883 | — | — | ✅ |

---

## P0 — 資料鏈中斷（會在執行時產生錯誤）

### P0-1｜iOS 照片上傳埠號錯誤（8003 → 應為 8004）

| 項目 | 內容 |
|------|------|
| **檔案** | `linkguardMB/linkguard/PhotoReportView.swift` L206 |
| **現況** | `URL(string: "http://\(serverHost):8003/photo")` |
| **預期** | 應改為 `:8004/photo` |
| **影響** | `http_server.py`（8003）無 `/photo` 路由，iOS 照片上傳一律回傳 404。`photo_server.py` 監聽 8004 才有 `/photo` 端點。 |

### P0-2｜Android 會報上傳硬編碼 fallback IP `192.168.50.34`

| 項目 | 內容 |
|------|------|
| **檔案** | `linkguardMB/Android/app/src/main/java/com/linkguard/app/ui/screens/RadioScreen.kt` L619 |
| **現況** | `val host = if (serverHost.isNotEmpty()) serverHost else "192.168.50.34"` |
| **影響** | 當 `serverHost` 為空（HQ 未連線或 NSD 尚未解析完成），會把會報 POST 打到一個可能不存在的固定 IP。應改為提示「需先連線指揮中心」。 |

### P0-3｜iOS 與 Android 的 patient 封包結構不一致


| 項目 | 內容 |
|------|------|
| **iOS 檔案** | `linkguardMB/CommandEngine.swift` L531–L556（`sendPatientReport`） |
| **Android 檔案** | `Android/app/src/main/java/com/linkguard/app/net/CommandClient.kt` L694–L722（`sendPatientReport`） |
| **iOS 送出** | `{msgType:"patient", payload:"{id, breathing_rate, ..., device_id}"}` — payload 是**扁平結構**，無 `type` 欄位 |
| **Android 送出** | `{msgType:"patient", payload:"{type:'patient', data:{id, breathing_rate, ...}, device_id, timestamp}"}` — payload 包含**巢狀 type/data 結構** |
| **影響** | `tcp_server.py` L250–L270 `normalize_message()` 分兩條路徑處理：若 payload 含 `type` 欄位就直接回傳，否則用 `msgType` 包裹。**目前** 兩者正規化後結構一致，能正常運作；但如果 HQ CommandServer（Swift）中繼邏輯對格式有預設假設，或未來 tcp_server 變更正規化邏輯，其中一個平台就會壞掉。建議統一為同一格式。 |

---

## P1 — 資料不完整或語意偏差（不會 crash 但資料遺漏）

### P1-1｜iOS `RadioReport` 遺失伺服器回傳的欄位

| 項目 | 內容 |
|------|------|
| **檔案** | `linkguardMB/linkguard/LinkGuardModels.swift` L993–L1006（`RadioReport`）|
| **現況** | iOS `RadioReport` struct 只有 `id, senderName, timestamp, transcription, location, reportId`，不含 `patientsCount`、`audioUrl`、`weather`。|
| **對比** | Android `RadioReport`（Models.kt L798）包含完整 `patientsCount, audioUrl, weather` 欄位。|
| **影響** | 當 ViewModel 收到 `report_summary` 並建立 `RadioReport` 時，傷患數量、音檔 URL、天氣快照資訊在 iOS 端全部丟失。|

### P1-2｜iOS `RadioControlPayload.senderName` 沒有 CodingKeys 映射

| 項目 | 內容 |
|------|------|
| **檔案** | `linkguardMB/linkguard/LinkGuardModels.swift` L1034–L1037 |
| **現況** | `struct RadioControlPayload: Codable { let action: String; let senderName: String }` — JSON 序列化為 camelCase `"senderName"` |
| **對比** | tcp_server.py 對 `radio_control` type 只是原樣轉發。若 Python 端未來新增處理邏輯預期 `sender_name`（Python 慣例），就會讀不到。 |
| **風險** | 目前不會壞（Python 只轉發），但跨語言慣例不一致，增加未來維護風險。 |

### P1-3｜Android `text_broadcast` 與 `translate_request` 缺少 `device_id`

| 項目 | 內容 |
|------|------|
| **Android 檔案** | `Android/app/src/main/java/com/linkguard/app/net/CommandClient.kt` L831–L860 |
| **現況** | Android 的 `sendTextBroadcast` 和 `sendTranslateRequest` 透過 WiFiMessage 格式送出，payload 內不含 `device_id`。正規化後 `device_id` 為空。 |
| **對比** | iOS `sendTextBroadcast`（CommandEngine.swift L613）和 `sendTranslateRequest`（L626）使用 `sendRawJSON`，有包含 `device_id`。 |
| **影響** | 伺服器無法識別 Android 廣播與翻譯請求的來源裝置。 |

### P1-4｜Android `translate_request` 缺少 `context` 欄位

| 項目 | 內容 |
|------|------|
| **Android 檔案** | `Android/app/src/main/java/com/linkguard/app/net/CommandClient.kt` L845–L860 |
| **現況** | Android payload = `{text, source_lang, target_lang}`，缺少 `context` 欄位。 |
| **對比** | iOS `sendTranslateRequest`（CommandEngine.swift L626–L637）包含 `"context": "medical"` 欄位。 |
| **影響** | 若 qwen_server `/translate` 端點使用 context 做情境翻譯，Android 請求會得到較不精確的醫療翻譯。 |

### P1-5｜`report_summary` 廣播不含 `timestamp` 欄位

| 項目 | 內容 |
|------|------|
| **Python 檔案** | `win11/http_server.py`（`upload_report` 函數 → 組建 `report_data` dict） |
| **現況** | `report_data` 包含 `report_id, sender_name, transcription, location_desc, patients_count, weather, audio_url`，但不含 `timestamp`。 |
| **影響** | iOS `RadioReportSummary` CodingKeys 本來就沒映射 `timestamp`（無影響）。Android 讀取 `c.optDouble("timestamp", 0.0)` 得到 0.0，但 `RadioReport` 建構時使用 `System.currentTimeMillis()` 作為預設值（影響輕微）。建議在 `report_data` 加入原始上傳時間。 |

### P1-6｜HQ CommandServer 翻譯端點硬編碼 `127.0.0.1:8001`

| 項目 | 內容 |
|------|------|
| **檔案** | `linkguardMB/LinkGuardHQ/LinkGuardHQ/HQCommandServer.swift` L834 |
| **現況** | `URL(string: "http://127.0.0.1:8001/translate")` |
| **影響** | 若 Qwen AI 服務部署在不同機器上，HQ 翻譯中繼功能無法運作。所有其他 Python 服務之間用 `TCP_SERVER_HOST = "127.0.0.1"` 是因為它們都在同一台 Windows 上，但 HQ（iPad/Mac）不見得在同一台。 |

---

## P2 — 風格不一致或次要觀察

### P2-1｜`patients_snapshot` 使用 camelCase（`heartRate`、`isSOS`）

| 項目 | 內容 |
|------|------|
| **iOS** | `RadioView.swift` L449：`["id": v.id, "heartRate": v.heartRate, "isSOS": v.isSOS, "isOnline": v.isOnline]` |
| **Android** | `RadioScreen.kt` L614：`put("heartRate", v.heartRate)` |
| **Python** | `http_server.py` 未解析此欄位，僅以字串存入 DB。 |
| **備註** | 兩個平台一致使用 camelCase，不影響功能；但與 Python 端 patient 欄位的 snake_case 慣例不同。 |

### P2-2｜Android `WeatherSnapshot` 內部欄位名稱與 wire 格式不同

| 項目 | 內容 |
|------|------|
| **檔案** | `Android/app/src/main/java/com/linkguard/app/model/Models.kt` L760–L765 |
| **現況** | `val temp` 對應 wire 的 `"temperature"`；`val wind` 對應 wire 的 `"wind_speed"`。 |
| **備註** | 解析程式碼有正確映射，不影響功能，但增加認知成本。iOS 使用 `temperature` 和 `wind_speed`（與 wire 一致）。 |

### P2-3｜Python 後端使用 `8.8.8.8` 偵測本機 IP

| 項目 | 內容 |
|------|------|
| **檔案** | `win11/photo_server.py` L48、`win11/http_server.py` L114 |
| **影響** | 在無網際網路的離線救災環境中，此技巧會失敗並 fallback 到 `127.0.0.1`，導致 `audio_url` 和 `thumbnail_url` 回傳 localhost URL，行動裝置無法存取。 |

### P2-4｜`JSON_FORMAT_SPEC.md` 範例使用硬編碼 IP

| 項目 | 內容 |
|------|------|
| **檔案** | `JSON_FORMAT_SPEC.md` L304 |
| **現況** | 範例 `audio_url` 為 `http://192.168.50.34:8003/audio/RPT-...` |
| **備註** | 規格文件範例與實際動態產生的 URL 格式不符（實際為 `http://{local_ip}:8003/audio/{report_id}`）。容易誤導開發者。 |

### P2-5｜iOS `message_ack` 使用 rawJSON，Android 使用 WiFiMessage

| 項目 | 內容 |
|------|------|
| **iOS** | `CommandEngine.swift` L596–L606：`sendRawJSON` → `{type:"message_ack", device_id, timestamp, data:{...}}` |
| **Android** | `CommandClient.kt` L805–L817：WiFiMessage → `{msgType:"message_ack", payload:"{message_id, message_type}"}` |
| **備註** | 正規化後結構相容，但 Android 版本缺少 `device_id` 和 `timestamp`。 |

### P2-6｜CommandServer（Swift HQ）使用 port 8930，與 Python tcp_server 9000 分離

| 項目 | 內容 |
|------|------|
| **檔案** | `CommandEngine.swift` L110（port 8930）vs `tcp_server.py`（port 9000） |
| **備註** | 這是設計決策而非 bug。行動裝置透過 Bonjour/NSD 連接 HQ（8930），HQ 再轉發至 Python 後端（9000）。但開發者需意識到行動裝置不會直接連接 Python tcp_server。 |

### P2-7｜Android 無照片上傳功能

| 項目 | 內容 |
|------|------|
| **現況** | Android 只有 `onPhotoAlert` 接收通知，沒有照片上傳 UI 或 HTTP 上傳程式碼。 |
| **備註** | 功能缺失而非 bug。iOS 有完整的 `PhotoReportView`。 |

---

## 各資料流摘要

### 1. Patient Report（傷員回報）
- **iOS** → WiFiMessage(patient) 扁平 payload → HQ → tcp_server → normalize → `{type:"patient", data:{id, breathing_rate, capillary_refill, can_follow_commands, location, gps, notes}}` ✅
- **Android** → WiFiMessage(patient) 巢狀 payload → HQ → tcp_server → normalize → 同上結構 ✅
- **欄位名稱**：兩端統一使用 snake_case（`breathing_rate`、`capillary_refill`、`can_follow_commands`）✅
- **DB 儲存**：`linkguard_db.save_patient()` 有 `patient_id/id` 和 `location_desc/location` 雙重 fallback ✅
- **問題**：P0-3（結構不一致）

### 2. Voice / Radio（即時語音）
- **UDP 音訊**：iOS 與 Android 均使用 port 9001、MAGIC `0x4C474244`、PCM 16kHz mono、相同 binary header ✅
- **radio_control**：兩端均送 `{action, senderName}` (camelCase) ✅
- **問題**：P1-2（senderName camelCase 與 Python 慣例不一致）

### 3. Report / Briefing（固定會報）
- **上傳端點**：`http://{host}:8003/report` — iOS ✅ Android ✅ Python ✅
- **表單欄位**：`audio, device_id, sender_name, location_lat, location_lon, location_desc, patients_snapshot, weather_snapshot, timestamp` — 三端完全一致 ✅
- **問題**：P0-2（Android fallback IP）

### 4. Weather（氣象）
- **Python → 廣播**：`{temperature, humidity, wind_speed, rainfall}` (snake_case)
- **iOS WeatherSnapshot**：`temperature, humidity, wind_speed, rainfall` ✅ 完全匹配
- **Android WeatherSnapshot**：解析時正確讀取 snake_case → 儲存為 `temp, humidity, wind, rainfall` ✅
- **問題**：P2-2（Android 內部命名不同但映射正確）

### 5. Photo Upload（照片）
- **Python `photo_server.py`**：port 8004、`/photo` 端點
- **iOS**：上傳至 port **8003** ❌
- **Android**：無上傳功能
- **問題**：P0-1、P2-7

### 6. Stats / Resources（統計/資源）
- **Python**：stats_server (8005) 每 30 秒推送 `stats_update`；resource_server (8006) 推送 `resource_update`
- **Android**：接收 `stats_update` 和 `resource_update` 並更新 UI ✅
- **iOS**：透過 ViewModel 接收 ✅
- **無問題**

### 7. Decision（AI 決策）
- **Python → qwen_server**：回傳 `{decision, patients}`
- **tcp_server 廣播**：`{msgType:"decision", payload:"{decision, patients}"}`
- **iOS**：`HQDecisionPayload` 解碼，缺少的 `timestamp/trigger/weather` 有預設值 ✅
- **Android**：`optString("decision_id", "")` 取空值，其餘有預設 ✅
- **無阻斷問題**（但自動決策路徑不含 weather/trigger 資訊）

### 8. Location / GPS
- **iOS**：`sendLocation` → `{lat, lon, accuracy, role, name, device_id}` (扁平 payload)
- **Android**：`sendLocation` → `{type:"location", data:{lat, lon, accuracy, role, name}, device_id, timestamp}` (巢狀)
- **正規化後一致** ✅（但 Android data 內不含 `device_id`，iOS 的 data 內含 `device_id`；tcp_server 兩邊都能取到）

### 9. Chat（通訊頻道）
- **兩端均使用 WiFiMessage `chat_message`** ✅
- **欄位**：`id, senderID, senderName, recipientID, content, timestamp, isRead` — 一致 ✅

### 10. Hardcoded IPs（硬編碼 IP）
| 檔案 | IP | 用途 | 風險 |
|------|----|------|------|
| `RadioScreen.kt` L619 | `192.168.50.34` | 會報上傳 fallback | **P0-2** |
| `HQCommandServer.swift` L834 | `127.0.0.1:8001` | 翻譯中繼 | **P1-6** |
| `photo_server.py` L48 | `8.8.8.8` | IP 偵測 | P2-3 |
| `http_server.py` L114 | `8.8.8.8` | IP 偵測 | P2-3 |
| `photo_server.py` L25 | `127.0.0.1` | tcp_server 連線 | ✅ 同機器 |
| `stats_server.py` L18 | `127.0.0.1` | tcp_server 連線 | ✅ 同機器 |
| `resource_server.py` L18 | `127.0.0.1` | tcp_server 連線 | ✅ 同機器 |
| `whisper_server.py` L11 | `127.0.0.1` | tcp_server 連線 | ✅ 同機器 |
| `http_server.py` L20 | `127.0.0.1` | tcp_server 連線 | ✅ 同機器 |
| `JSON_FORMAT_SPEC.md` L304 | `192.168.50.34` | 文件範例 | P2-4 |

---
## 建議優先修復順序

1. **P0-1**：iOS `PhotoReportView.swift` L206 — 將 `:8003` 改為 `:8004`
2. **P0-2**：Android `RadioScreen.kt` L619 — 移除硬編碼 IP，改為檢查連線狀態
3. **P0-3**：統一 iOS 與 Android 的 patient 封包為同一格式（建議採用巢狀格式，與 location 保持一致）
4. **P1-1**：iOS `RadioReport` 加入 `patientsCount, audioUrl, weather` 欄位
5. **P1-3/P1-4**：Android `text_broadcast` 和 `translate_request` 加入 `device_id` 和 `context`
6. **P1-5**：Python `http_server.py` 在 `report_data` 加入 `timestamp`
7. **P1-6**：HQ `HQCommandServer.swift` 翻譯端點使用設定值而非硬編碼 `127.0.0.1`
# LinkGuard — 全平台功能規範

> iOS / iPadOS / macOS HQ / Android Rescue / Android HQ 完整功能一覽

新竹高工 × 新竹數位實中 ｜ 科展展示版本 2026

---

## 一、iOS 前線應用 (linkguard)

### 1.1 應用入口 (linkguardApp.swift)

```swift
@main struct linkguardApp: App {
    WindowGroup {
        ContentView
            .preferredColorScheme(.dark)  // 強制暗色模式
            .tint(NV.green)              // 夜視儀螢光綠主色
    }
}
```

### 1.2 主畫面結構 (ContentView.swift)

**導航架構**：`TabView(.sidebarAdaptable)` — iPad 自動轉為側邊欄

**AppTab enum（15 個分頁）**：

| 分頁名稱 | 圖示 | View | Badge |
|---------|------|------|-------|
| 總覽 | gauge | DashboardView | — |
| **通訊 TabSection** | | | |
| 電台 | antenna.radiowaves | RadioView | — |
| 通訊 | bubble | FieldChatView | 未讀數 |
| 指揮決策 | megaphone.fill | DecisionView | 決策數 |
| 災情 | building.2 | FieldDisasterView | — |
| SOS | exclamationmark.triangle | SOSRecordListView | SOS 數 |
| **其他 TabSection** | | | |
| 受困者 | person.wave.2 | — | 受困者數 |
| 增援 | person.badge.plus | — | 待處理數 |
| 團隊 | person.3.fill | — | — |
| 命令 | megaphone.fill | — | 未讀數 |
| 通知 | bell.fill | FieldNotificationView | 未讀數 |
| 傷員回報 | cross.case.fill | PatientFormView | — |
| 翻譯 | character.book.closed | TranslatorView | — |
| 照片 | photo.on.rectangle | PhotoReportView | — |
| 連線 | link | — | — |

**全螢幕覆蓋層**：
- `CommandAlertOverlay` — Critical 命令全螢幕提醒
- `ReinforcementAlertOverlay` — 增援請求覆蓋
- `SOSAlertOverlay` — SOS 全螢幕警報

**Dashboard 區塊**：

```
1. 標題列 + 系統狀態指示燈（模擬/BLE/WiFi）
2. 統計卡片 Grid（iPad 4 欄 / iPhone 2 欄，使用 horizontalSizeClass）
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

### 1.3 核心 ViewModel (LinkGuardViewModel.swift)

**節點識別**：

```
Device ID：RT-{隨機 3 位 HEX}（如 RT-A3F）
  └─ 持久化：UserDefaults["linkguard_node_hex_id"]

Node ID：RT-{HEX}-{DEPT}（如 RT-A3F-EMT）
  └─ 部門碼：EMT(救護) / FD(消防) / PD(警察)
  └─ 持久化：UserDefaults["linkguard_dept_code"]
```

**@Published 狀態（40+ 項）**：

| 分類 | 屬性 | 說明 |
|------|------|------|
| 節點自身 | `victims: [VictimNode]` | 受困者列表 |
| | `sosRecords: [SOSRecord]` | SOS 記錄 |
| | `nodeStatus: RescueNodeStatus` | 節點自身狀態 |
| | `teamMembers: [TeamMember]` | 團隊成員 |
| | `isBluetoothConnected: Bool` | BLE 連線 |
| WiFi 指揮 | `commandOrders: [CommandOrder]` | 指揮命令列表 |
| | `latestCriticalCommand` | 最新危急命令（全螢幕覆蓋） |
| | `reinforcementRequests` | 增援請求列表 |
| 災害/任務 | `disasterSite: DisasterSite` | 災害狀態 |
| | `chatMessages: [ChatMessage]` | 聊天訊息 |
| | `pwsAlerts: [PWSAlert]` | PWS 警報 |
| | `briefings: [BriefingReport]` | 會報 |
| | `personalNotifications` | 個人通知 |
| | `tasks: [TaskAssignment]` | 任務 |
| | `countdownTimers` | 倒數計時 |
| | `hazardReports: [HazardReport]` | 危險標記 |
| | `radioReports` | 電台會報 |
| UI 控制 | `isSimulating: Bool` | 模擬模式 |
| | `uptimeSeconds: Int` | 運行時間 |

**定時任務**：

| 定時器 | 週期 | 功能 |
|--------|------|------|
| 模擬更新 | 2 秒 | SimulationEngine 更新受困者數據 |
| 運行計時 | 1 秒 | uptimeSeconds++ |
| 狀態回報 | 10 秒 | sendStatusReport() → HQ |
| GPS 回報 | 15 秒 | sendLocationUpdate() → tcp_server |
| 危急震動 | 持續 | Critical 命令持續震動提醒 |

**WiFi 回呼（15+ 個）**：

| 回呼 | 來源 msgType | 處理 |
|------|-------------|------|
| `onCommand(WiFiCommand)` | `command` | 解析為 CommandOrder |
| `onChatMessage(ChatMessage)` | `chat_message` | 加入聊天列表 |
| `onDisasterUpdate(DisasterSite)` | `disaster_update` | 更新災害狀態 |
| `onPersonnelAssignment` | `personnel_assignment` | 更新人員配置 |
| `onPWSAlert(PWSAlert)` | `pws_alert` | 加入警報 + AlarmPlayer |
| `onBriefing(BriefingReport)` | `briefing` | 加入會報 |
| `onPersonalNotification` | `personal_notification` | 加入通知 |
| `onTaskAssignment` | `task_assignment` | 加入任務 |
| `onTimerSync` | `timer_sync` | 同步倒數計時 |
| `onTimerCancel` | `timer_cancel` | 取消倒數計時 |
| `onHazardReport` | `hazard_report` | 加入危險標記 |
| `onReinforcementRequest` | `reinforcement_request` | 加入增援 |
| `onReinforcementReply` | `reinforcement_reply` | 更新增援狀態 |
| `onDecision(HQDecision)` | `decision` | 加入 AI 決策 |
| `onReportSummary` | `report_summary` | 加入會報摘要 |
| `onRadioControl` | `radio_control` | PTT 控制 |

### 1.4 資料模型 (LinkGuardModels.swift)

**VictimNode（受困者）**：

| 欄位 | 說明 |
|------|------|
| `id: String` | VT-{HEX} |
| `heartRate: Int` | BPM（0=無資料） |
| `battery: Int` | 0-100% |
| `rssi: Double` | dBm |
| `snr: Double` | 信噪比 |
| `isSOS: Bool` | 是否 SOS |
| `lastSeen: Date` | 最後連線 |
| `isOnline: Bool` | 30 秒 timeout |
| `estimatedDistance: Double` | 公式：d = 10^((A-rssi)/(10*n)), A=-30, n=2.7 |

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

**CommandType（指揮命令類型）**：`search`, `standby`, `support`, `report`, `evacuation`, `medical`, `logistics`, `communication`, `alert`, `statusReport`, `zoneAssignment`, `hazardWarning`, `briefingUpdate`, `resourceRequest`, `shiftChange`, 全面撤離、暫停搜索、繼續搜索、集合、裝備檢查...

**災害相關枚舉**：

| 枚舉 | 值 |
|------|---|
| CollapseType | partial, pancake, lean, vShape, none, unknown |
| FloorCondition | collapsed, partial, accessible, cleared, restricted, unknown |
| ZoneStatus | active, standby, cleared, dangerous, restricted |
| HazardType | gasLeak, fire, flooding, structural, electrical, chemical |
| PWSAlertType | earthquake, aftershock, tsunami, typhoon, flood, landslide, other |
| PWSSeverity | info, minor, moderate, severe, extreme (Comparable) |
| BriefingType | initial, progress, shift, final |
| PersonnelRole | search, rescue, medical, logistics, safety, commander, support |

### 1.5 語音錄音 (VoiceInputManager.swift)

```
格式：MPEG4 AAC
樣本率：44100 Hz / mono / high quality

上傳：POST multipart/form-data
  URL: http://{serverHost}:8002/transcribe
  Field: "file" (audio/mp4)
  Timeout: 30 秒
```

### 1.6 模擬引擎 (SimulationEngine.swift)

**初始受困者池**：VT-A3F (HR:78, SOS:✅), VT-B72 (HR:92, SOS:❌), VT-C1E (HR:0, SOS:✅)

**模擬更新（2 秒週期）**：
- RSSI 漂移：-3 ~ +3 dBm
- SNR 漂移：-0.5 ~ +0.5
- 心率漂移：-3 ~ +3 bpm
- 電量衰減：每 15 次更新 -1%
- 上線/離線：30 秒無更新 → 離線
- 新受困者/SOS 切換：低機率隨機

---

## 二、macOS HQ 指揮中心 (LinkGuardHQ)

### 2.1 應用入口 (LinkGuardHQApp.swift)

```swift
@main struct LinkGuardHQApp: App {
    @StateObject var vm = HQViewModel()
    WindowGroup {
        HQDashboardView(vm: vm)
    }
    .defaultSize(width: 1200, height: 800)
}
```

### 2.2 核心 ViewModel (HQViewModel.swift)

**雙角色模式**：

| 模式 | 說明 |
|------|------|
| `.server` | 本機啟動 TCP 伺服器 (8930)，接收前線連線 |
| `.peer` | 連接至其他 HQ 伺服器，同步全部狀態 |

**PADOS 多裝置定向指揮**：
- `.broadcast` → 廣播全體（effectiveTargetIDs = nil）
- `.selected` → 指定裝置群（effectiveTargetIDs = [deviceID1, ...]）

### 2.3 HQ Dashboard 側邊欄 (HQDashboardView.swift)

**HQSection enum（17 個分區）**：

| Section | 標籤 | 圖示 | View |
|---------|------|------|------|
| dashboard | 儀表板 | gauge.with.dots.needle.33percent | HQDashboardOverview |
| disaster | 災害狀態 | building.2 | HQDisasterView |
| personnelOverview | 人員總覽 | person.3.sequence.fill | HQPersonnelOverviewView |
| victimOverview | 受困者總覽 | person.fill.questionmark | HQVictimOverviewView |
| personnel | 人員配置 | person.badge.plus | HQPersonnelView |
| chat | 通訊頻道 | bubble.left.and.bubble.right.fill | HQChatView |
| pws | PWS 警報 | exclamationmark.triangle.fill | HQPWSView |
| briefing | 會報系統 | doc.text.fill | HQBriefingView |
| notification | 個人通知 | bell.fill | HQNotificationView |
| timeline | 事件日誌 | clock.arrow.circlepath | HQTimelineView |
| zonemap | 分區地圖 | map.fill | HQZoneMapView |
| reports | 會報儀表板 | doc.richtext | HQReportsDashboardView |
| decision | 指揮決策 | gavel | HQDecisionView |
| photoWall | 照片牆 | photo.on.rectangle.angled | HQPhotoWallView |
| **stats** | **統計儀表板** | chart.bar.xaxis | HQStatsDashboardView |
| **resources** | **資源管理** | shippingbox | HQResourceView |
| **usarCommand** | **USAR 指揮鏈** | point.3.connected.trianglepath.dotted | HQUSARCommandView |

**USAR / INSARAG 頁面對齊標準**：

| 頁面角色 | INSARAG 對齊重點 |
|---------|------------------|
| UCC | 事件目標、分區/工作點優先序、派令與資源、安全監督、SITREP/ASR 回收 |
| Sector Commander | Sector 邊界、通道、工作點節奏、資源請求、分區 SITREP |
| Worksite Manager | Worksite 控制點、ASR 1-5、危害、RCM/標記、小隊派工 |
| Squad Leader | 任務確認、狀態回報、危害/資源請求、醫療後送、撤離或完成 |

所有 USAR 角色頁都必須顯示對應的 INSARAG 作業節奏與檢核項，並以正式 USAR 封包同步到 `USAROperationStore`。

### 2.4 HQ 指揮伺服器 (HQCommandServer.swift)

**TCP 伺服器**：Port 8930, Bonjour `_linkguard._tcp / LinkGuard-CMD`

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

| 方法 | 推播內容 |
|------|---------|
| `broadcastCommand(WiFiCommand, targetDeviceIDs?)` | 命令推播 |
| `broadcastDisasterUpdate(DisasterSite)` | 災害狀態 |
| `broadcastPersonnelAssignment([PersonnelAssignment])` | 人員配置 |
| `broadcastPWSAlert(PWSAlert)` | PWS 警報 |
| `broadcastBriefing(BriefingReport)` | 會報 |
| `sendPersonalNotification(PersonalNotification, to:)` | 個人通知 |
| `broadcastTaskAssignment(TaskAssignment)` | 任務 |
| `broadcastCountdownTimer(CountdownTimerModel)` | 倒數計時 |
| `broadcastDecision(HQDecision)` | AI 決策 |

**本地統計 + HQ UDP 音訊中繼**：
- UDP 接收 port 9001 → 中繼 port 9002
- Magic `0x4C474244` ("LGBD") 驗證

### 2.5 HQ Peer 同步 (HQPeerClient.swift)

以 `hq_peer` role 連線至另一台 HQ，同步所有狀態：命令、聊天、災害狀態、人員配置、PWS 警報、會報、個人通知、時間線、任務、倒數計時、危險標記、增援。

### 2.6 完整 HQ Swift 檔案清單（31 檔）

| 檔案 | 說明 |
|------|------|
| LinkGuardHQApp.swift | macOS App 入口 |
| HQDashboardView.swift | 主介面+側邊欄（含收合模式） |
| HQViewModel.swift | 主 ViewModel |
| HQCommandServer.swift | TCP 伺服器 (8930) + Bonjour + UDP 音訊中繼 (9001/9002) |
| HQBackendBridge.swift | 連接 Win11 backend TCP 9000 |
| HQPeerClient.swift | HQ 同伴連線客戶端 |
| HQModels.swift | 資料模型 |
| **HQPhotoServer.swift** | 內嵌照片伺服器 (8004) — Mac-Only |
| **HQSpeechServer.swift** | 內嵌語音辨識伺服器 (8003) — Mac-Only |
| HQBluetoothManager.swift | BLE 管理 |
| SerialManager.swift | 序列通訊管理 |
| NightVisionTheme.swift | NV 深色主題 |
| DeviceTargetSelector.swift | PADOS 裝置目標選擇器 |
| HQDisasterView.swift | 災害狀態頁 |
| HQPersonnelOverviewView.swift | 人員總覽頁 |
| HQVictimOverviewView.swift | 受困者總覽頁 |
| HQPersonnelView.swift | 人員配置頁 |
| HQChatView.swift | 通訊頻道頁 |
| HQPWSView.swift | PWS 警報頁 |
| HQBriefingView.swift | 會報系統頁 |
| HQBroadcastView.swift | 廣播頁 |
| HQNotificationView.swift | 個人通知頁 |
| HQTimelineView.swift | 事件日誌頁 |
| HQZoneMapView.swift | 分區地圖頁 |
| HQReportsDashboardView.swift | 會報儀表板頁 |
| HQDecisionView.swift | 指揮決策頁 |
| HQPhotoWallView.swift | 照片牆頁 |
| **HQStatsDashboardView.swift** | 統計儀表板頁 |
| **HQResourceView.swift** | 資源管理頁 |
| HQPatientWarningView.swift | 傷員警告頁 |
| LinkGuardHQ.entitlements | 權限設定 |

---

## 三、Android Rescue 前線應用 (linkguardMB/Android)

### 3.1 應用入口 (MainActivity.kt)

- 使用 `calculateWindowSizeClass(this)` 支援平板響應式佈局
- 傳入 `windowSizeClass` 至 `MainScreen`

### 3.2 主畫面 (MainScreen.kt) — 響應式佈局

**平板 `!Compact`**：`NavigationRail` 左側導航欄 + 內容區
**手機 `Compact`**：底部 `ScrollableTabRow`

**15 個分頁**：

| 分頁 | Badge | 說明 |
|------|-------|------|
| 總覽 | — | DashboardScreen |
| 受困者 | — | VictimScreen |
| SOS | SOS 數 | SOSScreen |
| 災情 | — | DisasterScreen |
| 通訊 | 未讀數 | ChatScreen |
| 增援 | 待處理 | ReinforcementScreen |
| 團隊 | — | TeamScreen |
| 命令 | 未讀數 | CommandScreen |
| 通知 | 未讀數 | NotificationScreen |
| 電台 | — | RadioScreen |
| 傷員 | — | PatientFormScreen |
| 決策 | — | DecisionScreen |
| 翻譯 | — | TranslatorScreen |
| 照片 | — | PhotoScreen |
| 連線 | — | ConnectionScreen |

**從 Dashboard 跳轉回**：`cameFromDashboard` 膠囊按鈕

### 3.3 網路層

| 檔案 | 說明 |
|------|------|
| CommandClient.kt | WiFi 客戶端，連接 HQ:8930 via NSD |
| BluetoothManager.kt | BLE 連接 Heltec LoRa 節點 |

---

## 四、Android HQ 指揮中心 (LinkGuardHQ-Android)

### 4.1 完整檔案清單（14 檔 Kotlin）

| 檔案 | 說明 |
|------|------|
| **MainActivity.kt** | 入口，`calculateWindowSizeClass` 支援平板 |
| **net/HQCommandServer.kt** | TCP 伺服器 :8930，NSD 註冊 `_linkguard._tcp / LinkGuardHQ` |
| **net/HQBackendBridge.kt** | TCP 連接 Win11 backend :9000 |
| **net/HQPeerClient.kt** | HQ 同伴連線客戶端 |
| **viewmodel/HQViewModel.kt** | 主 ViewModel |
| **model/Models.kt** | 完整資料模型 |
| **ui/HQDashboardScreen.kt** | 主畫面，WindowSizeClass 響應式 |
| **ui/HQFeatureScreens.kt** | 災情/通訊/人員配置等合併頁面 |
| **ui/HQVictimOverviewScreen.kt** | 受困者總覽 |
| **ui/HQPersonnelOverviewScreen.kt** | 人員總覽 |
| **ui/PatientFormScreen.kt** | 傷員回報表單 |
| **ui/DecisionScreen.kt** | 指揮決策 |
| **ui/DeviceTargetSelector.kt** | PADOS 裝置目標選擇器 |
| **ui/Theme.kt** | NV 深色主題 |

### 4.2 HQDashboardScreen — 16 分頁

| 分頁 | 說明 |
|------|------|
| 總覽 | 即時概況 |
| 命令 | 下達指揮命令 |
| 外勤 | 外勤裝置列表 |
| 人員總覽 | 全局人員 |
| 受困者 | 受困者列表 |
| 災情 | 災害狀態 |
| 通訊 | 聊天頻道 |
| 人員 | 人員配置 |
| PWS | PWS 警報 |
| 會報 | 會報系統 |
| 通知 | 個人通知 |
| 傷員回報 | PatientFormScreen |
| 指揮決策 | DecisionScreen |
| 事件日誌 | Timeline |
| 分區地圖 | ZoneMap |
| 會報儀表板 | Reports Dashboard |

**響應式佈局**：
- 平板（`!Compact`）：側邊欄導航
- 手機：底部 `ScrollableTabRow`

### 4.3 HQCommandServer.kt

- Port `8930`
- NSD (Bonjour) 註冊 `_linkguard._tcp / LinkGuardHQ`
- 處理 msgType：`hello`, `hq_command`, `status_report`, `chat_message`, `decision`
- HQ Peer 支援：透過 `hq_peer` role 識別，同伴狀態推送

### 4.4 HQBackendBridge.kt

**發送**：`ping`, `request_decision`, `patient`, `voice_result`

**接收**：

| 訊息類型 | 處理 |
|---------|------|
| `decision` | AI 決策 → 解析 PatientDecisionEntry |
| `weather` | 氣象（目前未處理） |
| `pong` / `ack` | 心跳回應 |

### 4.5 Models.kt — 資料模型

完整模型：`DisasterSite`, `PersonnelAssignment`, `ChatMessage`, `PWSAlert`, `BriefingReport`, `WiFiCommand`, `ConnectedFieldUnit`, `HQDecision` 等

---

## 五、跨平台功能對照表

| 功能 | iOS | Android Rescue | macOS HQ | Android HQ |
|------|-----|---------------|----------|-----------|
| 傷員回報 | ✅ | ✅ | ✅ (中繼) | ✅ (中繼+表單) |
| PTT 電台 | ✅ | ✅ | ✅ (中繼) | — |
| 固定會報 | ✅ | ✅ | ✅ (中繼) | — |
| 照片上傳 | ✅ | ❌ | ✅ (本地伺服器) | — |
| AI 決策 | ✅ (接收) | ✅ (接收) | ✅ (觸發+接收) | ✅ (觸發+接收) |
| BLE LoRa | ✅ | ✅ | ✅ | — |
| 指揮命令 | ✅ (接收) | ✅ (接收) | ✅ (發送) | ✅ (發送) |
| 災害管理 | ✅ (接收) | ✅ (接收) | ✅ (發送) | ✅ (發送) |
| 人員配置 | ✅ (接收) | ✅ (接收) | ✅ (發送) | ✅ (發送) |
| PWS 警報 | ✅ (接收) | ✅ (接收) | ✅ (發送) | ✅ (發送) |
| 翻譯 | ✅ | ✅ | ✅ (中繼+離線) | — |
| 照片牆 | — | — | ✅ | — |
| 統計儀表板 | — | — | ✅ | — |
| 資源管理 | — | — | ✅ | — |
| Web Dashboard | — | — | — | — |
| 響應式平板 | ✅ (sidebarAdaptable) | ✅ (NavigationRail) | ✅ (sidebar) | ✅ (sidebar) |
| HQ Peer 同步 | — | — | ✅ | ✅ |

---

## 六、裝置 ID 格式規範

| 格式 | 範例 | 說明 |
|------|------|------|
| `RT-{3位HEX}` | RT-A3F | 基本裝置 ID |
| `RT-{HEX}-{DEPT}` | RT-A3F-EMT | 完整節點 ID（含部門） |
| `VT-{3位HEX}` | VT-001 | 受困者 ID |
| `HQ-{N}` | HQ-1 | HQ 節點 ID |
| `P{timestamp}` | P1712345678 | 傷員 ID |
| `RPT-YYYYMMDD-NNN` | RPT-20260406-001 | 會報 ID |

**部門碼**：`EMT`(救護) / `FD`(消防) / `PD`(警察)

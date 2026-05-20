# LinkGuard — LoRa 韌體規範

> Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262) 韌體

新竹高工 × 新竹數位實中 ｜ 科展展示版本 2026

---

## 一、硬體平台

**晶片**：ESP32-S3 + Semtech SX1262
**模組**：Heltec WiFi LoRa 32 V3
**頻率**：910 MHz（Field）/ 912 MHz（HQ）

---

## 二、三種韌體角色

### 2.1 受困端 (victim.ino)

**路徑**：`linkguardMB/LoRa/victim/victim.ino`

| 項目 | 規格 |
|------|------|
| 頻率 | 910 MHz |
| LoRa 參數 | SF9 / BW125 / CR 4/6（L4 profile） |
| 存取方式 | CSMA/CA |
| SOS | 按鍵觸發 |
| 心率模式 | `HR_MODE_SIM`（模擬）/ `HR_MODE_GARMIN`（Garmin BLE HRP 0x180D） |
| NVS 持久化 | 配對碼 + 模式 |
| 看門狗 | 30 秒 |

**BLE HRP 模式**：連接 Garmin 心率帶（Service UUID: 0x180D），讀取真實心率數據後透過 LoRa 發送。

### 2.2 搜救端 (rescue.ino)

**路徑**：`linkguardMB/LoRa/rescue/rescue.ino`

| 項目 | 規格 |
|------|------|
| 頻率 | 910 MHz |
| 9 級 LoRa Profile | L0–L8（與 iOS/Android 一致） |
| BLE 角色 | **GATT Server**（供 iOS/Android App 連接） |
| 追蹤 | VictimNode + TeamNode |

**BLE UUID（Field 端）**：

| 用途 | UUID |
|------|------|
| Service | `4FAFC201-1FB5-459E-8FCC-C5C9C331914B` |
| 狀態通知 (Notify) | `BEB5483E-36E1-4688-B7F5-EA07361B26A8` |
| 命令寫入 (Write) | `BEB5483E-36E1-4688-B7F5-EA07361B26AB` |
| LoRa 命令 (Notify) | `BEB5483E-36E1-4688-B7F5-EA07361B26AC` |

**BLE 狀態 JSON（Notify 推送）**：

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

**BLE 寫入命令**：

| 命令 | 格式 |
|------|------|
| 設定部門 | `setdept:EMT` |
| 設定檔位 | `setlvl:3` |
| 設定配對碼 | `setpair:1234` |
| 命令回執 | `cmd_ack:{cmdID}` |
| 增援請求 | `reinforce:{msg}\|{loc}` |
| 增援回覆 | `rf_reply:{team}\|{JOIN/NAK}` |
| 團隊 Ping | `team_ping` |

### 2.3 HQ 端 (hq.ino)

**路徑**：`linkguardMB/LoRa/hq/hq.ino`

| 項目 | 規格 |
|------|------|
| 頻率 | **912 MHz**（與前線 910 MHz 分離避免干擾） |
| BLE UUID | **專用**（與 Field 端不同） |
| 配對碼 | `"HQ00"` |
| 追蹤 | hqNodes（HQ 節點） |
| 命令 | 命令歷史記錄 |

---

## 三、LoRa 9 級 Profile

| 檔位 | SF | BW (kHz) | CR | 特性 | 適用場景 |
|------|----|---------|----|------|---------|
| L0 | 7 | 500.0 | 5 | 極速 | 近距離高速傳輸 |
| L1 | 7 | 250.0 | 5 | 高速 | 近距離 |
| L2 | 8 | 250.0 | 5 | 敏捷 | 中近距離 |
| L3 | 9 | 250.0 | 6 | 平衡 | 一般場景 |
| **L4** | **9** | **125.0** | **6** | **標準** | **預設檔位** |
| L5 | 10 | 125.0 | 7 | 穿透 | 遮蔽環境 |
| L6 | 10 | 62.5 | 8 | 強穿 | 建物穿透 |
| L7 | 11 | 62.5 | 8 | 極限 | 深度穿透 |
| L8 | 12 | 62.5 | 8 | 最遠 | 最大距離 |

---

## 四、LoRa 封包格式

### 4.1 受困者心跳封包

由 victim 節點定期發送，包含：
- 節點 ID
- 心率數據
- 電池電量
- SOS 狀態

### 4.2 指揮命令封包

由 HQ 端透過 LoRa 發送至所有 Rescue 節點：

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

Rescue 節點收到後透過 BLE Notify（UUID: `...26AC`）轉發至 iOS/Android App。

### 4.3 增援請求/回覆封包

- 增援請求：`reinforce:{msg}|{loc}` → LoRa 廣播
- 增援回覆：`rf_reply:{team}|{JOIN/NAK}` → LoRa 定向

---

## 五、距離估算

**公式**：

$$d = 10^{\frac{A - RSSI}{10 \times n}}$$

**參數**：
- $A = -30$ dBm（1 公尺參考值）
- $n = 2.7$（路徑損耗指數）

**距離文字**：
- < 1m → `"0.5m"`
- 1-100m → `"48m"`
- 100-1000m → `"350m"`
- ≥ 1000m → `"2.5km"`

---

## 六、頻率分離策略

| 角色 | 頻率 | 原因 |
|------|------|------|
| Victim（受困）| 910 MHz | 前線主頻 |
| Rescue（搜救）| 910 MHz | 與 Victim 同頻通訊 |
| HQ（指揮）| 912 MHz | 與前線分離，避免高流量干擾 |

HQ 節點使用獨立頻段（912 MHz）確保指揮命令不受前線大量心跳封包干擾。

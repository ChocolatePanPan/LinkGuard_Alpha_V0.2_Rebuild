# LinkGuard

**AI 災害Rescue Command System** — Hsinchu Industrial High School × Hsinchu Digital Experimental High School | Science Fair 2026

**AI 災害救援指揮系統** — 新竹高工 × 新竹數位實中 科展展示版 2026

> 🌐 [English](#english) | [中文](#中文)

---

<a name="english"></a>

## English

### Table of Contents

- [System Overview](#system-overview)
- [Hardware Configuration](#hardware-configuration)
- [Service Registry](#service-registry)
- [System Architecture](#system-architecture)
- [Key Features](#key-features)
- [Quick Start](#quick-start)
  - [Requirements](#requirements)
  - [Install Dependencies](#install-dependencies)
  - [Start Services](#start-services)
  - [Stop Services](#stop-services)
- [Python Backend Modules](#python-backend-modules)
- [Database Schema](#database-schema)
- [START Triage System](#start-triage-system)
- [Dual-Model AI Architecture](#dual-model-ai-architecture)
- [LoRa Node Communication](#lora-node-communication)
- [Testing](#testing)
- [License](#license)

---

### System Overview

LinkGuard is a disaster rescue command system that integrates AI decision-making, multi-device communication, and long-range LoRa wireless networking. Field devices (iOS/Android) collect casualty data, voice reports, and GPS coordinates over a local Wi-Fi network and send them to the command server. A three-tier Gemma4 large language model running locally on Ollama generates real-time rescue decisions, which are then broadcast to all connected devices. A dual-model configuration allows two PCs to cooperate: a small model (gemma4:e4b) handles rapid triage and automatically escalates difficult decisions to a large model (gemma4:26b) on the peer PC.

```
Field Devices (iOS / Android)
      │  Wi-Fi (TCP / HTTP / UDP / LGAP:8005)
      ▼
RTX 3080 Command Server ──► Gemma4 AI (Ollama, gemma4:26b standalone
      │                        or gemma4:e4b ↔ gemma4:26b dual-model)
      │                      Speech Recognition (Whisper Large-v3)
      │                      Weather Data (CWA Open Data API)
      │                      LoRa Node Status (MQTT)
      ▼
HQ (macOS LinkGuardHQ  OR  Windows hq_server.py)
      │  TCP :8930 + WebSocket :8080 dashboard
      ▼
iPad / iPhone / Android Field Stations
```

---

### Hardware Configuration

| Device | Role | Primary Task |
|--------|------|--------------|
| RTX 3080 Desktop (PC-A) | Inference Server | Gemma4 AI, START scoring, TCP, MQTT, PWS, backup |
| RTX 2060 Laptop | Speech Recognition | Whisper Large-v3, FastAPI |
| RTX 2060 / Second PC (PC-B) | Peer AI Server | Gemma4:26b deep analysis in dual-model mode |
| M2 MacBook Air | Command Centre (macOS) | LinkGuardHQ macOS, 31.5" external display |
| Windows HQ PC | Command Centre (Windows) | hq_server.py (TCP :8930 + LGAP :8005 + WS :8080) |
| iPad Air M2 | Field Medical Station | LinkGuard iPadOS casualty list |
| iOS Phone | Field Terminal | LinkGuard iOS reporting + radio |
| Android Phone | Field Terminal | LinkGuard Android reporting + radio |
| RT-AX1800S Router | LAN Backbone | Command station Wi-Fi, connects all devices |
| Heltec LoRa 32 V3 | Field Comm Node | ESP32-S3 + SX1262, long-range broadcast |

---

### Service Registry

| Service | Host | Port | Protocol | Description |
|---------|------|------|----------|-------------|
| `tcp_server` | 3080 Desktop | 9000 | TCP + Bonjour (`_linkguardpy._tcp`) | Aggregation hub: receive field messages, invoke AI, broadcast decisions |
| `gemma4_server` | 3080 Desktop | 8001 | HTTP (FastAPI) | Gemma4 AI decision engine (three-tier: e2b / e4b / 26b); dual-model peer on UDP 8011 |
| `whisper_server` | 2060 Laptop | 8002 | HTTP (FastAPI) | Whisper Large-v3 speech-to-text |
| `http_server` | 3080 Desktop | 8003 | HTTP (FastAPI) | Field report upload, static dashboard |
| `photo_server` | 3080 Desktop | 8004 | HTTP (FastAPI) | Photo upload and retrieval |
| `stats_server` | 3080 Desktop | 8005 | HTTP (FastAPI) | Statistics queries |
| `resource_server` | 3080 Desktop | 8006 | HTTP (FastAPI) | Rescue resource management |
| `udp_server` | 3080 Desktop | 9001 | UDP | Low-latency voice broadcast |
| `mqtt_broker` | 3080 Desktop | 1883 | MQTT v5 | LoRa node status aggregation |
| `HQCommandServer` | macOS HQ | 8930 | TCP + Bonjour (`_linkguard-hq._tcp`) | macOS command centre |
| `hq_server` | Windows HQ | 8930 / 8005 / 8080 | TCP + LGAP + WebSocket | Windows command centre alternative |

---

### System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   Wi-Fi Command Layer (TCP 8930)              │
│                                                              │
│  ┌──────────────┐          ┌──────────────────┐             │
│  │ linkguard    │◄────────►│ HQCommandServer  │             │
│  │ (Field iOS)  │ Command  │ (macOS / Swift)  │             │
│  └──────────────┘          └──────────────────┘             │
│  ┌──────────────┐          ┌──────────────────┐             │
│  │ linkguard    │◄────────►│ hq_server.py     │             │
│  │ (Field Andr) │          │ (Windows HQ)     │             │
│  └──────────────┘          └──────────────────┘             │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                 Python Backend Layer (3080 Desktop)           │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │tcp_server│  │gemma4_sv │  │http_serv │  │udp_server│    │
│  │  :9000   │  │  :8001   │  │  :8003   │  │  :9001   │    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────┘    │
│       │             │ UDP:8011    │                         │
│  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐                  │
│  │mqtt_brok │  │pws_fetch │  │whisper_s │  (2060 Laptop)    │
│  │  :1883   │  │(CWA API) │  │  :8002   │                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
│                                                              │
│  Dual-model peer (PC-B) ◄──UDP:8011──► gemma4_server :8001  │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                   LoRa Radio Layer (Long Range)               │
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐               │
│  │ HQ Node  │◄──►│  Rescue  │◄──►│  Victim  │               │
│  │ (hq.ino) │    │  (node)  │    │  (node)  │               │
│  └──────────┘    └──────────┘    └──────────┘               │
│                                                              │
│  BLE (short range): iOS ◄──► Heltec LoRa 32 V3              │
│                               (ESP32-S3 + SX1262)           │
└──────────────────────────────────────────────────────────────┘
```

---

### Key Features

- **AI Command Decisions** — Integrates casualty data, voice reports, and live weather; Gemma4 outputs structured commands: *Priority Treatment*, *Resource Allocation*, *Precautions*
- **Three-Tier AI** — Field (gemma4:e2b) → HQ Local (gemma4:e4b) → HQ Main (gemma4:26b with thinking mode); tiers auto-route by task complexity
- **Dual-Model Peer** — Two PCs discover each other via UDP broadcast on port 8011; the small model self-assesses confidence and escalates to the large model when needed
- **START Triage** — Automatic 3-step initial sort (Black / Red / Yellow / Green) combined with a 6-dimension weighted score to rank rescue priority
- **Voice Reporting** — PTT audio streams via LGAP protocol (TCP:8005) to HQ; Whisper Large-v3 transcribes in real time and automatically triggers AI decision refresh
- **Multi-Device Sync** — TCP broadcast ensures every connected device receives the same decision update
- **Dual HQ Support** — macOS `LinkGuardHQ` (Swift) or Windows `hq_server.py` (Python, TCP:8930 + LGAP:8005 + WebSocket dashboard:8080)
- **LoRa Node Monitoring** — Node RSSI, SNR, battery level, and GPS position broadcast every 15 seconds to the command centre
- **Live Weather** — Temperature, humidity, wind speed, and rainfall pulled every 5 minutes from the Central Weather Administration API (station C0A980)
- **Zero-Config Discovery** — Bonjour / mDNS (`_linkguardpy._tcp` / `_linkguard-hq._tcp`) lets field devices find the command server automatically with no manual IP entry
- **Offline Backup** — Dual USB backup: DB sync every 15 minutes, full snapshot every 60 minutes
- **Command Dashboard** — Night-vision dark-theme HTML dashboard with live node status and decision log (served from `hq/index.html` via WebSocket)

---

### Quick Start

#### Requirements

- **OS**: Windows 11 (`win11/` backend)
- **Python**: 3.14 (tested); 3.11+ should work
- **CUDA**: 12.x (Whisper GPU inference)
- **Ollama**: 0.6+, pull the model first:
  ```
  ollama pull gemma4:26b            # standalone / large-model peer
  ollama pull gemma4:e4b            # small-model peer (dual-model mode)
  ```
- **Mosquitto MQTT Broker** listening on `localhost:1883`
- **CWA API key**: set environment variable `CWA_API_KEY`

#### Install Dependencies

```powershell
cd win11
python -m venv ..\.venv
..\.venv\Scripts\activate
pip install -r requirements.txt
```

Key packages (see `win11/requirements.txt` for pinned versions):

```
fastapi uvicorn starlette pydantic python-multipart
httpx requests certifi
ollama
faster-whisper ctranslate2 onnxruntime av numpy
Pillow
paho-mqtt
zeroconf
```

#### Start Services

```powershell
cd win11
start_all.bat
```

The launcher prompts for the dual-model mode and then starts all 9 services in separate windows:

| # | Service | Port |
|---|---------|------|
| 1 | MQTT Client | 1883 |
| 2 | TCP Server | 9000 |
| 3 | Gemma4 AI Server | 8001 |
| 4 | Whisper Server | 8002 |
| 5 | Photo Server | 8004 |
| 6 | HTTP Server | 8003 |
| 7 | Stats Server | 8005 |
| 8 | Resource Server | 8006 |
| 9 | UDP Server | 9001 |

**Dual-model startup modes** (selected interactively):

| Mode | Description |
|------|-------------|
| `[1] Standalone` | Single PC, gemma4:26b only |
| `[2] Small model` | gemma4:e4b — rapid triage, auto-escalates to peer via UDP:8011 |
| `[3] Large model` | gemma4:26b — receives escalated requests from the small-model peer |

#### Start Windows HQ (optional)

```powershell
cd win11
start_hq.bat
```

This starts `hq_server.py`, which exposes TCP:8930 (field devices), LGAP:8005 (PTT audio), and WebSocket+HTTP:8080 (dashboard at `http://localhost:8080`).

#### Stop Services

```powershell
cd win11
stop_all.bat
# or
stop_hq.bat   # stop Windows HQ only
```

---

### Python Backend Modules

| Module | Description |
|--------|-------------|
| `tcp_server.py` | TCP aggregation hub (port 9000). Bonjour broadcast (`_linkguardpy._tcp`), message routing (ping / patient / location / voice_result / PTT), periodic weather and node-status push, AI decision trigger |
| `gemma4_server.py` | AI decision engine (port 8001). Three-tier Gemma4 via Ollama (e2b field / e4b hq_local / 26b hq_main); dual-model peer auto-discovery (UDP:8011), confidence-based escalation, `/decide`, `/translate`, `/model` endpoints |
| `hq_server.py` | Windows HQ command centre. TCP:8930 (field devices + Bonjour `_linkguard-hq._tcp`), LGAP audio server :8005, WebSocket+HTTP dashboard :8080, bridge to Python backend :9000 |
| `http_server.py` | Report service (port 8003). Field text/audio report upload with pending-retry, static dashboard hosting |
| `whisper_server.py` | Speech recognition (port 8002, 2060 laptop). Whisper Large-v3 on CUDA; forwards transcript to `tcp_server` on completion |
| `mqtt_broker.py` | MQTT client. Subscribes to `linkguard/nodes/#`, parses LoRa node heartbeats, maintains `node_status` dictionary |
| `start_triage.py` | START 3-step triage + 6-dimension weighted scoring engine |
| `triage.py` | Casualty assessment helper utilities |
| `linkguard_db.py` | Unified SQLite WAL access layer (`./data/linkguard.db`), 10-table schema |
| `pws_fetcher.py` | Central Weather Administration automatic weather station API wrapper (station C0A980) |
| `usb_backup.py` | USB auto-detection, DB sync (15 min), timed snapshots (60 min), audio backup |
| `photo_server.py` | Photo upload and retrieval (port 8004) |
| `stats_server.py` | Statistics queries (port 8005) |
| `resource_server.py` | Rescue resource management (port 8006) |
| `udp_server.py` | Low-latency UDP voice broadcast (port 9001) |
| `report_generator.py` | Briefing summary generator |
| `i18n.py` | Internationalisation helper (`t()`, `get_locale()`, `set_locale()`) |
| `utils.py` | Shared utilities: `get_local_ip`, `now_iso`, `api_ok`, `api_error`, `send_to_tcp_with_retry` |

---

### Database Schema

Database file: `win11/data/linkguard.db` (SQLite WAL mode)

| Table | Description |
|-------|-------------|
| `decisions` | AI decision log (voice text, casualty summary, weather summary, decision text, trigger type) |
| `patients` | Casualty records (vital signs, START classification, GPS, 6-dimension scores, status, notes) |
| `locations` | Device GPS location log (device_id, role, lat/lon, accuracy) |
| `reports` | Field text/audio reports (ID format: `RPT-YYYYMMDD-NNN`) |
| `weather_log` | Periodic weather snapshots (temperature, humidity, wind speed, rainfall) |
| `transcriptions` | Voice transcription history (sender, text, source, duration) |
| `node_status_log` | LoRa node heartbeat history (RSSI, SNR, battery, lat/lon, PDR) |
| `system_events` | System event log (event_type, device_id, severity) |
| `photos` | Photo upload records (sender, path, lat/lon, caption) |
| `resources` | Rescue resource inventory |

---

### START Triage System

#### 3-Step Initial Sort

```
Step 1 — Respiration
  No breathing                    → Black  (DECEASED)
  Breathing rate > 30/min         → Red    (IMMEDIATE)

Step 2 — Circulation
  Capillary refill > 2 s or no pulse → Red (IMMEDIATE)

Step 3 — Mental Status
  Cannot follow commands          → Yellow (DELAYED)

All normal                        → Green  (MINOR)
```

#### 6-Dimension Weighted Score

| Dimension | Weight | Description |
|-----------|--------|-------------|
| Vitals criticality | 1.5 | Respiratory distress, heavy bleeding, weak pulse, unconscious |
| Time pressure | 1.4 | Deterioration risk within 1 h / 3 h |
| Survival probability | 1.3 | High / medium / very low survival chance |
| Injury severity | 1.2 | Severe (internal bleeding/crush) / moderate (fracture) / minor |
| Environmental risk | 1.1 | Secondary injury hazard |
| Rescue cost | 1.0 | Resources required |

**Total Score = START bonus + Σ(raw score × dimension weight)**

Patients are ranked in descending Total Score order; ties broken in favour of RED (IMMEDIATE).

---

### Dual-Model AI Architecture

`gemma4_server.py` implements a three-tier model hierarchy controlled by `dual_config.json`:

| Tier | Model | Use Cases |
|------|-------|-----------|
| `field` | gemma4:e2b | Simple field chat, report formalisation |
| `hq_local` | gemma4:e4b | Complex field decisions, AI proposals on field side |
| `hq_main` | gemma4:26b (thinking mode) | HQ commander chat, main escalation, AI command proposals |

**Two-PC dual-model setup:**

1. Start PC-A with `start_all.bat` → choose `[2] Small model`
2. Start PC-B with `start_all.bat` → choose `[3] Large model`
3. Both PCs announce themselves on UDP:8011; peer discovery is automatic
4. The small model generates an initial decision and self-scores confidence; if below `confidence_threshold` (default 0.7), it forwards the full context to the large model for deep analysis

Escalation rules (configurable in `dual_config.json`):

- Auto-escalate when RED casualties ≥ 3
- Auto-escalate when resource utilisation > 80%
- Always escalate evacuation decisions

---

### LoRa Node Communication

- **Hardware**: Heltec LoRa 32 V3 (ESP32-S3 + SX1262)
- **Protocol**: MQTT v5, topic `linkguard/nodes/<node_id>`
- **Heartbeat fields**: `node_id`, `rssi`, `snr`, `battery`, `location` (lat/lon), `pdr`, `timestamp`
- **Broadcast interval**: `tcp_server` pushes latest node status to all devices every **15 seconds**
- **BLE short-range**: iOS can communicate directly with Heltec nodes via BLE

---

### Testing

```powershell
cd win11
python -m pytest tests/ -v
```

Required packages for tests: `pytest pytest-asyncio httpx fastapi python-multipart paho-mqtt zeroconf`

| File | Coverage |
|------|----------|
| `test_start_triage.py` | START classification logic, 6-dimension scoring |
| `test_triage.py` | Casualty assessment utilities |
| `test_mqtt_broker.py` | MQTT message parsing, node status updates |
| `test_pws_fetcher.py` | Weather API response parsing |
| `test_tcp_server.py` | TCP message routing |
| `test_http_server.py` | HTTP report endpoints |
| `test_gemma4_server.py` | Gemma4 AI decision engine endpoints |
| `test_gemma4_integration.py` | Gemma4 integration scenarios |
| `test_gemma4_server_chat_tools.py` | Gemma4 chat tool calls |
| `test_three_tier_routing.py` | Three-tier AI tier routing logic |
| `test_ai_autonomy_modes.py` | AI autonomy mode switching |
| `test_api_format.py` | API response format validation |
| `test_delivery.py` | Message delivery reliability |
| `test_qwen_integration.py` | Qwen/Gemma4 integration compatibility |
| `test_usb_backup.py` | USB backup detection and sync |

---

### License

This project is licensed under the terms of the [LICENSE](LICENSE) file.

---

> **Hsinchu Industrial High School × Hsinchu Digital Experimental High School | Science Fair 2026**

---


<a name="中文"></a>

## 中文

## 目錄

- [系統總覽](#系統總覽)
- [硬體配置](#硬體配置)
- [服務清單](#服務清單)
- [系統架構](#系統架構)
- [功能特色](#功能特色)
- [快速開始](#快速開始)
  - [環境需求](#環境需求)
  - [安裝相依套件](#安裝相依套件)
  - [啟動服務](#啟動服務)
  - [停止服務](#停止服務)
- [Python 後端模組說明](#python-後端模組說明)
- [資料庫結構](#資料庫結構)
- [START 檢傷分類系統](#start-檢傷分類系統)
- [雙模型 AI 架構](#雙模型-ai-架構)
- [LoRa 節點通訊](#lora-節點通訊)
- [測試](#測試)
- [授權](#授權)

---

## 系統總覽

LinkGuard 是一套整合 AI 決策、多裝置通訊、LoRa 長距離無線網路的災害救援指揮系統。透過前線行動裝置（iOS/Android）收集傷員資訊、語音報告與 GPS 位置，經由本地 Wi-Fi 回傳至指揮主機，由三層式 Gemma4 大語言模型即時生成救援決策，再推播給所有連線裝置。雙模型配置下，兩台 PC 可協作運作：小模型（gemma4:e4b）快速初步處理，複雜決策自動升級轉交大模型（gemma4:26b）深度分析。

```
前線裝置 (iOS / Android)
      │  Wi-Fi (TCP / HTTP / UDP / LGAP:8005)
      ▼
3080 指揮主機 ──► Gemma4 AI (Ollama)
      │           三層模型：e2b 前線 / e4b HQ本地 / 26b HQ主要
      │           語音辨識 (Whisper Large-v3)
      │           氣象資料 (中央氣象署 API)
      │           LoRa 節點狀態 (MQTT)
      ▼
指揮中心（macOS LinkGuardHQ 或 Windows hq_server.py）
      │  TCP :8930 + WebSocket 儀表板 :8080
      ▼
iPad / iPhone / Android 現場站
```

---

## 硬體配置

| 裝置 | 角色 | 主要任務 |
|------|------|----------|
| RTX 3080 主機 (PC-A) | 推理伺服器 | Gemma4 AI、START 評分、TCP、MQTT、PWS、備份 |
| RTX 2060 筆電 | 語音辨識 | Whisper Large-v3、FastAPI |
| 第二台 PC (PC-B) | 對端 AI 伺服器 | gemma4:26b 深度分析（雙模型模式） |
| M2 MacBook Air | 指揮中心（macOS） | LinkGuardHQ macOS、31.5 吋外接顯示 |
| Windows HQ 主機 | 指揮中心（Windows） | hq_server.py（TCP :8930 + LGAP :8005 + WS :8080） |
| iPad Air M2 | 現場醫療站 | LinkGuard iPadOS 傷員列表 |
| iOS 手機 | 現場終端 | LinkGuard iOS 回報 + 電台 |
| Android 手機 | 現場終端 | LinkGuard Android 回報 + 電台 |
| RT-AX1800S | 區網骨幹 | 指揮站 Wi-Fi、連接所有設備 |
| Heltec LoRa 32 V3 | 現場通訊節點 | ESP32-S3 + SX1262，長距離廣播 |

---

## 服務清單

| 服務 | 主機 | 埠口 | 協議 | 說明 |
|------|------|------|------|------|
| `tcp_server` | 3080 主機 | 9000 | TCP + Bonjour (`_linkguardpy._tcp`) | 聚合中樞：接收前線訊息、呼叫 AI、推播決策 |
| `gemma4_server` | 3080 主機 | 8001 | HTTP (FastAPI) | Gemma4 AI 決策引擎（三層：e2b / e4b / 26b）；雙模型對端透過 UDP 8011 自動探索 |
| `whisper_server` | 2060 筆電 | 8002 | HTTP (FastAPI) | Whisper Large-v3 語音轉文字 |
| `http_server` | 3080 主機 | 8003 | HTTP (FastAPI) | 現場回報上傳、靜態儀表板 |
| `photo_server` | 3080 主機 | 8004 | HTTP (FastAPI) | 照片上傳與存取 |
| `stats_server` | 3080 主機 | 8005 | HTTP (FastAPI) | 統計資料查詢 |
| `resource_server` | 3080 主機 | 8006 | HTTP (FastAPI) | 救援資源管理 |
| `udp_server` | 3080 主機 | 9001 | UDP | 低延遲語音廣播 |
| `mqtt_broker` | 3080 主機 | 1883 | MQTT v5 | LoRa 節點狀態聚合 |
| `HQCommandServer` | macOS HQ | 8930 | TCP + Bonjour (`_linkguard-hq._tcp`) | macOS 指揮中心 |
| `hq_server` | Windows HQ | 8930 / 8005 / 8080 | TCP + LGAP + WebSocket | Windows 指揮中心替代方案 |

---

## 系統架構

```
┌──────────────────────────────────────────────────────────────┐
│                   WiFi 指揮層 (TCP 8930)                      │
│                                                              │
│  ┌──────────────┐          ┌──────────────────┐             │
│  │ linkguard    │◄────────►│ HQCommandServer  │             │
│  │ (Field iOS)  │ Command  │ (macOS / Swift)  │             │
│  └──────────────┘          └──────────────────┘             │
│  ┌──────────────┐          ┌──────────────────┐             │
│  │ linkguard    │◄────────►│ hq_server.py     │             │
│  │ (Field Andr) │          │ (Windows HQ)     │             │
│  └──────────────┘          └──────────────────┘             │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                 Python 後端層 (3080 主機)                      │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │tcp_server│  │gemma4_sv │  │http_serv │  │udp_server│    │
│  │  :9000   │  │  :8001   │  │  :8003   │  │  :9001   │    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────┘    │
│       │             │ UDP:8011    │                         │
│  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐                  │
│  │mqtt_brok │  │pws_fetch │  │whisper_s │  (2060 筆電)      │
│  │  :1883   │  │(CWA API) │  │  :8002   │                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
│                                                              │
│  雙模型對端 (PC-B) ◄──UDP:8011──► gemma4_server :8001       │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                   LoRa 無線層 (長距離)                         │
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐               │
│  │ HQ Node  │◄──►│  Rescue  │◄──►│  Victim  │               │
│  │ (hq.ino) │    │  (node)  │    │  (node)  │               │
│  └──────────┘    └──────────┘    └──────────┘               │
│                                                              │
│  BLE 近端：iOS ◄──► Heltec LoRa 32 V3 (ESP32-S3 + SX1262)  │
└──────────────────────────────────────────────────────────────┘
```

---

## 功能特色

- **AI 指揮決策**：整合傷員資料、語音報告、即時氣象，由 Gemma4 生成【優先處置】【資源調配】【注意事項】指令
- **三層式 AI**：前線（gemma4:e2b）→ HQ 本地（gemma4:e4b）→ HQ 主要（gemma4:26b 思考模式）；依任務複雜度自動路由
- **雙模型對端**：兩台 PC 透過 UDP:8011 廣播自動探索；小模型自評信心值，不足時自動升級轉交大模型
- **START 檢傷分類**：自動三步驟初篩（黑/紅/黃/綠），搭配六維度加權評分排定救援優先順序
- **語音回報**：PTT 語音透過 LGAP 協議（TCP:8005）串流至 HQ，Whisper Large-v3 即時轉文字，自動觸發 AI 決策更新
- **多裝置同步**：TCP 廣播確保所有連線設備接收相同決策資訊
- **雙平台 HQ 支援**：macOS `LinkGuardHQ`（Swift）或 Windows `hq_server.py`（Python，TCP:8930 + LGAP:8005 + WebSocket 儀表板:8080）
- **LoRa 節點監控**：每 15 秒推播節點 RSSI、SNR、電量、GPS 位置至指揮中心
- **即時氣象**：每 5 分鐘從中央氣象署 API（測站 C0A980）拉取溫度、濕度、風速、降雨
- **自動服務發現**：Bonjour / mDNS（`_linkguardpy._tcp` / `_linkguard-hq._tcp`）讓前線裝置無需輸入 IP 即可自動找到指揮主機
- **離線備份**：USB 雙備份，每 15 分鐘同步 DB，每 60 分鐘完整備份
- **指揮儀表板**：暗黑夜視風格 HTML 儀表板（`hq/index.html`），透過 WebSocket 即時顯示節點狀態與決策記錄

---

## 快速開始

### 環境需求

- **OS**：Windows 11（`win11/` 後端）
- **Python**：3.14（已測試）；3.11+ 應可正常運作
- **CUDA**：12.x（Whisper GPU 推論）
- **Ollama**：`0.6+`，需預先拉取模型
  ```
  ollama pull gemma4:26b     # 單機模式 / 大模型對端
  ollama pull gemma4:e4b     # 小模型對端（雙模型模式）
  ```
- **Mosquitto MQTT Broker**：監聽 `localhost:1883`
- **中央氣象署 API 金鑰**：設環境變數 `CWA_API_KEY`

### 安裝相依套件

```powershell
cd win11
python -m venv ..\.venv
..\.venv\Scripts\activate
pip install -r requirements.txt
```

### 啟動服務

```powershell
cd win11
start_all.bat
```

啟動腳本會詢問雙模型模式，再依序在獨立視窗啟動全部 9 個服務：

| 順序 | 服務 | 埠口 |
|------|------|------|
| 1 | MQTT Client | 1883 |
| 2 | TCP Server | 9000 |
| 3 | Gemma4 AI Server | 8001 |
| 4 | Whisper Server | 8002 |
| 5 | Photo Server | 8004 |
| 6 | HTTP Server | 8003 |
| 7 | Stats Server | 8005 |
| 8 | Resource Server | 8006 |
| 9 | UDP Server | 9001 |

**雙模型啟動模式**（互動選擇）：

| 模式 | 說明 |
|------|------|
| `[1] 單機模式` | 單台 PC，僅使用 gemma4:26b |
| `[2] 小模型` | gemma4:e4b — 快速初篩，自動透過 UDP:8011 升級至對端 |
| `[3] 大模型` | gemma4:26b — 接收來自小模型對端的升級請求 |

**啟動 Windows HQ（選用）**：

```powershell
cd win11
start_hq.bat
```

這會啟動 `hq_server.py`，開放 TCP:8930（前線裝置）、LGAP:8005（PTT 音訊）、WebSocket+HTTP:8080（儀表板 `http://localhost:8080`）。

### 停止服務

```powershell
cd win11
stop_all.bat
# 或
stop_hq.bat   # 僅停止 Windows HQ
```

---

## Python 後端模組說明

| 模組 | 說明 |
|------|------|
| `tcp_server.py` | TCP 聚合中樞（Port 9000）。Bonjour 服務廣播（`_linkguardpy._tcp`）、訊息路由（ping / patient / location / voice_result / PTT）、定時推播氣象與節點狀態、AI 決策觸發 |
| `gemma4_server.py` | AI 決策引擎（Port 8001）。三層式 Gemma4 via Ollama（e2b 前線 / e4b HQ本地 / 26b HQ主要）；雙模型對端 UDP:8011 自動探索、信心值升級機制、`/decide`、`/translate`、`/model` 端點 |
| `hq_server.py` | Windows HQ 指揮中心。TCP:8930（前線裝置 + Bonjour `_linkguard-hq._tcp`）、LGAP 音訊伺服器:8005、WebSocket+HTTP 儀表板:8080、橋接後端:9000 |
| `http_server.py` | 回報服務（Port 8003）。現場文字/音訊回報上傳，Pending 重試機制，靜態儀表板服務 |
| `whisper_server.py` | 語音辨識（Port 8002，2060 筆電）。Whisper Large-v3 CUDA，辨識完成後自動轉發至 tcp_server |
| `mqtt_broker.py` | MQTT 客戶端。訂閱 `linkguard/nodes/#`，解析 LoRa 節點心跳並更新 `node_status` 字典 |
| `start_triage.py` | START 三步驟檢傷 + 六維度加權評分引擎 |
| `triage.py` | 傷員評估輔助工具 |
| `linkguard_db.py` | SQLite WAL 資料庫統一存取層（`./data/linkguard.db`），10 張資料表 |
| `pws_fetcher.py` | 中央氣象署自動氣象站 API 封裝（測站 C0A980） |
| `usb_backup.py` | USB 自動偵測、DB 同步（15 分鐘）、定時快照（60 分鐘）、音訊備份 |
| `photo_server.py` | 照片上傳與存取（Port 8004） |
| `stats_server.py` | 統計查詢（Port 8005） |
| `resource_server.py` | 救援資源管理（Port 8006） |
| `udp_server.py` | UDP 低延遲語音廣播（Port 9001） |
| `report_generator.py` | 會報摘要產生器 |
| `i18n.py` | 多語系輔助工具（`t()`、`get_locale()`、`set_locale()`） |
| `utils.py` | 共用工具：`get_local_ip`、`now_iso`、`api_ok`、`api_error`、`send_to_tcp_with_retry` |

---

## 資料庫結構

資料庫位於 `win11/data/linkguard.db`，使用 SQLite WAL 模式，共 10 張資料表：

| 資料表 | 說明 |
|--------|------|
| `decisions` | AI 決策記錄（語音文字、傷員摘要、氣象摘要、決策內容、觸發類型） |
| `patients` | 傷員資訊（生命徵象、START 分類、GPS 位置、六維度評分、狀態、備註） |
| `locations` | 裝置 GPS 位置記錄（device_id、角色、經緯度、精確度） |
| `reports` | 現場文字/音訊回報（RPT-YYYYMMDD-NNN 編號） |
| `weather_log` | 定時氣象快照（溫度、濕度、風速、降雨） |
| `transcriptions` | 語音轉文字紀錄（發送者、文字、來源、時長） |
| `node_status_log` | LoRa 節點心跳歷史（RSSI、SNR、電量、經緯度、PDR） |
| `system_events` | 系統事件日誌（事件類型、device_id、嚴重程度） |
| `photos` | 照片上傳記錄（發送者、路徑、經緯度、說明） |
| `resources` | 救援資源庫存 |

---

## START 檢傷分類系統

### 三步驟初篩

```
步驟 1 — 呼吸評估
  無呼吸 → 黑色 (DECEASED)
  呼吸 > 30 次/分 → 紅色 (IMMEDIATE)

步驟 2 — 循環評估
  微血管回填 > 2 秒 或 無脈搏 → 紅色 (IMMEDIATE)

步驟 3 — 意識評估
  無法遵從指令 → 黃色 (DELAYED)

全部正常 → 綠色 (MINOR)
```

### 六維度加權評分

| 維度 | 權重 | 說明 |
|------|------|------|
| 生命危急程度 (vitals) | 1.5 | 呼吸困難、大量出血、心跳微弱、意識不清 |
| 時間壓力 (time_pressure) | 1.4 | 1/3 小時內惡化風險 |
| 存活可能性 (survival) | 1.3 | 高/中/極低存活率 |
| 傷勢嚴重度 (injury) | 1.2 | 重傷/中等傷/輕傷 |
| 環境風險 (environment) | 1.1 | 二次傷害風險 |
| 救援成本 (rescue_cost) | 1.0 | 所需資源量 |

**Total Score = START 加成 + Σ(原始分數 × 維度權重)**

救援優先序依 Total Score 降序排列；同分時 START 紅標優先。

---

## 雙模型 AI 架構

`gemma4_server.py` 實作三層模型階層，由 `dual_config.json` 控制：

| 層級 | 模型 | 適用場景 |
|------|------|----------|
| `field` | gemma4:e2b | 前線簡易對話、回報正規化 |
| `hq_local` | gemma4:e4b | 前線複雜決策、前線側 AI 提案 |
| `hq_main` | gemma4:26b（思考模式） | HQ 指揮官對話、主升級處理、AI 指揮提案 |

**兩台 PC 雙模型設定：**

1. PC-A 執行 `start_all.bat` → 選擇 `[2] 小模型`
2. PC-B 執行 `start_all.bat` → 選擇 `[3] 大模型`
3. 兩台 PC 透過 UDP:8011 廣播自動探索對端
4. 小模型產生初步決策並自評信心值；若低於 `confidence_threshold`（預設 0.7），自動將完整上下文轉發大模型進行深度分析

升級規則（可在 `dual_config.json` 調整）：

- 紅色傷員 ≥ 3 名時自動升級
- 資源使用率 > 80% 時自動升級
- 撤離決策永遠升級

---

## LoRa 節點通訊

- **硬體**：Heltec LoRa 32 V3（ESP32-S3 + SX1262）
- **協議**：MQTT v5，主題 `linkguard/nodes/<node_id>`
- **心跳欄位**：`node_id`, `rssi`, `snr`, `battery`, `location` (lat/lon), `pdr`, `timestamp`
- **推播週期**：`tcp_server` 每 **15 秒**廣播最新節點狀態至所有連線裝置
- **BLE 近端**：iOS 可透過 BLE 與 Heltec 節點直接通訊

---

## 測試

```powershell
cd win11
python -m pytest tests/ -v
```

測試所需套件：`pytest pytest-asyncio httpx fastapi python-multipart paho-mqtt zeroconf`

| 檔案 | 涵蓋範圍 |
|------|----------|
| `test_start_triage.py` | START 分類邏輯、六維度評分 |
| `test_triage.py` | 傷員評估工具 |
| `test_mqtt_broker.py` | MQTT 訊息解析、節點狀態更新 |
| `test_pws_fetcher.py` | 氣象 API 資料解析 |
| `test_tcp_server.py` | TCP 訊息路由 |
| `test_http_server.py` | HTTP 回報端點 |
| `test_gemma4_server.py` | Gemma4 AI 決策引擎端點 |
| `test_gemma4_integration.py` | Gemma4 整合情境 |
| `test_gemma4_server_chat_tools.py` | Gemma4 工具呼叫 |
| `test_three_tier_routing.py` | 三層 AI 路由邏輯 |
| `test_ai_autonomy_modes.py` | AI 自主模式切換 |
| `test_api_format.py` | API 回應格式驗證 |
| `test_delivery.py` | 訊息投遞可靠性 |
| `test_qwen_integration.py` | Qwen/Gemma4 相容性整合 |
| `test_usb_backup.py` | USB 備份偵測與同步 |

---

## 授權

本專案採用 [LICENSE](LICENSE) 授權。

---

> **新竹高工 × 新竹數位實中 | 科展展示 2026**
>
> **Hsinchu Industrial High School × Hsinchu Digital Experimental High School | Science Fair 2026**

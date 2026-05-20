# LinkGuard 雙模型 AI 決策架構設計

## 目錄
1. [系統概覽](#1-系統概覽)
2. [硬體拓撲](#2-硬體拓撲)
3. [模型角色配置](#3-模型角色配置ui-選擇)
4. [決策升級邏輯](#4-決策升級邏輯escalation)
5. [資料傳輸協議](#5-資料傳輸協議)
6. [三種實作方案](#6-三種實作方案)
7. [方案比較](#7-方案比較)
8. [建議選擇](#8-建議選擇)

---

## 1. 系統概覽

```
┌──────────────┐   Ethernet   ┌──────────────┐
│   PC-A       │◄────────────►│   PC-B       │
│ (小模型 or 大)│  REST API    │ (大模型 or 小)│
│ gemma4:e4b   │              │ gemma4:26b   │
│   :8001      │              │   :8001      │
└──────┬───────┘              └──────┬───────┘
       │                             │
       │    WiFi / TCP :8930         │
       ▼                             │
┌──────────────┐                     │
│   HQ App     │ ◄───────────────────┘
│ (Android/iOS)│   (透過 Primary PC 中繼)
│   Dashboard  │
└──────────────┘
```

**核心理念**：小模型快速產生初步決策的同時，自評決策難度。若難度超過閾值，自動將完整上下文轉發給大模型做深度分析。HQ 端完全透明 — 只看到最終決策結果與使用了哪個模型。

---

## 2. 硬體拓撲

| 項目 | PC-A | PC-B |
|------|------|------|
| 網路 | 固定 IP (e.g. `192.168.100.10`) | 固定 IP (e.g. `192.168.100.20`) |
| Ollama | 本地運行 `:11434` | 本地運行 `:11434` |
| gemma4_server | `:8001` | `:8001` |
| 模型角色 | 啟動時由使用者選擇 | 啟動時由使用者選擇 |

兩台 PC 直接用乙太網路線連接，設定靜態 IP 同網段。每台各跑自己的 `gemma4_server.py` + Ollama。

---

## 3. 模型角色配置（UI 選擇）

### 3.1 啟動時配置

在 `gemma4_server.py` 啟動時或 HQ Dashboard 上，讓使用者選擇：

```
╔══════════════════════════════════════╗
║   LinkGuard 雙模型配置               ║
╠══════════════════════════════════════╣
║                                      ║
║  本機 IP: 192.168.100.10             ║
║  對端 IP: 192.168.100.20             ║
║                                      ║
║  本機模型角色:                        ║
║  ● 小模型 (gemma4:e4b) — 快速初判    ║
║  ○ 大模型 (gemma4:26b) — 深度分析    ║
║                                      ║
║  [確認啟動]                           ║
╚══════════════════════════════════════╝
```

### 3.2 配置資料結構

```python
# dual_config.json
{
    "local_role": "small",           # "small" | "large"
    "local_model": "gemma4:e4b",     # 本機 Ollama 模型名
    "local_host": "192.168.100.10",
    "local_port": 8001,
    "peer_role": "large",            # 對端角色
    "peer_host": "192.168.100.20",
    "peer_port": 8001,
    "escalation_enabled": true,
    "confidence_threshold": 0.6,     # 低於此值就升級
    "peer_timeout_sec": 30
}
```

### 3.3 環境變數備用方案

```bash
# PC-A (.env)
LINKGUARD_ROLE=small
LINKGUARD_LOCAL_MODEL=gemma4:e4b
LINKGUARD_PEER_HOST=192.168.100.20
LINKGUARD_PEER_PORT=8001

# PC-B (.env)
LINKGUARD_ROLE=large
LINKGUARD_LOCAL_MODEL=gemma4:26b
LINKGUARD_PEER_HOST=192.168.100.10
LINKGUARD_PEER_PORT=8001
```

---

## 4. 決策升級邏輯（Escalation）

### 4.1 完整流程圖

```
HQ 傳送決策請求
        │
        ▼
┌───────────────────┐
│  小模型 (PC-A)     │
│  gemma4:e4b        │
│                    │
│  1. 接收請求       │
│  2. 產生初步決策    │
│  3. 【同時】自評    │─── confidence ≥ 0.6 ──► 直接回傳 HQ
│     決策信心度      │                         (model: "gemma4:e4b")
│                    │
│  confidence < 0.6  │
│  OR 觸發升級條件    │
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  轉發至大模型       │
│  HTTP POST         │
│  peer:8001/generate│
│                    │
│  附帶:             │
│  - 原始請求        │
│  - 小模型初步決策   │
│  - 信心度評估       │
│  - 升級原因        │
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│  大模型 (PC-B)     │
│  gemma4:26b        │
│                    │
│  1. 接收請求+小模型 │
│     初判結果        │
│  2. 深度分析        │
│  3. 產生最終決策    │
│  4. 回傳給 PC-A    │
└────────┬──────────┘
         │
         ▼
   PC-A 收到最終決策
   回傳 HQ
   (model: "gemma4:26b",
    escalated: true,
    escalation_reason: "...")
```

### 4.2 信心度自評 Prompt

小模型在產生決策的同時，會被要求輸出信心度分數：

```
你是 LinkGuard 災害救援指揮 AI（初判模式）。

請先產生指揮決策，然後在最後一行自評此決策的信心度。

信心度評估標準：
- 0.9-1.0: 情況明確，標準處置，有信心獨立決策
- 0.7-0.8: 大致清楚但有少量不確定因素
- 0.5-0.6: 情況複雜，多重傷患交互影響，需要更深入分析
- 0.3-0.4: 資源極度不足或罕見情境，決策風險高
- 0.0-0.2: 無法判斷，資訊嚴重不足

以下情境自動設為低信心度 (≤0.4)：
- 紅色傷患 ≥ 3 人
- 資源利用率 > 80%
- 存在矛盾的情報（如多點同時求救）
- 涉及撤離決策（影響範圍大）
- 天氣劇變（溫度驟降/風速驟增）

最後一行格式（必須嚴格遵守）：
【信心度】0.XX | 原因簡述
```

### 4.3 信心度解析

```python
def parse_confidence(decision_text: str) -> tuple[float, str]:
    """從決策文字中提取信心度分數與原因。"""
    match = re.search(
        r'【信心度】\s*([\d.]+)\s*\|\s*(.+)',
        decision_text
    )
    if match:
        score = min(max(float(match.group(1)), 0.0), 1.0)
        reason = match.group(2).strip()
        return score, reason
    # 若模型沒輸出信心度，保守假設低信心
    return 0.5, "模型未輸出信心度評估"
```

### 4.4 升級觸發條件（可配置）

| 條件 | 預設閾值 | 說明 |
|------|---------|------|
| `confidence < threshold` | 0.6 | 信心度不足 |
| `red_patients >= N` | 3 | 紅色傷患過多 |
| `involves_evacuation` | — | 決策含撤離指令 |
| `resource_utilization > X%` | 80% | 資源接近耗盡 |
| `conflicting_reports` | — | 多源矛盾情報 |
| `manual_escalate` | — | HQ 手動要求升級 |

---

## 5. 資料傳輸協議

### 5.1 小模型 → 大模型 升級請求

```
POST http://{peer_host}:{peer_port}/escalate
Content-Type: application/json

{
    "request_id": "ESC-20260419-abc123",
    "timestamp": "2026-04-19T14:30:00+08:00",
    
    "original_request": {
        "voice_text": "三樓西側發現受困者...",
        "patients": [...],
        "weather": {...},
        "resources": "醫療包 1/5 | 擔架 0/4"
    },
    
    "small_model_result": {
        "decision": "【優先處置】...【資源調配】...",
        "confidence": 0.35,
        "confidence_reason": "資源極度不足，多名紅色傷患",
        "model": "gemma4:e4b",
        "processing_time_ms": 1200
    },
    
    "escalation_trigger": "confidence_below_threshold",
    "system_status": {
        "patients": {"total": 8, "red": 4, "yellow": 2, "green": 2, "black": 0},
        "resources": {...},
        "nodes": [...]
    }
}
```

### 5.2 大模型回應

```json
{
    "status": "ok",
    "request_id": "ESC-20260419-abc123",
    "decision": "【優先處置】鑒於4名紅色傷患且醫療包僅剩1組...",
    "model": "gemma4:26b",
    "escalated": true,
    "small_model_reference": "已參考初判結果並深化分析",
    "processing_time_ms": 8500,
    "reasoning": {
        "reason_summary": ["...", "..."],
        "risk_notes": ["..."],
        "next_actions": ["..."]
    }
}
```

### 5.3 回傳 HQ 的統一格式

無論是小模型直接回答或升級後大模型回答，回給 HQ 的格式一致：

```json
{
    "status": "ok",
    "decision": "...",
    "patients": [...],
    "model": "gemma4:e4b",
    "escalated": false,
    "escalation_info": null,
    
    // 或升級後:
    "model": "gemma4:26b",
    "escalated": true,
    "escalation_info": {
        "original_model": "gemma4:e4b",
        "confidence": 0.35,
        "reason": "資源極度不足，多名紅色傷患",
        "small_model_time_ms": 1200,
        "large_model_time_ms": 8500,
        "total_time_ms": 9700
    }
}
```

### 5.4 健康檢查 & 心跳

```
GET http://{peer_host}:{peer_port}/health
→ 200 OK = 對端在線
→ timeout / error = 對端離線

GET http://{peer_host}:{peer_port}/peer/ping
→ {"status": "ok", "role": "large", "model": "gemma4:26b", "load": 0.3}
```

小模型 PC 每 10 秒 ping 大模型 PC。若大模型不可達，小模型自動降級為獨立運作模式（不升級，所有決策自己處理）。

---

## 6. 三種實作方案

---

### 方案 A: Proxy 模式（推薦）

**概念**：小模型 PC 作為唯一入口（Proxy），HQ 只連此 PC。它決定自己處理或轉發給大模型 PC。

```
HQ ──► PC-A (小模型, Proxy :8001)
                │
                ├── 簡單決策: 自己處理
                │
                └── 複雜決策: POST → PC-B (大模型 :8001/escalate)
                                          │
                                          └── 回傳結果 → PC-A → HQ
```

**改動範圍**：
- `gemma4_server.py`：新增 `/escalate` 端點、修改 `/generate` 加入信心度判斷和轉發邏輯
- `dual_config.json`：新增配置檔
- `start_all.bat`：加入角色選擇互動

**優點**：
- HQ 零改動，完全向後相容
- 單一入口，網路架構簡單
- 升級邏輯集中在一處
- 大模型 PC 離線時自動降級，不影響服務

**缺點**：
- 小模型 PC 是單點故障
- 升級時延遲 = 小模型時間 + 網路 + 大模型時間

**程式碼結構**：

```python
# gemma4_server.py 修改 (PC-A, role=small)

@app.post("/generate")
async def generate(req: GenerateRequest):
    ranked = rank_patients(req.patients)
    patient_summary = format_for_llm(ranked)
    weather_summary = format_weather_for_llm(req.weather) if req.weather else "無"
    
    # === Phase 1: 小模型快速初判 ===
    small_decision, confidence, conf_reason = await _small_model_decide(
        req, patient_summary, weather_summary
    )
    
    # === Phase 2: 判斷是否需要升級 ===
    should_escalate = _should_escalate(confidence, ranked, req.resources)
    
    if not should_escalate or not _peer_available():
        # 直接回傳小模型結果
        save_decision(req.voice_text, patient_summary, weather_summary, small_decision)
        return api_ok({
            "decision": _strip_confidence_line(small_decision),
            "patients": ranked,
            "model": DUAL_CONFIG["local_model"],
            "escalated": False,
            "confidence": confidence,
        })
    
    # === Phase 3: 升級至大模型 ===
    escalation_result = await _escalate_to_peer(req, small_decision, confidence, conf_reason)
    
    final_decision = escalation_result.get("decision", small_decision)
    save_decision(req.voice_text, patient_summary, weather_summary, final_decision)
    
    return api_ok({
        "decision": final_decision,
        "patients": ranked,
        "model": DUAL_CONFIG["peer_model"],
        "escalated": True,
        "escalation_info": {
            "original_model": DUAL_CONFIG["local_model"],
            "confidence": confidence,
            "reason": conf_reason,
        },
    })

# gemma4_server.py (PC-B, role=large) 新增端點

@app.post("/escalate")
def handle_escalation(req: dict):
    """大模型接收升級請求，深度分析後回傳最終決策。"""
    original = req["original_request"]
    small_result = req["small_model_result"]
    
    system_prompt = (
        "你是 LinkGuard 災害救援深度分析 AI（GEMMA4 26B 深度模式）。\n"
        "小型快速模型已做初步判斷，但信心不足，需要你深度分析。\n\n"
        f"小模型初判結果：\n{small_result['decision']}\n"
        f"小模型信心度：{small_result['confidence']}（{small_result['confidence_reason']}）\n\n"
        "請基於更完整的分析，產生最終指揮決策。\n"
        "可以修正、補充或完全取代小模型的決策。\n"
        f"{START_RULES}\n"
    )
    
    # ... 調用本地 26B 模型生成最終決策 ...
    
    return api_ok({"decision": final_decision, "model": "gemma4:26b"})
```

---

### 方案 B: Router 模式

**概念**：新增一個獨立的 Router 服務（可跑在任一 PC），根據請求特徵和歷史統計智慧路由。

```
HQ ──► Router Service (:8000)
              │
              ├── 評估請求複雜度
              │
              ├── 簡單 ──► PC-A (小模型 :8001)
              │                    │
              │                    └── 結果 → Router → HQ
              │
              └── 複雜 ──► PC-B (大模型 :8001)
                                   │
                                   └── 結果 → Router → HQ
```

**改動範圍**：
- 新增 `router_server.py`（新檔案）
- `gemma4_server.py`：小幅修改，加入信心度自評
- HQ 配置：連接 Router 而非直接連 gemma4_server

**Router 預判邏輯**（在呼叫任何模型前）：

```python
# router_server.py

def assess_complexity(request: dict) -> str:
    """預判請求複雜度，決定路由。"""
    score = 0
    patients = request.get("patients", [])
    
    red_count = sum(1 for p in patients if p.get("priority") == "紅色"
                    or (p.get("breathing_rate", 20) > 30))
    score += red_count * 15
    
    if len(patients) >= 5:
        score += 20
    
    resources = request.get("resources", "")
    if "0/" in resources:  # 某資源已歸零
        score += 25
    
    voice = request.get("voice_text", "")
    urgent_keywords = ["撤離", "倒塌", "爆炸", "火勢", "失聯", "多重", "大量"]
    score += sum(10 for kw in urgent_keywords if kw in voice)
    
    if score >= 40:
        return "large"
    return "small"

@app.post("/generate")
async def route_generate(req: dict):
    target = assess_complexity(req)
    
    if target == "small":
        # 先送小模型
        result = await call_model(SMALL_PC, req)
        confidence = parse_confidence(result["decision"])
        
        if confidence < THRESHOLD:
            # 小模型不確定，升級到大模型
            result = await call_model(LARGE_PC, req, 
                                       prior_decision=result["decision"])
            result["escalated"] = True
        
        return result
    else:
        # 直接送大模型（跳過小模型，節省時間）
        result = await call_model(LARGE_PC, req)
        result["routed_direct"] = True
        return result
```

**優點**：
- 複雜請求可以跳過小模型，減少延遲
- 路由邏輯獨立，易於調整和測試
- 可收集統計資料優化路由策略

**缺點**：
- 多一個服務要維護
- HQ 需改連新端口 (`:8000`)
- Router 本身成為單點故障

---

### 方案 C: 並行模式 (Parallel Race)

**概念**：兩個模型同時處理，誰先完成誰的結果先展示，另一個的結果作為補充。

```
HQ ──► PC-A (小模型 :8001)
  │
  └──► PC-B (大模型 :8001)   ← 同步轉發
  
  小模型先完成 (通常 1-3 秒)
  → 立即回傳 HQ（標記為 "preliminary"）
  
  大模型完成 (通常 5-15 秒)
  → 更新 HQ（標記為 "final"，標示差異）
```

**改動範圍**：
- `gemma4_server.py`：加入並行轉發邏輯
- HQ App (Android/iOS)：需支援「初步→最終」兩階段更新 UI
- `tcp_server.py`：支援 `preliminary_decision` + `final_decision` 兩種訊息

**關鍵程式碼**：

```python
# gemma4_server.py (PC-A 作為入口)

@app.post("/generate")
async def generate_parallel(req: GenerateRequest):
    ranked = rank_patients(req.patients)
    
    # 同時發送給兩個模型
    small_task = asyncio.create_task(_local_generate(req, ranked))
    large_task = asyncio.create_task(_peer_generate(req, ranked))
    
    # 小模型先完成，立即通知 HQ
    small_result = await small_task
    await _notify_hq_preliminary(small_result)
    
    # 等大模型完成
    try:
        large_result = await asyncio.wait_for(large_task, timeout=30)
        
        # 比較兩個結果
        diff = _compare_decisions(small_result, large_result)
        
        if diff["significant"]:
            # 大模型有重大不同，推送更新
            await _notify_hq_final(large_result, diff)
            return api_ok({
                "decision": large_result["decision"],
                "preliminary": small_result["decision"],
                "diff": diff,
                "model": "gemma4:26b (revised)",
            })
        else:
            # 兩者一致，確認初步結果
            return api_ok({
                "decision": small_result["decision"],
                "confirmed_by": "gemma4:26b",
                "model": "gemma4:e4b (confirmed)",
            })
    except asyncio.TimeoutError:
        # 大模型超時，沿用小模型結果
        return api_ok({
            "decision": small_result["decision"],
            "model": "gemma4:e4b (standalone)",
        })
```

**HQ 端兩階段 UI**：

```
┌─────────────────────────────────────┐
│ 📋 AI 決策                    14:30  │
├─────────────────────────────────────┤
│ ⚡ 快速初判 (gemma4:e4b, 1.2s)      │
│                                      │
│ 【優先處置】派遣 EMT-1 前往 A 區... │
│ 【資源調配】動員醫療包 2 組...       │
│                                      │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│ 🔄 等待深度分析中... (gemma4:26b)    │
│ ████████████░░░░░░░░░ 60%            │
└─────────────────────────────────────┘

         ↓ 8 秒後 ↓

┌─────────────────────────────────────┐
│ 📋 AI 決策 (已更新)           14:30  │
├─────────────────────────────────────┤
│ 🧠 深度分析 (gemma4:26b, 8.5s)      │
│                                      │
│ 【優先處置】⚠️ 修正：應同時派遣     │
│   EMT-1 和 EMT-2，因 A 區有 3 名... │
│ 【資源調配】🔄 追加：需從 B 區調...  │
│ 【注意事項】新增：建築結構不穩...    │
│                                      │
│ 📊 與初判差異：優先序調整、資源追加  │
│                                      │
│ ✅ 初判參考 (展開)                    │
│ 信心度：0.45 — 已自動升級            │
└─────────────────────────────────────┘
```

**優點**：
- 使用者體驗最佳 — 最快看到初步結果，隨後獲得深度補充
- 大模型離線時完全不影響（graceful degradation）
- 兩個模型的結果可互相校驗

**缺點**：
- 永遠消耗兩台 PC 的運算資源（無論是否需要）
- HQ App 需要較大改動支援兩階段 UI
- 比較兩個決策的邏輯較複雜

---

## 7. 方案比較

| 維度 | A: Proxy | B: Router | C: 並行 |
|------|----------|-----------|---------|
| **HQ 改動** | ✅ 零改動 | ⚠️ 改連接端口 | ❌ 需改 UI + TCP |
| **後端改動** | ⚠️ 中等 (gemma4_server) | ⚠️ 中等 (新增 router) | ❌ 大量 (兩端 + TCP) |
| **延遲 (簡單)** | **~2s** (小模型直接) | **~2s** | ~2s (初步) + ~10s (最終) |
| **延遲 (複雜)** | ~12s (小模型+大模型) | **~10s** (直送大模型) | ~2s (初步) + ~10s (最終) |
| **資源利用** | ✅ 按需使用 | ✅ 按需使用 | ❌ 雙重消耗 |
| **容錯** | ✅ 大模型離線自動降級 | ⚠️ Router 單點 | ✅ 互不影響 |
| **可觀測性** | ✅ 簡單日誌 | ✅ 路由統計 | ✅ 對比分析 |
| **用戶體驗** | ⚠️ 升級時等較久 | ⚠️ 升級時等較久 | ✅ 最快看到結果 |
| **實作複雜度** | ✅ 低 | ⚠️ 中 | ❌ 高 |
| **維護複雜度** | ✅ 低 | ⚠️ 中 | ⚠️ 中 |

---

## 8. 建議選擇

### 🏆 首選：方案 A (Proxy 模式)

**理由**：
1. **HQ 零改動**：Android/iOS HQ App 完全不需要修改，向後相容
2. **實作最快**：只需修改 `gemma4_server.py` + 新增配置檔
3. **架構最簡**：沒有新增服務，維護負擔最小
4. **容錯佳**：大模型 PC 離線時自動降級為獨立運作

### 進階目標：方案 A → 方案 C 漸進升級

先實作方案 A 確保核心功能正常，未來可逐步升級到方案 C 獲得更好的用戶體驗：
1. **Phase 1**：方案 A — 只改後端，HQ 不動
2. **Phase 2**：在方案 A 基礎上加入 WebSocket 推播，HQ 可選展示兩階段結果
3. **Phase 3**：完整方案 C 並行模式

---

## 附錄：需新增/修改的檔案清單

### 方案 A 修改清單

| 檔案 | 動作 | 說明 |
|------|------|------|
| `win11/gemma4_server.py` | 修改 | 加入配置載入、信心度解析、升級轉發、`/escalate` 端點、`/peer/ping` 端點 |
| `win11/dual_config.json` | 新增 | 雙模型配置檔（角色、IP、閾值） |
| `win11/start_all.bat` | 修改 | 加入角色選擇提示 |
| `win11/start_hq.bat` | 修改 | 加入角色選擇提示 |

### 方案 B 額外修改

| 檔案 | 動作 | 說明 |
|------|------|------|
| `win11/router_server.py` | 新增 | 獨立路由服務 |
| `win11/start_all.bat` | 修改 | 啟動 router |
| HQ App 連線配置 | 修改 | 端口改為 `:8000` |

### 方案 C 額外修改

| 檔案 | 動作 | 說明 |
|------|------|------|
| `win11/tcp_server.py` | 修改 | 支援 `preliminary_decision` / `final_decision` |
| `win11/hq_server.py` | 修改 | 兩階段推播 |
| Android HQ `HQViewModel.kt` | 修改 | 兩階段決策 State |
| Android HQ UI | 修改 | 兩階段展示 |
| iOS HQ `LinkGuardViewModel.swift` | 修改 | 兩階段決策 State |
| iOS HQ UI | 修改 | 兩階段展示 |

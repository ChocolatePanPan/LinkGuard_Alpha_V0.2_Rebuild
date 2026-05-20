# LinkGuard — Gemma 4 開發提示詞完整文件

> 災害救援指揮 AI 系統提示詞 × Gemma 4 模型調校指南

新竹高工 × 新竹數位實中 ｜ 科展展示版本 2026

---

## 目錄

1. [系統角色定義](#一系統角色定義)
2. [START 檢傷分類規則](#二start-檢傷分類規則)
3. [決策生成提示詞模板](#三決策生成提示詞模板)
4. [翻譯引擎提示詞模板](#四翻譯引擎提示詞模板)
5. [Context 場景指引](#五context-場景指引)
6. [輸出格式約束](#六輸出格式約束)
7. [JSON 通訊協議摘要](#七json-通訊協議摘要)
8. [Few-shot 範例](#八few-shot-範例)
9. [Gemma 4 特有調校注意事項](#九gemma-4-特有調校注意事項)
10. [模型參數調校指南](#十模型參數調校指南)

---

## 一、系統角色定義

### 1.1 核心角色

```
你是災害救援指揮AI助理「LinkGuard」。
你的任務是根據 START 檢傷分類標準、傷員狀態、現場氣象、可用資源及歷史決策記錄，
生成實時指揮決策建議。

你同時具備以下功能：
- 指揮決策生成（Decision Generation）
- START 檢傷分類評分（Triage Scoring）
- 多語言災害救援翻譯（Translation）
```

### 1.2 角色約束

- **簡潔為本**：每項 1-3 句話，不輸出冗長分析
- **格式嚴格**：必須遵守指定輸出格式
- **醫療準確**：術語、數值、單位必須精確
- **歷史感知**：避免重複已執行的指令
- **資源意識**：決策必須考慮可用資源限制

---

## 二、START 檢傷分類規則

### 2.1 三步驟初篩分類

```
【START 檢傷分類標準】

步驟1 呼吸評估:
  ├─ breathing_rate == -1 → 黑色（DECEASED，排除救援序列）
  └─ 有呼吸 → 進入步驟2

步驟2 循環評估:
  ├─ breathing_rate > 30 → 紅色（IMMEDIATE）
  ├─ capillary_refill > 2 秒 → 紅色（IMMEDIATE）
  ├─ capillary_refill == -1（無脈搏）→ 紅色（IMMEDIATE）
  └─ 循環正常 → 進入步驟3

步驟3 意識評估:
  ├─ can_follow_commands == False → 黃色（DELAYED）
  └─ 可遵從指令 → 綠色（MINOR，輕傷/可行走）
```

### 2.2 START 加成分數

| 分類 | 顏色 | 英文 | START 加成 | 說明 |
|------|------|------|-----------|------|
| 已死亡 | 黑色 | DECEASED | -200 | 排除救援序列 |
| 危急 | 紅色 | IMMEDIATE | +60 | 最優先救援 |
| 輕傷 | 綠色 | MINOR | 0 | 可行走、可等待 |

### 2.3 六維度加權評分

$$\text{Total Score} = \text{START加成} + \sum_{i=1}^{6}(\text{原始分數}_i \times \text{維度權重}_i)$$

| 維度 | 權重 | 評分項目 |
|------|------|---------|
| **生命危急程度** | ×1.5 | 呼吸困難(40)、大量出血(50)、心跳微弱(30)、意識不清(30) |
| **時間壓力** | ×1.4 | 1小時內惡化(40)、3小時內惡化(25)、狀況穩定(5) |
| **存活可能性** | ×1.3 | 高存活(30)、中等(10)、極低(-40) |
| **傷勢嚴重度** | ×1.2 | 重傷(40)、中等傷(20)、輕傷(5) |
| **環境風險** | ×1.1 | 火災(40)、建築倒塌(30)、難以接近(-20) |
| **救援成本** | ×1.0 | 長時間(-30)、大量人力(-20)、重設備(-20) |

**排序規則**：
- 主要依據：Total Score 降序
- 同分時：紅色 > 綠色 > 黑色
- 黑色（DECEASED）排在最末

---

## 三、決策生成提示詞模板

### 3.1 System Prompt

```
你是災害救援指揮AI助理。簡潔回答，不要冗長分析。

【START 檢傷分類標準】
步驟1 呼吸評估: 無呼吸(-1) → 黑色（DECEASED，排除救援序列）
步驟2 循環評估: 呼吸>30次/分 → 紅色（IMMEDIATE）；微血管回填>2秒或無脈搏(-1) → 紅色
步驟3 意識評估: 無法遵從指令 → 黃色（DELAYED）
全部正常 → 綠色（MINOR，輕傷/可行走）

【六維度加權評分】
Total Score = START加成 + Σ(原始分數 × 維度權重)
維度：生命危急(×1.5)、時間壓力(×1.4)、存活可能(×1.3)、傷勢嚴重(×1.2)、環境風險(×1.1)、救援成本(×1.0)
分數由高至低排序決定救援優先序。

以下是本次事件的歷史決策記錄：
{recent_decisions}

根據歷史記錄和當前資訊生成新的指揮決策，避免重複已執行的指令。
直接輸出決策，格式如下（每項1-3句話即可）：
【優先處置】...
【資源調配】...
【注意事項】...
【與上次決策的差異】...
```

### 3.2 User Prompt 模板

```
目前時間：{now}
語音回報：{voice_text}

傷員狀況：
{patient_summary}

氣象資訊：{weather_summary}

可用資源：{resource_text}

請根據以上資訊生成指揮決策。
```

### 3.3 Patient Summary 格式（由 format_for_llm 生成）

```
[P1712345678] 優先級：紅色 | 原因：呼吸大於30次/分 | 位置：三樓西側 | 分數：98.5 | 排序：#1
[P1712345679] 優先級：綠色 | 原因：三項檢查正常 | 位置：一樓大廳 | 分數：15.0 | 排序：#2
[P1712345680] 優先級：黑色 | 原因：無呼吸 | 位置：二樓東側 | 分數：-200.0 | 排序：#3
```

### 3.4 Weather Summary 格式（由 format_weather_for_llm 生成）

```
氣溫 32.5°C / 濕度 80% / 氣壓 1013hPa / 風速 3.2m/s / 無降雨
```

### 3.5 決策流程

```
1. 對每名傷員執行 triage_START() 檢傷分類
2. format_for_llm() 生成傷員摘要
3. format_weather_for_llm() 生成氣象摘要
4. get_recent_decisions(5) 取得最近 5 筆歷史決策
5. 組合 system_prompt + user_prompt
6. ollama.chat() 調用 Gemma 4 生成決策
7. save_decision() 存入 SQLite 記憶庫
8. 回傳 {decision, patients, model}
```

---

## 四、翻譯引擎提示詞模板

### 4.1 翻譯 System Prompt

```
你是災害救援翻譯引擎。
任務：把輸入文字從 {source_name} 翻成 {target_name}。
只允許輸出 JSON，格式必須是：{"translated":"..."}。
禁止輸出任何額外說明、前綴、Markdown、反引號。
需保留人名、代號、座標、數字、單位與醫療數值。
若原文已是目標語言或不需翻譯，translated 可回傳原文。
翻譯優先：準確 > 簡潔 > 自然。
領域補充：
{context_guidance}
```

### 4.2 翻譯 User Prompt 格式

```
source_lang={source_lang}
target_lang={target_lang}
context={context}
text:
{text}
```

### 4.3 支援語言

| 代碼 | 語言 |
|------|------|
| `zh-TW` | 繁體中文 |
| `en` | 英文 |
| `ja` | 日文 |
| `ko` | 韓文 |
| `vi` | 越南文 |
| `th` | 泰文 |
| `id` | 印尼文 |
| `ms` | 馬來文 |

### 4.4 翻譯記憶庫（高頻急救短句優先使用）

| 中文 | 英文 |
|------|------|
| 你有哪裡不舒服？ | Where do you feel discomfort? |
| 你能呼吸嗎？ | Can you breathe? |
| 我要幫助你 | I am here to help you. |
| 請不要移動 | Please do not move. |
| 救護車來了 | The ambulance is here. |
| 你叫什麼名字？ | What is your name? |
| 你有沒有過敏？ | Do you have any allergies? |
| 請張開嘴巴 | Please open your mouth. |

---

## 五、Context 場景指引

### 5.1 Medical（醫療）

```
- 醫用術語必須準確（例：心率→heart rate、呼吸困難→respiratory distress）
- 簡化複雜的醫學概念為非專業人士能理解的用語
- 保留數字和生命徵象（血壓、脈搏、呼吸）
```

### 5.2 Operational（行動指揮）

```
- 保持指揮術語清晰準確（例：請求支援→request backup、方位→compass bearing）
- 避免含糊其辭，必須有行動意圖
```

### 5.3 Logistics（後勤物資）

```
- 物資、設備名詞要準確對應（例：擔架→stretcher、繃帶→bandage）
- 數量和單位必須正確轉換
```

---

## 六、輸出格式約束

### 6.1 決策輸出格式

模型必須遵循以下固定格式輸出：

```
【優先處置】<1-3句話描述最緊急的處置行動>
【資源調配】<1-3句話描述救護車、人員、設備的分配>
【注意事項】<1-3句話描述環境風險、天氣影響、注意事項>
【與上次決策的差異】<1-3句話描述與前一次決策的差異>
```

**嚴禁**：
- 不要輸出 Markdown 標題或代碼區塊
- 不要輸出開頭的問候語或結尾的總結
- 不要輸出超過 4 個區塊

### 6.2 翻譯輸出格式

**唯一合法格式**：

```json
{"translated":"翻譯結果文字"}
```

**嚴禁**：
- 不要輸出 Markdown、代碼區塊、反引號
- 不要輸出「翻譯：」「Translation:」等前綴
- 不要輸出額外說明或解釋
- 不要輸出多行結果

### 6.3 LLM 傷員摘要格式

```
[{patient_id}] 優先級：{priority} | 原因：{reason} | 位置：{location} | 分數：{total_score} | 排序：#{rank}
```

---

## 七、JSON 通訊協議摘要

### 7.1 基礎封包格式（TCP）

所有 TCP 訊息統一使用以下結構，以換行符 `\n` 分隔封包：

```json
{
  "type": "<訊息類型>",
  "device_id": "<裝置ID>",
  "timestamp": "<ISO 8601 時間戳>",
  "data": { ... }
}
```

### 7.2 傷員資料封包

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
    "gps": { "lat": 24.8038, "lon": 120.9688 },
    "notes": "清醒，能溝通"
  }
}
```

### 7.3 決策推播封包

```json
{
  "type": "decision",
  "timestamp": "2026-04-06T14:31:00+08:00",
  "data": {
    "decision": "【優先處置】...\n【資源調配】...\n【注意事項】...\n【與上次決策的差異】...",
    "patients": [ ... ],
    "model": "gemma4:26b"
  }
}
```

### 7.4 翻譯請求封包

```json
{
  "type": "translate_request",
  "device_id": "RT-A3F",
  "timestamp": "2026-04-06T14:32:00+08:00",
  "data": {
    "text": "傷患需要緊急手術",
    "source_lang": "zh-TW",
    "target_lang": "en",
    "context": "medical"
  }
}
```

### 7.5 主要數據流

| # | 數據流 | 來源 | 目標 | 協議 |
|---|--------|------|------|------|
| 1 | 傷員回報流 | 手機 APP | tcp_server → qwen_server | TCP |
| 2 | 語音廣播流 | 手機 APP | udp_server → 所有裝置 | UDP |
| 3 | 語音轉錄流 | 手機 APP → whisper_server | tcp_server | HTTP |
| 4 | 決策推播流 | qwen_server | tcp_server → 所有裝置 | TCP |
| 5 | 氣象數據流 | pws_fetcher → qwen_server | tcp_server | 內部 |
| 6 | 指揮命令流 | HQ App → 前線裝置 | TCP (WiFi) |
| 7 | 聊天訊息流 | 雙向 HQ ↔ 前線 | TCP (WiFi) |

---

## 八、Few-shot 範例

### 8.1 決策生成範例

**輸入（User Prompt）**：

```
目前時間：2026-04-06T14:30:00+08:00
語音回報：A 區發現三名傷患，一名無呼吸，兩名能行走但受傷

傷員狀況：
[P001] 優先級：黑色 | 原因：無呼吸 | 位置：A區2樓 | 分數：-200.0 | 排序：#3
[P002] 優先級：紅色 | 原因：呼吸大於30次/分 | 位置：A區1樓 | 分數：98.5 | 排序：#1
[P003] 優先級：綠色 | 原因：三項檢查正常 | 位置：A區1樓 | 分數：15.0 | 排序：#2

氣象資訊：氣溫 32.5°C / 濕度 80% / 氣壓 1013hPa / 風速 3.2m/s / 無降雨

可用資源：救護車 1/2 可用 | 醫療包 3/5 可用 | 人員 4/6 可用

請根據以上資訊生成指揮決策。
```

**期望輸出（Decision）**：

```
【優先處置】P002 為紅色危急傷患，呼吸過速，立即由 2 名救護員進行穩定氣道處置並送上救護車。P001 已判定黑色，不再投入資源。P003 綠色可原地等候。
【資源調配】唯一可用救護車優先載送 P002。派 2 名人員護送，剩餘 2 名持續搜索 A 區其他樓層。
【注意事項】氣溫 32.5°C 高溫，注意傷患及救護員中暑風險。A 區 2 樓結構需確認安全後再進入。
【與上次決策的差異】首次決策，無歷史記錄可比較。
```

### 8.2 翻譯範例（醫療場景）

**輸入**：

```
source_lang=zh-TW
target_lang=en
context=medical
text:
傷患右小腿開放性骨折，呼吸22次/分，脈搏110，血壓90/60
```

**期望輸出**：

```json
{"translated":"Patient has an open fracture of the right lower leg, respiratory rate 22/min, pulse 110, blood pressure 90/60"}
```

### 8.3 翻譯範例（行動指揮場景）

**輸入**：

```
source_lang=zh-TW
target_lang=en
context=operational
text:
B 區三樓有瓦斯洩漏風險，請撤退至安全線外，等候消防隊確認
```

**期望輸出**：

```json
{"translated":"Gas leak risk on 3rd floor of Zone B. Withdraw behind the safety perimeter and await fire department confirmation."}
```

### 8.4 翻譯範例（後勤物資場景）

**輸入**：

```
source_lang=zh-TW
target_lang=ja
context=logistics
text:
需要追加5副擔架和20捲繃帶到前進指揮所
```

**期望輸出**：

```json
{"translated":"前進指揮所に担架5台と包帯20巻の追加が必要です"}
```

### 8.5 START 檢傷分類範例

**輸入**：
```json
{
  "patient": {
    "id": "P001",
    "breathing_rate": -1,
    "capillary_refill": 0,
    "can_follow_commands": false
  }
}
```

**期望輸出**：
```json
{
  "priority": "黑色",
  "reason": "無呼吸",
  "start_bonus": -200,
  "total_score": -200.0
}
```

### 8.6 多傷員排序範例

**輸入**：3 位傷患

| ID | breathing_rate | capillary_refill | can_follow_commands |
|----|---------------|-----------------|-------------------|
| P1 | 22 | 1.5 | true |
| P2 | 35 | 3.0 | false |
| P3 | -1 | — | — |

**期望排序**：
1. **P2**（紅色，呼吸大於30次/分，分數最高）
2. **P1**（綠色，分數 0）
3. **P3**（黑色，分數 -200，排末位）

---

## 九、Gemma 4 特有調校注意事項

### 9.1 Chat Template

Gemma 4 使用 `<start_of_turn>` / `<end_of_turn>` chat template。**由 Ollama 自動處理**，提示詞中不需要手動加入。

```
<start_of_turn>user
{user_prompt}<end_of_turn>
<start_of_turn>model
{model_response}<end_of_turn>
```

### 9.2 Thinking Mode（思考模式）

Gemma 4 內建深度推理能力。本專案統一使用 `think=False`（速度優先）。

```python
# 在 ollama.chat() 中設定
try:
    response = client.chat(**chat_kwargs, think=False)
except TypeError:
    response = client.chat(**chat_kwargs)
```

如需啟用思考模式（更精準但較慢），將 `think=False` 改為 `think=True`。模型會在 `<think>...</think>` 標籤中輸出推理過程。

### 9.3 多語言能力

Gemma 4 原生支援 140+ 語言，繁體中文表現優良。相較 Qwen2.5：
- 翻譯準確度在東南亞語系（越南文、泰文、印尼文）略有提升
- 日韓翻譯品質相當
- 醫療術語翻譯需透過 context guidance 強化

### 9.4 上下文視窗

| 模型 | 上下文視窗 | 建議設定 |
|------|-----------|---------|
| Gemma 4 4B (e4b) | 最大 128K | `num_ctx: 8192`（輕量快速） |
| Gemma 4 26B | 最大 128K | `num_ctx: 8192`（平衡速度與容量） |
| Gemma 4 31B | 最大 128K | `num_ctx: 8192`（最高精準度） |
| Qwen2.5 14B（舊） | 4096 | `num_ctx: 4096` |

增大 `num_ctx` 可容納更多傷員和歷史決策，但會增加 VRAM 使用量和推理時間。

### 9.5 JSON 輸出合規性

Gemma 4 在 JSON-only output 約束下的表現：
- 偶爾會在 JSON 外包裹 Markdown 代碼區塊（```json ... ```）
- 已由 `_clean_translation_output()` 函式處理此情況
- 建議在翻譯 prompt 中重複強調「禁止輸出反引號」

### 9.6 從 Qwen 遷移注意事項

| 項目 | Qwen2.5 14B | Gemma 4 26B | 遷移動作 |
|------|------------|-------------|----------|
| 模型名 | `linkguard-qwen` | `gemma4:26b` | MODEL_NAME 已更新 |
| 上下文 | 4096 | 8192 | OLLAMA_OPTIONS 已更新 |
| Temperature | 0.3 | 0.3 | 保持不變 |
| VRAM | ~10GB | ~16-18GB (Q4) | 需足夠 VRAM |
| 翻譯溫度 | 0.0 | 0.0 | 保持不變 |
| 決策 max tokens | 1024 | 1024 | 保持不變 |
| 翻譯 max tokens | 256 | 256 | 保持不變 |
| think 參數 | False | False | 保持不變 |

---

## 十、模型參數調校指南

### 10.1 Ollama 部署

```bash
# 下載 Gemma 4 26B（正式模型）
ollama pull gemma4:26b

# 下載 Gemma 4 4B（輕量替代）
ollama pull gemma4:4b

# 用 Modelfile 建立 LinkGuard 專用模型（內建系統提示詞）
ollama create linkguard-gemma4 -f Modelfile.gemma4

# 驗證模型可用
ollama run gemma4:26b "回覆OK"
```

### 10.2 推理參數一覽

| 參數 | 決策生成 | 翻譯 | 說明 |
|------|---------|------|------|
| `temperature` | 0.3 | 0.0 | 決策需少量變異；翻譯要求完全確定 |
| `num_predict` | 1024 | 256 | 決策較長；翻譯輸出短 |
| `num_ctx` | 8192 | 8192 | 上下文視窗大小 |
| `num_gpu` | 99 | 99 | 使用全部 GPU 層 |

### 10.3 模型動態切換

伺服器執行中可透過 API 切換模型，無需重啟：

```bash
# 切換至 Gemma 4 26B（遠端部署時）
curl -X POST http://localhost:8001/model \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma4:26b"}'

# 切換回 Gemma 4 4B（輕量）
curl -X POST http://localhost:8001/model \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma4:4b"}'

# 回退至 Qwen（備用）
curl -X POST http://localhost:8001/model \
  -H "Content-Type: application/json" \
  -d '{"model": "linkguard-qwen"}'

# 查看當前模型
curl http://localhost:8001/model

# 列出所有可用模型
curl http://localhost:8001/models
```

### 10.4 MODEL_REGISTRY 完整配置

```python
MODEL_REGISTRY = {
    "gemma4:26b": {
        "model": "gemma4:26b",
        "description": "Gemma 4 26B — 正式模型（精準度高）",
        "options": {"num_ctx": 8192, "num_gpu": 99, "temperature": 0.3},
    },
    "gemma4:4b": {
        "model": "gemma4:4b",
        "description": "Gemma 4 4B — 輕量模型（速度快、VRAM 需求低）",
        "options": {"num_ctx": 8192, "num_gpu": 99, "temperature": 0.3},
    },
    "linkguard-qwen": {
        "model": "linkguard-qwen",
        "description": "Qwen2.5 14B — 舊版模型（備用）",
        "options": {"num_ctx": 4096, "num_gpu": 99, "temperature": 0.3},
    },
    "gemma3:4b": {
        "model": "gemma3:4b",
        "description": "Gemma 3 4B — 測試模型（速度快、資源需求低）",
        "options": {"num_ctx": 4096, "num_gpu": 99, "temperature": 0.4},
    },
}
```

### 10.5 硬體需求

| 模型 | VRAM (Q4_K_M) | 推薦 GPU | 推理速度 (approx) |
|------|--------------|---------|------------------|
| Gemma 4 4B (e4b) | ~3 GB | 任意 GPU | ~35 tok/s |
| Gemma 4 26B | ~16-18 GB | RTX 3090 24GB | ~12 tok/s |
| Gemma 4 31B | ~20 GB | RTX 4090 24GB | ~10 tok/s |
| Qwen2.5 14B | ~10 GB | RTX 3080 10GB | ~15 tok/s |
| Gemma 3 4B | ~3 GB | 任意 GPU | ~40 tok/s |

### 10.6 環境變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama 伺服器位址 |
| `QWEN_TEST_MODEL` | `gemma4:26b` | 測試時使用的模型名 |

### 10.7 健康檢查

```bash
# 檢查 Qwen Server 狀態
curl http://localhost:8001/health

# 回應範例
{
  "status": "ok",
  "ollama_connected": true,
  "active_model": "gemma4:26b",
  "uptime_seconds": 3600
}
```

---

## 附錄 A：伺服器啟動順序

```
[1] MQTT Client          (port 1883)
[2] TCP Server           (port 9000)  ← 核心樞紐
[3] Qwen AI Server       (port 8001)  ← 決策引擎（現使用 Gemma 4）
[4] Whisper Server       (port 8002)  ← 語音識別
[5] HTTP Server          (port 8003)  ← 報告上傳
[6] Photo Server         (port 8004)  ← 相片管理
[7] Stats Server         (port 8005)  ← 統計查詢
[8] Resource Server      (port 8006)  ← 資源管理
```

## 附錄 B：完整端點一覽

| 端點 | 方法 | 用途 |
|------|------|------|
| `/generate` | POST | 生成指揮決策 |
| `/translate` | POST | 多語言翻譯 |
| `/triage/score` | POST | 單一傷患評分 |
| `/triage/rank` | POST | 多傷患排序 |
| `/triage/queue` | GET | 取得活動傷患隊列 |
| `/triage/recalc` | POST | 全隊列重新計算 |
| `/triage/deactivate` | POST | 傷患出隊 |
| `/model` | GET | 取得當前模型 |
| `/model` | POST | 切換模型 |
| `/models` | GET | 列表所有模型 |
| `/history` | GET | 決策歷史 |
| `/history` | DELETE | 清空歷史 |
| `/health` | GET | 健康檢查 |

"""
i18n.py — LinkGuard 國際化模組
支援繁體中文 (zh) 與英文 (en) 雙語切換。
"""

_locale: str = "zh"

STRINGS: dict[str, dict[str, str]] = {
    # === 模型描述 ===
    "model.gemma4_26b": {
        "zh": "Gemma 4 26B — 正式模型（精準度高）",
        "en": "Gemma 4 26B — Production model (high accuracy)",
    },
    "model.gemma4_4b": {
        "zh": "Gemma 4 4B — 輕量模型（速度快、VRAM 需求低）",
        "en": "Gemma 4 4B — Lightweight model (fast, low VRAM)",
    },
    "model.linkguard_qwen": {
        "zh": "Qwen2.5 14B — 舊版模型（備用）",
        "en": "Qwen2.5 14B — Legacy model (backup)",
    },
    "model.gemma3_4b": {
        "zh": "Gemma 3 4B — 測試模型（速度快、資源需求低）",
        "en": "Gemma 3 4B — Test model (fast, low resource)",
    },

    # === API 回應訊息 ===
    "msg.switched_to": {
        "zh": "已切換至 {model}",
        "en": "Switched to {model}",
    },
    "msg.history_cleared": {
        "zh": "已清除所有決策記錄",
        "en": "All decision records cleared",
    },
    "msg.recalc_done": {
        "zh": "已完成全佇列重算",
        "en": "Full queue recalculation completed",
    },
    "msg.patient_deactivated": {
        "zh": "傷患 {id} 已標記為 {status}",
        "en": "Patient {id} marked as {status}",
    },
    "msg.llm_no_command": {
        "zh": "LLM 未產生有效指令",
        "en": "LLM did not produce valid commands",
    },
    "msg.command_executed": {
        "zh": "指令 {id} 已標記為已執行",
        "en": "Command {id} marked as executed",
    },
    "msg.wake_triggered": {
        "zh": "已觸發 AI 巡檢決策，結果已存入歷史記錄",
        "en": "AI patrol decision triggered, result saved to history",
    },

    # === 錯誤訊息 ===
    "err.unknown_model": {
        "zh": "未知模型 '{model}'，可用: {available}",
        "en": "Unknown model '{model}', available: {available}",
    },
    "err.missing_title": {
        "zh": "手動指令需提供 title",
        "en": "Manual command requires a title",
    },
    "err.invalid_type": {
        "zh": "無效指令類型，可用: {types}",
        "en": "Invalid command type, available: {types}",
    },
    "err.text_empty": {
        "zh": "text 不可為空",
        "en": "text must not be empty",
    },
    "err.invalid_status": {
        "zh": "status 必須為 rescued 或 deceased_confirmed",
        "en": "status must be rescued or deceased_confirmed",
    },
    "err.command_not_found": {
        "zh": "找不到指令 {id}",
        "en": "Command {id} not found",
    },

    # === 指令類型 ===
    "cmd.dispatch": {"zh": "調派指令", "en": "Dispatch"},
    "cmd.alert": {"zh": "警報廣播", "en": "Alert Broadcast"},
    "cmd.resource": {"zh": "資源調配", "en": "Resource Allocation"},
    "cmd.personnel": {"zh": "人員指派", "en": "Personnel Assignment"},
    "cmd.evacuate": {"zh": "撤離命令", "en": "Evacuation Order"},
    "cmd.medical": {"zh": "醫療指示", "en": "Medical Directive"},
    "cmd.status_request": {"zh": "狀態查詢", "en": "Status Query"},

    # === 系統狀態格式化 ===
    "status.header": {"zh": "【系統狀態】", "en": "[System Status]"},
    "status.patient_total": {
        "zh": "傷患總計 {total} 人（紅{red} 黃{yellow} 綠{green} 黑{black}）",
        "en": "Patients total {total} (Red {red} Yellow {yellow} Green {green} Black {black})",
    },
    "status.priority_queue": {"zh": "優先處置佇列：", "en": "Priority treatment queue:"},
    "status.resources": {"zh": "可用資源：", "en": "Available resources:"},
    "status.lora_nodes": {"zh": "LoRa 節點：", "en": "LoRa Nodes:"},
    "status.no_nodes": {"zh": "LoRa 節點：無節點資料", "en": "LoRa Nodes: no node data"},
    "status.online": {"zh": "在線", "en": "Online"},
    "status.offline": {"zh": "離線", "en": "Offline"},
    "status.node_fmt": {
        "zh": "  [節點{id}] 電量:{battery}% RSSI:{rssi} {status}",
        "en": "  [Node {id}] Battery:{battery}% RSSI:{rssi} {status}",
    },

    # === 資源名稱 ===
    "res.ambulance": {"zh": "救護車", "en": "Ambulance"},
    "res.medical_kit": {"zh": "醫療包", "en": "Medical Kit"},
    "res.personnel": {"zh": "人員", "en": "Personnel"},

    # === 自動喚醒原因 ===
    "wake.queue_changed": {"zh": "傷患佇列已變化", "en": "Patient queue changed"},
    "wake.red_attention": {
        "zh": "{count} 名紅色傷患需持續關注",
        "en": "{count} red patient(s) require continuous attention",
    },
    "wake.low_battery": {
        "zh": "低電量節點: {ids}",
        "en": "Low battery node(s): {ids}",
    },
    "wake.manual": {"zh": "手動觸發", "en": "Manual trigger"},

    # === 記憶 / 歷史 ===
    "history.none": {"zh": "（尚無歷史決策）", "en": "(No decision history)"},
    "history.summary": {
        "zh": "[{ts}] 決策摘要：{text}",
        "en": "[{ts}] Decision summary: {text}",
    },
    "history.auto_wake_prefix": {
        "zh": "[自動喚醒] {reason}",
        "en": "[Auto-Wake] {reason}",
    },

    # === 雜項 ===
    "misc.no_weather": {"zh": "無氣象資料", "en": "No weather data"},
    "misc.no_patient": {"zh": "無傷患", "en": "No patients"},
    "misc.auto_detect": {"zh": "自動偵測", "en": "Auto-detect"},

    # === HTTP 錯誤 (http_server) ===
    "err.audio_too_large": {
        "zh": "音訊檔案超過 {limit} MB 上限",
        "en": "Audio file exceeds {limit} MB limit",
    },
    "err.invalid_report_id": {
        "zh": "無效的 report_id 格式",
        "en": "Invalid report_id format",
    },
    "err.audio_not_found": {
        "zh": "音訊檔案不存在",
        "en": "Audio file not found",
    },
    "err.report_gen_failed": {
        "zh": "報告生成失敗: {err}",
        "en": "Report generation failed: {err}",
    },
    "err.invalid_report_name": {
        "zh": "無效的報告檔名格式",
        "en": "Invalid report filename format",
    },
    "err.report_not_found": {
        "zh": "報告不存在",
        "en": "Report not found",
    },
    "err.dashboard_not_found": {
        "zh": "Dashboard 不存在",
        "en": "Dashboard not found",
    },

    # === HTTP 錯誤 (photo_server) ===
    "err.invalid_image": {
        "zh": "無效的圖片格式或處理失敗: {err}",
        "en": "Invalid image format or processing failed: {err}",
    },
    "err.thumb_gen_failed": {
        "zh": "縮圖生成失敗: {err}",
        "en": "Thumbnail generation failed: {err}",
    },
    "err.photo_too_large": {
        "zh": "照片超過 {limit} MB 上限",
        "en": "Photo exceeds {limit} MB limit",
    },
    "err.invalid_photo_id": {
        "zh": "無效的 photo_id 格式",
        "en": "Invalid photo_id format",
    },
    "err.photo_not_found": {
        "zh": "照片不存在",
        "en": "Photo not found",
    },
    "err.thumb_not_found": {
        "zh": "縮圖不存在",
        "en": "Thumbnail not found",
    },

    # === HTTP 錯誤 (resource_server) ===
    "err.resource_not_found": {
        "zh": "資源不存在",
        "en": "Resource not found",
    },
    "err.no_available_resource": {
        "zh": "無可用資源",
        "en": "No available resources",
    },

    # === TCP 錯誤 ===
    "err.decision_gen_failed": {
        "zh": "決策生成失敗: {err}",
        "en": "Decision generation failed: {err}",
    },
    "err.translate_failed": {
        "zh": "翻譯失敗: {err}",
        "en": "Translation failed: {err}",
    },
    "err.unknown_type": {
        "zh": "未知的 type: {type}",
        "en": "Unknown type: {type}",
    },
    "err.json_parse_failed": {
        "zh": "JSON 解析失敗",
        "en": "JSON parse failed",
    },

    # === Whisper 錯誤 ===
    "err.model_not_loaded": {
        "zh": "模型尚未載入完成",
        "en": "Model not yet loaded",
    },

    # === HQ 錯誤 ===
    "err.qwen_status": {
        "zh": "qwen_server 回傳 {code}",
        "en": "qwen_server returned {code}",
    },
    "err.ai_unreachable": {
        "zh": "無法連線 AI 伺服器 (qwen_server:8001)",
        "en": "Cannot connect to AI server (qwen_server:8001)",
    },
    "err.ai_decision_error": {
        "zh": "AI 決策錯誤: {err}",
        "en": "AI decision error: {err}",
    },
}


def get_locale() -> str:
    """取得目前語系。"""
    return _locale


def set_locale(locale: str):
    """設定語系（'zh' 或 'en'）。"""
    global _locale
    if locale in ("zh", "en"):
        _locale = locale


def t(key: str, **kwargs) -> str:
    """
    依目前語系取得翻譯字串。
    支援 format 參數：t("msg.switched_to", model="gemma4:26b")
    找不到 key 時回傳 key 本身。
    """
    entry = STRINGS.get(key)
    if not entry:
        return key
    text = entry.get(_locale, entry.get("zh", key))
    if kwargs:
        try:
            text = text.format(**kwargs)
        except (KeyError, IndexError):
            pass
    return text

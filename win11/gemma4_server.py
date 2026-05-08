import asyncio
import builtins
import json
import logging
import os
import re
import socket
import sys
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, PlainTextResponse
from collections import deque
from pydantic import BaseModel, Field
import ollama

# === 日誌設定（檔案 + console，print 也會被重導向）===
_LOG_DIR = Path(__file__).parent / "logs"
_LOG_DIR.mkdir(exist_ok=True)
_LOG_FILE = _LOG_DIR / "gemma4_server.log"

_log_formatter = logging.Formatter(
    "%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
_file_handler = RotatingFileHandler(
    _LOG_FILE, maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
)
_file_handler.setFormatter(_log_formatter)
_console_handler = logging.StreamHandler(sys.stdout)
_console_handler.setFormatter(_log_formatter)

logging.basicConfig(level=logging.INFO, handlers=[_file_handler, _console_handler])
logger = logging.getLogger("gemma4")

# 將既有的 print(...) 同步寫入 log（保留 console 輸出）
_real_print = builtins.print


def _logged_print(*args, **kwargs):
    try:
        msg = " ".join(str(a) for a in args)
        logger.info(msg)
    except Exception:
        pass
    return _real_print(*args, **kwargs)


builtins.print = _logged_print

from start_triage import (
    triage_START, format_for_llm,
    calculate_total_score, rank_patients, score_dimensions,
)
from weather_fetcher import format_weather_for_llm
import linkguard_db
from utils import api_ok, api_error, health_check_response, send_to_tcp_with_retry, get_local_ip
from i18n import t, get_locale, set_locale, STRINGS as I18N_STRINGS

# === 設定 ===
MODEL_NAME = "gemma4-linkguard2.0"
RUNTIME_MODEL_NAME = "gemma4:26b"
OLLAMA_HOST = "http://localhost:11434"
TZ_TW = timezone(timedelta(hours=8))

# === 雙模型配置 ===

_DUAL_CONFIG_PATH = Path(__file__).parent / "dual_config.json"


def _load_dual_config() -> dict:
    """載入雙模型配置，找不到或格式錯誤時回傳預設（停用）。"""
    try:
        if _DUAL_CONFIG_PATH.exists():
            with open(_DUAL_CONFIG_PATH, encoding="utf-8") as f:
                cfg = json.load(f)
            if isinstance(cfg, dict):
                return cfg
    except Exception as e:
        print(f"[DUAL] 載入 dual_config.json 失敗: {e}")
    return {"enabled": False}


def _save_dual_config(cfg: dict):
    """寫回 dual_config.json。"""
    with open(_DUAL_CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=4)


DUAL_CFG: dict = _load_dual_config()

# 對端存活狀態
_peer_alive: bool = False
_peer_last_ping: float = 0.0
_peer_info: dict = {}
_peer_ping_task: Optional[asyncio.Task] = None

# === 雙模型自動探索 (LAN UDP broadcast) ===
DUAL_DISCOVERY_PORT = int(os.environ.get("LINKGUARD_DUAL_DISCOVERY_PORT", "8011"))
DUAL_DISCOVERY_MAGIC = "linkguard-ai"
_discovered_peer_ip: str = ""
_discovery_last_seen: float = 0.0
_dual_announce_task: Optional[asyncio.Task] = None
_dual_discover_task: Optional[asyncio.Task] = None


def _peer_host_is_auto() -> bool:
    """判斷是否應啟用自動探索（peer_host 為空或 "auto"）。"""
    host = (DUAL_CFG.get("peer_host") or "").strip().lower()
    return host in ("", "auto")


# === 後台活動追蹤（給簡易儀表板用）===
_AI_ACTIVITIES: deque = deque(maxlen=200)
_HTTP_ACTIVITIES: deque = deque(maxlen=200)


def record_ai_activity(action: str, target: str = "", detail: str = "", status: str = "ok"):
    """記錄一筆 AI 活動。target=目的地（local / peer / broadcast），detail=輸出片段。"""
    _AI_ACTIVITIES.append({
        "ts": time.time(),
        "iso": datetime.now(TZ_TW).strftime("%H:%M:%S"),
        "action": action,
        "target": target,
        "detail": (detail or "")[:240],
        "status": status,
    })

# === 雙模型異步升級狀態 ===

# 小模型側：追蹤 in-flight 升級請求
# request_id -> {
#   "status": "pending"|"queued"|"processing"|"done"|"failed"|"not_required",
#   "queue_position": int|None,
#   "small_decision": str,
#   "small_confidence": float,
#   "small_confidence_reason": str,
#   "small_model_time_ms": int,
#   "final_decision": str|None,
#   "error": str|None,
#   "created_at": float,
#   "updated_at": float,
# }
_pending_escalations: dict = {}
_PENDING_TTL_SEC = 600  # 10 分鐘後清理

# 大模型側：佇列 + 序列化執行
_LARGE_MODEL_SEM = asyncio.Semaphore(1)
_LARGE_QUEUE: list = []  # request_id 列表，head 為下一個要處理的
_LARGE_QUEUE_LOCK = asyncio.Lock()
_LARGE_QUEUE_INFO: dict = {}  # request_id -> {"callback_url": str, "received_at": float}
MAX_LARGE_QUEUE = 10

# === 雙 AI Session 隔離 + 共識上報監控 ===
#
# 架構：
# - 同一 gemma4 實例，利用 session_id 區分不同使用者群體
# - 預期兩大 session 類型：
#     "hq_commander"            — HQ macOS App 指揮官對話
#     "field_{device_id}"        — iOS Field App 救援人員對話（每裝置一 session）
# - 兩側在 _DUAL_CONSENSUS_WINDOW_SEC 秒內分別都觸發 ESCALATE → 共識成立
#   → 統一呼叫 /escalate 上報主模型 + TCP 廣播 escalation_trigger

_SESSION_STORE: dict[str, list[dict]] = {}  # session_id -> [{"role", "content"}] 最多 24 輪
_SESSION_MAX_HISTORY = 24
_SESSION_TTL_SEC = 3600  # 1 小時無活動即清理
_SESSION_TOUCHED: dict[str, float] = {}  # session_id -> last activity monotonic ts

# 共識監控狀態
# _CONSENSUS_SIGNALS: deque[(side: str, session_id: str, ts: float, summary: str)]
# side ∈ {"hq", "field"}
_CONSENSUS_SIGNALS: deque = deque()
_DUAL_CONSENSUS_WINDOW_SEC = 60.0
_DUAL_CONSENSUS_COOLDOWN_SEC = 120.0  # 避免重複觸發
_last_consensus_fire_ts: float = 0.0
_CONSENSUS_LOCK = asyncio.Lock()

# 關鍵字降級偵測（LLM 未輸出 [ESCALATE:YES] 標記時的 fallback）
_ESCALATE_KEYWORDS = (
    "需要主模型", "請指揮中心", "請指揮中心介入", "超出現場能力",
    "無法判斷", "建議上報", "需上報", "請求支援", "需要更強的模型",
)


def _classify_session_side(session_id: str) -> str:
    """將 session_id 分類為 'hq' 或 'field'；未匹配返回 'unknown'。"""
    if not session_id:
        return "unknown"
    if session_id == "hq_commander" or session_id.startswith("hq_"):
        return "hq"
    if session_id.startswith("field_") or session_id.startswith("field"):
        return "field"
    return "unknown"


def _detect_escalation_signal(reply: str) -> bool:
    """偵測 LLM 回覆中是否包含上報訊號（顯式標記或關鍵字）。"""
    if not reply:
        return False
    if "[ESCALATE:YES]" in reply:
        return True
    lowered = reply.replace(" ", "")
    return any(kw in lowered for kw in _ESCALATE_KEYWORDS)


def _strip_escalation_marker(reply: str) -> str:
    """移除 [ESCALATE:YES] 標記（關鍵字不移除，保留自然語意）。"""
    return reply.replace("[ESCALATE:YES]", "").strip()


def _get_session_history(session_id: str, limit: int = _SESSION_MAX_HISTORY) -> list[dict]:
    """讀取 session 歷史訊息；順便清理超過 TTL 的 session。"""
    now = _now_ts()
    # GC inactive sessions
    stale = [sid for sid, ts in _SESSION_TOUCHED.items() if now - ts > _SESSION_TTL_SEC]
    for sid in stale:
        _SESSION_STORE.pop(sid, None)
        _SESSION_TOUCHED.pop(sid, None)
    _SESSION_TOUCHED[session_id] = now
    history = _SESSION_STORE.get(session_id, [])
    return history[-limit:] if limit else history


def _append_session_message(session_id: str, role: str, content: str):
    """將新訊息附加到 session 歷史，超過上限時丟棄最舊。"""
    if not session_id or not content:
        return
    bucket = _SESSION_STORE.setdefault(session_id, [])
    bucket.append({"role": role, "content": content})
    if len(bucket) > _SESSION_MAX_HISTORY:
        del bucket[0:len(bucket) - _SESSION_MAX_HISTORY]
    _SESSION_TOUCHED[session_id] = _now_ts()


def _broadcast_escalation_trigger_sync(payload: dict):
    """（阻塞）透過 tcp_server loopback 廣播 escalation_trigger 訊息。
    呼叫方應以 asyncio.to_thread 包裝。"""
    msg = {"type": "broadcast_escalation_trigger", "data": payload}
    try:
        send_to_tcp_with_retry(msg, tag="CONSENSUS", max_retries=2)
    except Exception as e:
        logger.warning(f"[CONSENSUS] 廣播 escalation_trigger 失敗: {e}")


async def _fire_dual_escalation(hq_signal: dict, field_signal: dict):
    """觸發雙 AI 共識上報：
    1. POST /escalate（走自己的 API，複用既有佇列邏輯）
    2. TCP 廣播 escalation_trigger 給所有客戶端

    hq_signal / field_signal: {"session_id", "summary", "ts"}
    """
    global _last_consensus_fire_ts
    now = _now_ts()
    if now - _last_consensus_fire_ts < _DUAL_CONSENSUS_COOLDOWN_SEC:
        logger.info("[CONSENSUS] 冷卻期內，略過本次共識觸發")
        return
    _last_consensus_fire_ts = now

    request_id = _new_request_id()
    hq_summary = hq_signal.get("summary", "")[:400]
    field_summary = field_signal.get("summary", "")[:400]
    combined_prompt = (
        f"【雙 AI 共識上報請求】\n\n"
        f"HQ 指揮官 AI 判斷：\n{hq_summary}\n\n"
        f"現場救援 AI 判斷：\n{field_summary}\n\n"
        f"請主模型綜合雙方判斷，提供最終決策建議。"
    )

    # 1) 寫入 pending 狀態（供後續查詢）
    _pending_escalations[request_id] = {
        "status": "pending",
        "queue_position": None,
        "small_decision": hq_summary or field_summary,
        "small_confidence": 0.4,
        "small_confidence_reason": "dual_ai_consensus",
        "small_model_time_ms": 0,
        "final_decision": None,
        "error": None,
        "created_at": now,
        "updated_at": now,
        "hq_summary": hq_summary,
        "field_summary": field_summary,
    }

    logger.info(f"[CONSENSUS] 雙 AI 共識成立 rid={request_id}")

    # 2) 透過 TCP 廣播給所有客戶端（雙方 UI 同步顯示）
    broadcast_payload = {
        "request_id": request_id,
        "status": "dispatched",
        "hq_summary": hq_summary,
        "field_summary": field_summary,
        "hq_session_id": hq_signal.get("session_id", ""),
        "field_session_id": field_signal.get("session_id", ""),
        "timestamp": datetime.now(TZ_TW).isoformat(),
        "combined_prompt": combined_prompt,
    }
    asyncio.create_task(asyncio.to_thread(_broadcast_escalation_trigger_sync, broadcast_payload))

    # 3) 若本節點是大模型角色，直接走 /escalate 佇列（loopback）
    if _is_large_role():
        try:
            req = EscalateRequest(
                request_id=request_id,
                prompt=combined_prompt,
                voice_text=combined_prompt,
                patients_summary=f"HQ: {hq_summary[:100]}\nField: {field_summary[:100]}",
                small_decision=hq_summary or field_summary,
                small_confidence=0.4,
                small_confidence_reason="dual_ai_consensus",
                callback_url="",
            )
            asyncio.create_task(_process_large_model_request(request_id, req.dict()))
        except Exception as e:
            logger.warning(f"[CONSENSUS] 本地大模型處理建立失敗: {e}")
    else:
        # 非大模型角色：轉送到對端大模型
        peer_host = (DUAL_CFG.get("peer_host") or "").strip()
        if peer_host and peer_host.lower() not in ("", "auto"):
            asyncio.create_task(_forward_escalate_to_peer(request_id, combined_prompt,
                                                         hq_summary, field_summary))


async def _forward_escalate_to_peer(request_id: str, prompt: str,
                                     hq_summary: str, field_summary: str):
    """將共識上報轉送給對端大模型節點。"""
    peer_host = (DUAL_CFG.get("peer_host") or "").strip()
    peer_port = DUAL_CFG.get("peer_port", 8001)
    if not peer_host or peer_host.lower() in ("", "auto"):
        _pending_escalations[request_id]["status"] = "failed"
        _pending_escalations[request_id]["error"] = "no peer host configured"
        return
    url = f"http://{peer_host}:{peer_port}/escalate"
    body = {
        "request_id": request_id,
        "prompt": prompt,
        "voice_text": prompt,
        "patients_summary": f"HQ: {hq_summary[:100]}\nField: {field_summary[:100]}",
        "small_decision": hq_summary or field_summary,
        "small_confidence": 0.4,
        "small_confidence_reason": "dual_ai_consensus",
        "callback_url": "",
    }
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(url, json=body)
            if resp.status_code in (200, 202):
                data = resp.json()
                info = data.get("data", {}) if isinstance(data, dict) else {}
                _pending_escalations[request_id]["status"] = (
                    "queued" if info.get("queue_position", 0) > 1 else "processing"
                )
                _pending_escalations[request_id]["queue_position"] = info.get("queue_position")
            else:
                _pending_escalations[request_id]["status"] = "failed"
                _pending_escalations[request_id]["error"] = f"peer returned {resp.status_code}"
    except Exception as e:
        _pending_escalations[request_id]["status"] = "failed"
        _pending_escalations[request_id]["error"] = str(e)


async def record_escalation_signal(session_id: str, summary: str) -> Optional[dict]:
    """記錄一筆 ESCALATE 訊號，若達成雙側共識則觸發 _fire_dual_escalation。

    Returns:
        若觸發共識，返回 {"request_id": ..., "fired": True}；否則返回 None。
    """
    if not session_id:
        return None
    side = _classify_session_side(session_id)
    if side == "unknown":
        return None

    async with _CONSENSUS_LOCK:
        now = _now_ts()
        # 加入訊號 + 清理過期
        _CONSENSUS_SIGNALS.append({
            "side": side,
            "session_id": session_id,
            "ts": now,
            "summary": summary[:800],
        })
        cutoff = now - _DUAL_CONSENSUS_WINDOW_SEC
        while _CONSENSUS_SIGNALS and _CONSENSUS_SIGNALS[0]["ts"] < cutoff:
            _CONSENSUS_SIGNALS.popleft()

        # 檢查窗口內是否雙側都有訊號
        hq_sig = None
        field_sig = None
        for sig in _CONSENSUS_SIGNALS:
            if sig["side"] == "hq" and hq_sig is None:
                hq_sig = sig
            elif sig["side"] == "field" and field_sig is None:
                field_sig = sig

        if hq_sig and field_sig:
            # 觸發共識（消費掉已用訊號，避免重複）
            _CONSENSUS_SIGNALS.clear()
            logger.info(
                f"[CONSENSUS] 雙側訊號齊備 hq={hq_sig['session_id']} "
                f"field={field_sig['session_id']}"
            )
            # fire 交由非持鎖路徑執行
            asyncio.create_task(_fire_dual_escalation(hq_sig, field_sig))
            return {"fired": True}

    return None
_LARGE_AVG_PROCESS_SEC = 25.0  # 估算等待時間用


def _new_request_id() -> str:
    """產生唯一 request_id（含時間 + 短 uuid）。"""
    return f"REQ-{datetime.now(TZ_TW).strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:6]}"


def _now_ts() -> float:
    return time.monotonic()


def _gc_pending_escalations():
    """移除超過 TTL 的已完成/失敗 entry。"""
    cutoff = _now_ts() - _PENDING_TTL_SEC
    stale = [
        rid for rid, st in _pending_escalations.items()
        if st.get("updated_at", 0) < cutoff
        and st.get("status") in ("done", "failed", "not_required")
    ]
    for rid in stale:
        _pending_escalations.pop(rid, None)


MODEL_ALIASES = {
    "gemma4-linkguard2.0": MODEL_NAME,
    "gemma4-linkguard": MODEL_NAME,
    "linkguard-gamme": MODEL_NAME,
    "linkguard-gemma": MODEL_NAME,
    "linkguard-qwen": MODEL_NAME,
    "linkguard2.0": MODEL_NAME,
    "gamme": MODEL_NAME,
    "GAMME": MODEL_NAME,
    "gemma4:26b": MODEL_NAME,
    "gemma4-26b": MODEL_NAME,
    "gemma4 26b": MODEL_NAME,
    "gemma4:26B": MODEL_NAME,
    "GEMMA4 26B": MODEL_NAME,
    "GEMMA4:26B": MODEL_NAME,
}

# 模型註冊表：key→{model, options, description}
MODEL_REGISTRY = {
    MODEL_NAME: {
        "model": RUNTIME_MODEL_NAME,
        "description_key": "model.gemma4_26b",
        "options": {
            "num_ctx": 12288,
            "num_gpu": 99,
            "temperature": 0.2,
            "top_p": 0.9,
            "repeat_penalty": 1.1,
        },
    },
}


def _model_desc(key: str) -> str:
    """取得模型描述（已翻譯）。"""
    entry = MODEL_REGISTRY.get(key, {})
    return t(entry.get("description_key", ""))

# 當前使用的模型名（目前固定 GEMMA4 26B）
_active_model: str = MODEL_NAME

OLLAMA_OPTIONS = {
    "num_ctx": 8192,
    "num_gpu": 99,
    "temperature": 0.3,
}


def _normalize_model_name(name: str) -> str:
    raw = (name or "").strip()
    if raw in MODEL_ALIASES:
        return MODEL_ALIASES[raw]
    return MODEL_ALIASES.get(raw.lower(), raw.lower())


def _get_active_model() -> str:
    return MODEL_NAME


def _get_runtime_model() -> str:
    """回傳本機 Ollama 實際要跑的模型名。雙模型模式啟用時依角色決定。"""
    if DUAL_CFG.get("enabled") and DUAL_CFG.get("local_model"):
        return DUAL_CFG["local_model"]
    entry = MODEL_REGISTRY.get(_get_active_model())
    if entry and entry.get("model"):
        return entry["model"]
    return RUNTIME_MODEL_NAME


def _get_model_options() -> dict:
    entry = MODEL_REGISTRY.get(_get_active_model())
    if entry:
        return entry["options"]
    return OLLAMA_OPTIONS


def _is_small_role() -> bool:
    """本機是否為小模型（初判）角色。"""
    return DUAL_CFG.get("enabled", False) and DUAL_CFG.get("local_role") == "small"


def _is_large_role() -> bool:
    """本機是否為大模型（深度分析）角色。"""
    return DUAL_CFG.get("enabled", False) and DUAL_CFG.get("local_role") == "large"


# ====================================================================
# Three-tier routing helpers  (Plan v2 Phase A1.2)
#
# Tiers (from dual_config.json):
#   field    : Host B  RTX 4060  gemma4:e2b   field iOS simple chat
#   hq_local : Host B  RTX 4060  gemma4:e4b   field internal upgrade
#   hq_main  : Host A  RTX 3080  gemma4:26b   HQ commander + final escalate
# ====================================================================

def _get_tier_cfg(tier: str) -> dict:
    """回傳指定 tier 的設定 dict，若不存在則回退到 hq_main。"""
    tiers = (DUAL_CFG.get("tiers") or {}) if isinstance(DUAL_CFG, dict) else {}
    if tier in tiers and isinstance(tiers[tier], dict):
        return tiers[tier]
    return tiers.get("hq_main", {
        "name": RUNTIME_MODEL_NAME,
        "host": OLLAMA_HOST,
        "context": 12288,
        "supports_audio": False,
        "thinking_mode": False,
    })


def _resolve_tier_for_session(session_id: str, complexity_hint: str = "auto") -> str:
    """根據 session 類別與複雜度提示決定 tier。

    - hq session  → hq_main
    - field session →  complexity_hint == "complex" 時用 hq_local，否則 field
    - unknown     → 依照 tier_routing 預設
    """
    routing = (DUAL_CFG.get("tier_routing") or {}) if isinstance(DUAL_CFG, dict) else {}
    side = _classify_session_side(session_id)
    if side == "hq":
        return routing.get("hq_session_default_tier", "hq_main")
    if side == "field":
        if str(complexity_hint).lower() == "complex":
            return "hq_local"
        return routing.get("field_session_default_tier", "field")
    return routing.get("hq_session_default_tier", "hq_main")


def _runtime_model_for_tier(tier: str) -> str:
    cfg = _get_tier_cfg(tier)
    return cfg.get("name") or _get_runtime_model()


def _host_for_tier(tier: str) -> str:
    cfg = _get_tier_cfg(tier)
    return cfg.get("host") or OLLAMA_HOST


def _tier_supports_thinking(tier: str) -> bool:
    return bool(_get_tier_cfg(tier).get("thinking_mode", False))


def _tier_context(tier: str) -> int:
    try:
        return int(_get_tier_cfg(tier).get("context", 12288))
    except (TypeError, ValueError):
        return 12288


async def _internal_escalate_to_e4b(messages: list[dict], options: Optional[dict] = None) -> dict:
    """Field 端內部升級：e2b → e4b（同主機本地 Ollama 呼叫）。

    Returns {"reply": str, "model": str, "elapsed_ms": int, "ok": bool, "error": Optional[str]}.
    """
    tier = "hq_local"
    model = _runtime_model_for_tier(tier)
    host = _host_for_tier(tier)
    opts = {**(options or {}), "num_ctx": _tier_context(tier)}
    t0 = time.monotonic()
    try:
        client = ollama.Client(host=host)
        def _call():
            try:
                return client.chat(model=model, messages=messages, options=opts, think=False)
            except TypeError:
                return client.chat(model=model, messages=messages, options=opts)
        resp = await asyncio.to_thread(_call)
        text = (resp.message.content or "").strip()
        return {
            "ok": True,
            "reply": text,
            "model": model,
            "tier": tier,
            "host": host,
            "elapsed_ms": int((time.monotonic() - t0) * 1000),
            "error": None,
        }
    except Exception as e:
        logger.warning(f"[TIER:hq_local] e4b 內部升級失敗: {e}")
        return {
            "ok": False,
            "reply": "",
            "model": model,
            "tier": tier,
            "host": host,
            "elapsed_ms": int((time.monotonic() - t0) * 1000),
            "error": str(e),
        }


async def _external_escalate_to_main(messages: list[dict], options: Optional[dict] = None) -> dict:
    """跨主機升級：呼叫 Host A 的 hq_main (gemma4:26b)，自動啟用 thinking。

    若 host 為 localhost，直接 ollama chat；否則需透過 peer_host 機制
    （目前簡化：仍透過 ollama Client 連到 hq_main host）。
    """
    tier = "hq_main"
    model = _runtime_model_for_tier(tier)
    host = _host_for_tier(tier)
    opts = {**(options or {}), "num_ctx": _tier_context(tier)}
    use_think = _tier_supports_thinking(tier)
    t0 = time.monotonic()
    try:
        client = ollama.Client(host=host)
        def _call():
            try:
                return client.chat(model=model, messages=messages, options=opts, think=use_think)
            except TypeError:
                return client.chat(model=model, messages=messages, options=opts)
        resp = await asyncio.to_thread(_call)
        text = (resp.message.content or "").strip()
        return {
            "ok": True,
            "reply": text,
            "model": model,
            "tier": tier,
            "host": host,
            "thinking": use_think,
            "elapsed_ms": int((time.monotonic() - t0) * 1000),
            "error": None,
        }
    except Exception as e:
        logger.warning(f"[TIER:hq_main] 主模型升級失敗: {e}")
        return {
            "ok": False,
            "reply": "",
            "model": model,
            "tier": tier,
            "host": host,
            "thinking": use_think,
            "elapsed_ms": int((time.monotonic() - t0) * 1000),
            "error": str(e),
        }


START_RULES = (
    "【START 檢傷分類標準】\n"
    "步驟1 呼吸評估: 無呼吸(-1) → 黑色（DECEASED，排除救援序列）\n"
    "步驟2 循環評估: 呼吸>30次/分 → 紅色（IMMEDIATE）；微血管回填>2秒或無脈搏(-1) → 紅色\n"
    "步驟3 意識評估: 無法遵從指令 → 黃色（DELAYED）\n"
    "全部正常 → 綠色（MINOR，輕傷/可行走）\n\n"
    "【六維度加權評分】\n"
    "Total Score = START加成 + Σ(原始分數 × 維度權重)\n"
    "維度：生命危急(×1.5)、時間壓力(×1.4)、存活可能(×1.3)、"
    "傷勢嚴重(×1.2)、環境風險(×1.1)、救援成本(×1.0)\n"
    "分數由高至低排序決定救援優先序。\n"
)


# === 記憶功能（委託 linkguard_db） ===

def save_decision(voice_text: str, patients_summary: str,
                  weather_summary: str, decision_text: str):
    try:
        linkguard_db.save_decision(voice_text, patients_summary,
                                   weather_summary, decision_text,
                                   trigger_type="llm")
    except Exception as e:
        logger.warning(f"[GENERATE] 儲存決策記憶失敗，略過: {e}")


def get_recent_decisions(n: int = 5) -> str:
    try:
        rows = linkguard_db.get_recent_decisions(n)
    except Exception as e:
        logger.warning(f"[GENERATE] 讀取歷史決策失敗，略過: {e}")
        return t("history.none")
    if not rows:
        return t("history.none")
    lines = []
    for row in rows:
        summary = (row.get("decision_text") or "")[:120].replace("\n", " ")
        ts = row.get("timestamp", "")
        lines.append(t("history.summary", ts=ts, text=summary))
    return "\n".join(lines)


# === 動態重算背景任務（每 30 秒） ===

_triage_task: Optional[asyncio.Task] = None
TRIAGE_INTERVAL = 30  # 秒


async def _triage_loop():
    """每 TRIAGE_INTERVAL 秒對活動傷患全佇列重新計分排序。"""
    while True:
        await asyncio.sleep(TRIAGE_INTERVAL)
        try:
            _recalc_all_patients()
        except Exception as e:
            print(f"[TRIAGE] 動態重算失敗: {e}")


def _recalc_all_patients():
    """讀取 DB 中所有 active 傷患，重新計算 total_score 並回寫。"""
    patients = linkguard_db.get_active_patients()
    for p in patients:
        # 還原 can_follow_commands 為 bool
        if p.get("can_follow_commands") is not None:
            p["can_follow_commands"] = bool(p["can_follow_commands"])
        # 還原 dimension flags from dimension_data JSON
        dim_data_raw = p.get("dimension_data", "{}")
        try:
            dim_flags = json.loads(dim_data_raw) if isinstance(dim_data_raw, str) else {}
        except (json.JSONDecodeError, TypeError):
            dim_flags = {}
        merged = {**dim_flags, **p}

        result = calculate_total_score(merged, persist=False)
        linkguard_db.update_patient_score(
            patient_id=p["patient_id"],
            priority=result["priority"],
            reason=result["reason"],
            start_bonus=result["start_bonus"],
            total_score=result["total_score"],
            dimension_data=json.dumps(
                {d["item"]: True for d in result["dimensions"]}, ensure_ascii=False
            ),
        )


# === FastAPI App ===

@asynccontextmanager
async def lifespan(application: FastAPI):
    linkguard_db.init_db()
    global _triage_task, _autowake_task, _peer_ping_task
    global _dual_announce_task, _dual_discover_task
    _triage_task = asyncio.create_task(_triage_loop())
    _autowake_task = asyncio.create_task(_autowake_loop())
    _peer_ping_task = asyncio.create_task(_peer_ping_loop())
    if DUAL_CFG.get("enabled"):
        role = DUAL_CFG.get("local_role", "?")
        model = DUAL_CFG.get("local_model", "?")
        peer_raw = DUAL_CFG.get("peer_host", "")
        peer = f"{peer_raw or 'auto'}:{DUAL_CFG.get('peer_port', 8001)}"
        print(f"[DUAL] 雙模型模式啟用 — 角色={role} 模型={model} 對端={peer}")
        _dual_announce_task = asyncio.create_task(_dual_announce_loop())
        _dual_discover_task = asyncio.create_task(_dual_discover_loop())
    yield
    _triage_task.cancel()
    _autowake_task.cancel()
    _peer_ping_task.cancel()
    tasks = [_triage_task, _autowake_task, _peer_ping_task]
    if _dual_announce_task:
        _dual_announce_task.cancel()
        tasks.append(_dual_announce_task)
    if _dual_discover_task:
        _dual_discover_task.cancel()
        tasks.append(_dual_discover_task)
    for task in tasks:
        try:
            await task
        except asyncio.CancelledError:
            pass

app = FastAPI(title="LinkGuard Qwen Server", lifespan=lifespan)


@app.middleware("http")
async def enforce_utf8_json(request: Request, call_next):
    """確保 JSON 回應明確標示 UTF-8，避免 PowerShell 5 亂碼。"""
    t0 = time.monotonic()
    response = await call_next(request)
    content_type = response.headers.get("content-type", "")
    if content_type.lower().startswith("application/json") and "charset=" not in content_type.lower():
        response.headers["content-type"] = "application/json; charset=utf-8"
    # 記錄 HTTP 活動（排除 dashboard 自輪詢與 peer ping，避免噪音）
    path = request.url.path
    if not path.startswith(("/admin/", "/peer/ping")):
        client_host = request.client.host if request.client else "?"
        _HTTP_ACTIVITIES.append({
            "ts": time.time(),
            "iso": datetime.now(TZ_TW).strftime("%H:%M:%S"),
            "method": request.method,
            "path": path,
            "client": client_host,
            "status": response.status_code,
            "ms": int((time.monotonic() - t0) * 1000),
        })
    return response

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# === 模型管理端點 ===

@app.get("/models")
def list_models():
    """列出所有可用模型及當前使用的模型。"""
    models = []
    for key, entry in MODEL_REGISTRY.items():
        models.append({
            "name": key,
            "description": _model_desc(key),
            "active": key == _get_active_model(),
        })
    return api_ok({"active": _get_active_model(), "models": models})


class ModelSwitchRequest(BaseModel):
    model: str


@app.post("/model")
def switch_model(req: ModelSwitchRequest):
    """切換當前使用的 LLM 模型（目前固定 GEMMA4 26B）。"""
    global _active_model
    normalized = _normalize_model_name(req.model)
    if normalized != MODEL_NAME:
        available = list(MODEL_REGISTRY.keys())
        api_error("UNKNOWN_MODEL", t("err.unknown_model", model=req.model, available=available))
    _active_model = MODEL_NAME
    return api_ok({
        "message": t("msg.switched_to", model=MODEL_NAME),
        "active": MODEL_NAME,
        "description": _model_desc(MODEL_NAME),
    })


@app.get("/model")
def get_current_model():
    """取得當前使用的模型。"""
    return api_ok({
        "active": MODEL_NAME,
        "description": _model_desc(MODEL_NAME),
    })


class GenerateRequest(BaseModel):
    voice_text: str = ""
    patients: object = Field(default_factory=list)
    weather: object = Field(default_factory=dict)
    resources: object = ""
    show_reasoning: bool = False


# === 雙模型：信心度解析與升級判斷 ===

_CONFIDENCE_RE = re.compile(r'【信心度】\s*([\d.]+)\s*[|｜]\s*(.+)')

# 小模型主動標記:遇到複雜情境直接標記需大模型介入
_NEED_BIG_MODEL_RE = re.compile(r'【需大模型分析】\s*(?:原因[：:])?\s*(.+)')

# 小模型專用 system prompt 後綴（要求輸出信心度）
_CONFIDENCE_SUFFIX = (
    "\n\n=== 升級判斷 (必讀) ===\n"
    "你是初判模型,以下情境必須主動標記為「需大模型分析」,讓更強的大模型 (GEMMA4 26B) 介入處理:\n"
    "1. 撤離 / 疏散 / 緊急轉移類決策 (一律升級)\n"
    "2. 同時 ≥ 3 名紅色傷患 (大量傷患事件)\n"
    "3. 多名傷患情報互相矛盾,無法判斷優先順序\n"
    "4. 任一關鍵資源 (擔架/醫療包/AED) 已歸零或使用率 ≥ 90%\n"
    "5. 涉及群眾心理安撫、家屬通報、媒體應對等非醫療決策\n"
    "6. 跨災區、跨指揮區的人力資源衝突\n"
    "7. 你自己對處置順序沒有明確把握\n"
    "命中以上任一情境,在決策最後加上:\n"
    "【需大模型分析】原因:xxx (例如: 涉及撤離決策且紅色傷患>=3)\n"
    "並把信心度設為 0.3 以下。\n\n"
    "在決策最後一行,你必須自評此決策的信心度 (0.0-1.0)。\n"
    "評估標準:\n"
    "- 0.8-1.0: 情況明確,標準處置\n"
    "- 0.6-0.7: 大致清楚但有不確定因素\n"
    "- 0.4-0.5: 情況複雜,多重傷患交互影響\n"
    "- 0.0-0.3: 無法判斷或資訊嚴重不足 (建議升級大模型)\n\n"
    "最後一行格式 (必須嚴格遵守):\n"
    "【信心度】0.XX | 原因簡述"
)


def _parse_need_big_model(decision_text: str) -> tuple[bool, str]:
    """偵測小模型是否主動標記需大模型分析。"""
    match = _NEED_BIG_MODEL_RE.search(decision_text)
    if match:
        return True, match.group(1).strip()
    return False, ""


def _strip_need_big_model_line(text: str) -> str:
    return _NEED_BIG_MODEL_RE.sub("", text).rstrip()


def _parse_confidence(decision_text: str) -> tuple[float, str]:
    """從決策文字中提取信心度分數與原因。"""
    match = _CONFIDENCE_RE.search(decision_text)
    if match:
        try:
            score = min(max(float(match.group(1)), 0.0), 1.0)
        except ValueError:
            score = 0.5
        reason = match.group(2).strip()
        return score, reason
    return 0.5, "模型未輸出信心度評估"


def _strip_confidence_line(decision_text: str) -> str:
    """移除決策文字中的信心度行（回傳給 HQ 時不含此行）。"""
    return _CONFIDENCE_RE.sub("", decision_text).rstrip()


def _should_escalate(confidence: float, ranked: list, resources: str, decision_text: str = "") -> bool:
    """根據信心度 + 規則判斷是否需要升級至大模型。
    若 dual_config.always_escalate=true，則小模型角色一律升級（讓兩個模型都參與）。"""
    if not DUAL_CFG.get("enabled") or not _is_small_role():
        return False

    # 0. 小模型主動標記「需大模型分析」→ 一律升級 (最高優先)
    if decision_text and _NEED_BIG_MODEL_RE.search(decision_text):
        return True

    # 全域開關：always_escalate=true → 小模型 = 初判，永遠送大模型再決策
    if DUAL_CFG.get("always_escalate", True):
        return True

    threshold = DUAL_CFG.get("confidence_threshold", 0.6)
    rules = DUAL_CFG.get("escalation_rules", {})

    # 1. 信心度低於閾值
    if confidence < threshold:
        return True

    # 2. 紅色傷患過多
    min_red = rules.get("min_red_patients_for_auto_escalate", 3)
    red_count = sum(1 for p in ranked if p.get("priority") == "紅色")
    if red_count >= min_red:
        return True

    # 3. 資源歸零
    if resources and "0/" in resources:
        return True

    # 4. 資源使用率超過閾值
    util_threshold = rules.get("resource_utilization_threshold")
    if util_threshold is not None and resources:
        pairs = re.findall(r"(\d+)/(\d+)", resources)
        if pairs:
            max_util = max(
                (int(total) - int(remain)) / int(total)
                for remain, total in pairs if int(total) > 0
            )
            if max_util >= util_threshold:
                return True

    # 5. 撤離決策永遠升級
    if rules.get("always_escalate_evacuation") and decision_text:
        _EVAC_KW = ("撤離", "撤退", "疏散", "避難", "緊急轉移")
        if any(kw in decision_text for kw in _EVAC_KW):
            return True

    return False


async def _peer_available() -> bool:
    """檢查對端是否存活。"""
    return _peer_alive


def _local_callback_base() -> str:
    """大模型 callback 回小模型時用的 URL base。
    優先順序：
      1. dual_config.json 的 local_callback_url（明確指定）
      2. 自動探測本機 IP（get_local_ip）→ http://{ip}:8001
    """
    explicit = (DUAL_CFG.get("local_callback_url") or "").strip()
    if explicit and explicit.lower() != "auto":
        return explicit.rstrip("/")
    try:
        ip = get_local_ip()
        if ip and ip != "127.0.0.1":
            return f"http://{ip}:8001"
    except Exception:
        pass
    return ""


async def _async_escalate_flow(
    request_id: str,
    req: "GenerateRequest",
    small_decision: str,
    confidence: float,
    conf_reason: str,
    ranked: list,
    local_ms: int,
):
    """背景升級流程：POST 到大模型 /escalate（非阻塞），對方回 202+queue_position 後就 return。
    最終結果由大模型透過 callback POST /escalation/result 推回。"""
    state = _pending_escalations.get(request_id)
    if state is None:
        return

    peer_host = DUAL_CFG.get("peer_host", "")
    peer_port = DUAL_CFG.get("peer_port", 8001)
    callback_url = DUAL_CFG.get("local_callback_url", "").strip()
    timeout = DUAL_CFG.get("peer_timeout_sec", 30)
    url = f"http://{peer_host}:{peer_port}/escalate"

    payload = {
        "request_id": request_id,
        "callback_url": callback_url,  # 若空則大模型用 X-Caller-URL header 或 request.client.host
        "original_request": {
            "voice_text": req.voice_text,
            "patients": req.patients,
            "weather": req.weather,
            "resources": req.resources,
        },
        "small_model_result": {
            "decision": small_decision,
            "confidence": confidence,
            "confidence_reason": conf_reason,
            "model": DUAL_CFG.get("local_model", "gemma4:e4b"),
            "elapsed_ms": local_ms,
        },
        "escalation_trigger": "confidence_below_threshold",
        "system_status": _build_system_status(),
    }

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(url, json=payload)
            # 期望 202 Accepted + queue_position
            resp.raise_for_status()
            body = resp.json()
            data = body.get("data", body) if isinstance(body, dict) else {}
            queue_position = data.get("queue_position")
            estimated_wait = data.get("estimated_wait_sec")

            state["status"] = "queued" if (queue_position or 0) > 1 else "processing"
            state["queue_position"] = queue_position
            state["estimated_wait_sec"] = estimated_wait
            state["updated_at"] = _now_ts()
            print(f"[DUAL] 升級已排入大模型佇列 rid={request_id} pos={queue_position}")
            record_ai_activity("升級至大模型", target=f"peer:{peer_host}:{peer_port}",
                               detail=f"rid={request_id} pos={queue_position} eta={estimated_wait}s")
    except Exception as e:
        print(f"[DUAL] 升級至大模型失敗 rid={request_id}: {e}")
        record_ai_activity("升級至大模型", target=f"peer:{peer_host}:{peer_port}",
                           detail=f"失敗: {e}", status="error")
        state["status"] = "failed"
        state["error"] = str(e)
        state["final_decision"] = _strip_confidence_line(small_decision)
        state["updated_at"] = _now_ts()
        return

    # 等待 callback 寫入結果（由 /escalation/result endpoint 處理）
    # 設定 hard timeout = peer_timeout * 6（涵蓋排隊 + 處理）
    hard_timeout = max(timeout * 6, 180)
    deadline = _now_ts() + hard_timeout
    while _now_ts() < deadline:
        st = _pending_escalations.get(request_id)
        if not st or st.get("status") in ("done", "failed"):
            return
        await asyncio.sleep(1.0)

    # Timeout — 標記失敗，使用小模型結果
    st = _pending_escalations.get(request_id)
    if st and st.get("status") not in ("done", "failed"):
        print(f"[DUAL] 升級 callback 逾時 rid={request_id}")
        st["status"] = "failed"
        st["error"] = "escalation_callback_timeout"
        st["final_decision"] = _strip_confidence_line(small_decision)
        st["updated_at"] = _now_ts()


async def _escalate_to_peer(
    req: "GenerateRequest",
    small_decision: str,
    confidence: float,
    conf_reason: str,
    ranked: list,
) -> dict:
    """[已棄用，保留作測試/相容] 同步將請求升級至大模型，回傳大模型結果。
    新流程請用 _async_escalate_flow + callback。"""
    peer_host = DUAL_CFG.get("peer_host", "")
    peer_port = DUAL_CFG.get("peer_port", 8001)
    timeout = DUAL_CFG.get("peer_timeout_sec", 30)
    url = f"http://{peer_host}:{peer_port}/escalate"

    payload = {
        "request_id": _new_request_id(),
        "original_request": {
            "voice_text": req.voice_text,
            "patients": req.patients,
            "weather": req.weather,
            "resources": req.resources,
        },
        "small_model_result": {
            "decision": small_decision,
            "confidence": confidence,
            "confidence_reason": conf_reason,
            "model": DUAL_CFG.get("local_model", "gemma4:e4b"),
        },
        "escalation_trigger": "confidence_below_threshold",
        "system_status": _build_system_status(),
    }

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(url, json=payload)
            resp.raise_for_status()
            return resp.json()
    except Exception as e:
        print(f"[DUAL] 升級至大模型失敗: {e}")
        return {"decision": small_decision, "escalation_failed": True, "error": str(e)}



def _clean_reasoning_output(raw: str) -> dict:
    text = (raw or "").strip()
    if not text:
        return {}

    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z0-9_-]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text).strip()

    try:
        parsed = json.loads(text)
    except Exception:
        return {}

    if not isinstance(parsed, dict):
        return {}

    allowed = {
        "reason_summary": [],
        "risk_notes": [],
        "next_actions": [],
    }
    for key in allowed:
        value = parsed.get(key)
        if isinstance(value, list):
            allowed[key] = [str(x).strip() for x in value if str(x).strip()][:5]
    return allowed


def _rule_fallback_decision(ranked: list, resource_text: str, weather_summary: str, error: Exception) -> str:
    active = ranked or []
    critical = [p for p in active if str(p.get("priority", "")) == "紅色"]
    deceased = [p for p in active if str(p.get("priority", "")) == "黑色"]
    green = [p for p in active if str(p.get("priority", "")) == "綠色"]
    top_patients = active[:3]

    if top_patients:
        patient_lines = []
        for patient in top_patients:
            patient_id = patient.get("id") or patient.get("patient_id") or "未知傷患"
            priority = patient.get("priority", "未分類")
            reason = patient.get("reason", "")
            patient_lines.append(f"{patient_id}（{priority}，{reason}）")
        focus = "；".join(patient_lines)
    else:
        focus = "目前無受困者資料，先維持偵查、通訊與安全區域控管。"

    resource_note = resource_text or "現場資源未回報，先保留醫療包、擔架與撤離通道給紅色傷患。"
    weather_note = weather_summary or t("misc.no_weather")
    error_text = str(error).strip() or "模型服務暫時不可用"

    return (
        "【優先處置】AI 模型服務暫時不可用，已改用 START 規則備援決策。"
        f"目前紅色 {len(critical)} 人、黑色 {len(deceased)} 人、綠色 {len(green)} 人；優先處理：{focus}\n"
        f"【資源調配】{resource_note}\n"
        f"【注意事項】氣象資訊：{weather_note}。請同步確認現場危害、撤離路線與通訊狀態，避免等待模型恢復造成決策空窗。\n"
        "【與上次決策的差異】本次為規則備援輸出，模型恢復後可重新請求 AI 深度建議。\n"
        f"【系統狀態】Ollama / 模型推理不可用：{error_text}"
    )


def _safe_rank_patients_for_generate(raw_patients) -> list:
    if not isinstance(raw_patients, list):
        logger.warning("[GENERATE] patients 不是 list，已改用空清單")
        return []
    patients = [patient for patient in raw_patients if isinstance(patient, dict)]
    if len(patients) != len(raw_patients):
        logger.warning("[GENERATE] patients 含有非 dict 資料，已略過")
    try:
        return rank_patients(patients)
    except Exception as e:
        logger.exception(f"[GENERATE] START 排序失敗，改用保守排序: {e}")
        fallback = []
        for patient in patients:
            try:
                scored = rank_patients([patient])
                fallback.append(scored[0] if scored else patient)
            except Exception as item_error:
                item = dict(patient)
                item.setdefault("priority", "未知")
                item.setdefault("reason", f"資料格式需確認: {item_error}")
                item.setdefault("start_bonus", 0)
                item.setdefault("dimension_score", 0)
                item.setdefault("total_score", 0)
                item.setdefault("dimensions", [])
                fallback.append(item)
        for index, item in enumerate(fallback, 1):
            item["rank"] = index
        return fallback


def _safe_patient_summary_for_generate(ranked: list) -> str:
    if not ranked:
        return "目前無受困者資料。"
    try:
        summary = format_for_llm(ranked)
        return summary or "目前無受困者資料。"
    except Exception as e:
        logger.exception(f"[GENERATE] 傷患摘要格式化失敗，改用精簡摘要: {e}")
        lines = []
        for index, patient in enumerate(ranked, 1):
            patient_id = patient.get("id") or patient.get("patient_id") or f"傷患{index}"
            priority = patient.get("priority", "未知")
            location = patient.get("location", "未知區")
            reason = patient.get("reason", "無")
            lines.append(f"[{patient_id}] 優先級：{priority} | 原因：{reason} | 位置：{location}")
        return "\n".join(lines) or "目前無受困者資料。"


def _safe_weather_summary_for_generate(raw_weather) -> str:
    if not isinstance(raw_weather, dict) or not raw_weather:
        return t("misc.no_weather")
    try:
        return format_weather_for_llm(raw_weather)
    except Exception as e:
        logger.warning(f"[GENERATE] 氣象摘要格式化失敗，略過: {e}")
        return t("misc.no_weather")


def _safe_resource_text_for_generate(raw_resources) -> str:
    resource_text = raw_resources if isinstance(raw_resources, str) else ""
    if resource_text.strip():
        return resource_text
    try:
        summary = linkguard_db.get_resource_summary()
        if summary:
            parts = []
            for rtype, info in summary.items():
                rkey = f"res.{rtype}"
                name = t(rkey) if rkey in I18N_STRINGS else rtype
                if isinstance(info, dict):
                    available = info.get("available", "?")
                    total = info.get("total", "?")
                else:
                    available = "?"
                    total = "?"
                parts.append(f"{name} {available}/{total}")
            return " | ".join(parts)
    except Exception as e:
        logger.warning(f"[GENERATE] 資源摘要讀取失敗，略過: {e}")
    return ""


def _safe_status_text_for_generate() -> str:
    try:
        return _format_status_for_llm()
    except Exception as e:
        logger.warning(f"[GENERATE] 系統狀態摘要失敗，略過: {e}")
        return "系統狀態：暫無可用摘要。"


def _safe_voice_history_for_generate(limit: int = 8) -> str:
    try:
        return _format_recent_voice_for_llm(limit=limit)
    except Exception as e:
        logger.warning(f"[GENERATE] 語音歷史摘要失敗，略過: {e}")
        return ""


@app.post("/generate")
async def generate(req: GenerateRequest):
    # 1. 對每個 patient 進行完整評分（START + 六維度）並排序
    ranked = _safe_rank_patients_for_generate(req.patients)

    # 2. 生成傷員摘要（含分數與排序）
    patient_summary = _safe_patient_summary_for_generate(ranked)

    # 3. 生成氣象摘要
    weather_summary = _safe_weather_summary_for_generate(req.weather)

    # 4. 取得歷史決策記憶
    recent_decisions = get_recent_decisions(5)

    # 5. 自動注入資源狀態
    resource_text = _safe_resource_text_for_generate(req.resources)

    # 5b. 注入系統狀態（節點、傷患統計、佇列）
    status_text = _safe_status_text_for_generate()

    # 6. 組合 system prompt + user prompt
    role_label = DUAL_CFG.get("local_model", "GEMMA4 26B") if _is_small_role() else "GEMMA4 26B"
    system_prompt = (
        f"你是 LinkGuard 災害救援指揮 AI（{role_label}）。\n"
        "請只輸出可執行決策，不要輸出推理過程。\n"
        "決策需具體、可行、可落地，避免空泛建議。\n\n"
        f"{START_RULES}\n"
        f"{status_text}\n\n"
        "以下是本次事件的歷史決策記錄：\n"
        f"{recent_decisions}\n\n"
        "你可以建議發布以下類型的指令：\n"
        "- dispatch（調派）：派遣人員或車輛到指定位置\n"
        "- alert（警報）：廣播緊急通知給所有前線\n"
        "- resource（資源調配）：調配醫療包、擔架等\n"
        "- personnel（人員指派）：分配特定人員負責傷患\n"
        "- evacuate（撤離）：下達撤離命令\n"
        "- medical（醫療指示）：給前線的醫療處置建議\n\n"
        "如需發布指令，在決策最後加上且僅一行：\n"
        "【建議指令】類型=xxx | 優先=1-5 | 內容=xxx\n\n"
        "根據歷史記錄和當前資訊生成新的指揮決策，避免重複已執行的指令。\n"
        "直接輸出決策，格式如下（每項1-3句話即可）：\n"
        "【優先處置】...\n"
        "【資源調配】...\n"
        "【注意事項】...\n"
        "【與上次決策的差異】..."
    )

    # 小模型模式：追加信心度自評要求
    if _is_small_role():
        system_prompt += _CONFIDENCE_SUFFIX

    now = datetime.now(TZ_TW).isoformat()
    voice_history = _safe_voice_history_for_generate(limit=8)
    user_prompt = (
        f"目前時間：{now}\n"
        f"最新語音回報：{req.voice_text}\n\n"
        + (f"{voice_history}\n\n" if voice_history else "")
        + f"傷員狀況：\n{patient_summary}\n\n"
        f"氣象資訊：{weather_summary}\n\n"
        f"可用資源：{resource_text}\n\n"
        "請根據以上資訊生成指揮決策。"
    )

    # 6. 送進 ollama 生成決策（不使用 thinking mode，直接輸出決策）
    active_model = _get_active_model()
    runtime_model = _get_runtime_model()
    model_options = _get_model_options()
    client = ollama.Client(host=OLLAMA_HOST)
    t0 = time.monotonic()
    chat_kwargs = dict(
        model=runtime_model,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        options={**model_options, "temperature": 0.2, "num_predict": 1024},
    )
    try:
        response = client.chat(**chat_kwargs, think=False)
    except TypeError:
        # 舊版 ollama SDK 不支援 think 參數
        try:
            response = client.chat(**chat_kwargs)
        except Exception as e:
            logger.exception(f"[GENERATE] AI 決策生成失敗，使用規則備援: {e}")
            decision = _rule_fallback_decision(ranked, resource_text, weather_summary, e)
            local_ms = int((time.monotonic() - t0) * 1000)
            request_id = _new_request_id()
            save_decision(req.voice_text, patient_summary, weather_summary, decision)
            record_ai_activity("決策生成", target=f"fallback:{runtime_model}", detail=str(e), status="fallback")
            return api_ok({
                "decision": decision,
                "patients": ranked,
                "model": "rule-fallback",
                "escalated": False,
                "provisional": False,
                "escalation_status": "ai_unavailable",
                "queue_position": None,
                "request_id": request_id,
                "ai_unavailable": True,
                "error": str(e),
                "local_model_time_ms": local_ms,
            })
    except Exception as e:
        logger.exception(f"[GENERATE] AI 決策生成失敗，使用規則備援: {e}")
        decision = _rule_fallback_decision(ranked, resource_text, weather_summary, e)
        local_ms = int((time.monotonic() - t0) * 1000)
        request_id = _new_request_id()
        save_decision(req.voice_text, patient_summary, weather_summary, decision)
        record_ai_activity("決策生成", target=f"fallback:{runtime_model}", detail=str(e), status="fallback")
        return api_ok({
            "decision": decision,
            "patients": ranked,
            "model": "rule-fallback",
            "escalated": False,
            "provisional": False,
            "escalation_status": "ai_unavailable",
            "queue_position": None,
            "request_id": request_id,
            "ai_unavailable": True,
            "error": str(e),
            "local_model_time_ms": local_ms,
        })
    decision = (response.message.content or "").strip()
    local_ms = int((time.monotonic() - t0) * 1000)

    # === 雙模型升級判斷（非阻塞：背景處理 + provisional 立即回傳）===
    request_id = _new_request_id()
    provisional = False
    escalation_status = "not_required"
    queue_position = None
    escalation_info = None

    if _is_small_role():
        confidence, conf_reason = _parse_confidence(decision)
        need_big, big_reason = _parse_need_big_model(decision)
        if need_big:
            # 小模型主動標記 → 強制低信心度,並把標記原因併入 reason
            confidence = min(confidence, 0.25)
            conf_reason = f"{conf_reason} | 主動標記: {big_reason}".strip(" |")
        should_esc = _should_escalate(confidence, ranked, resource_text, decision)
        peer_ok = await _peer_available()

        if should_esc and peer_ok:
            trigger = "self_marked_need_big_model" if need_big else "confidence_below_threshold"
            print(f"[DUAL] 觸發升級 rid={request_id} 信心度={confidence:.2f} 原因={conf_reason} trigger={trigger}")
            # 同時剝除信心度行與需大模型標記行
            small_decision_clean = _strip_need_big_model_line(_strip_confidence_line(decision))
            now = _now_ts()
            _pending_escalations[request_id] = {
                "status": "pending",
                "queue_position": None,
                "estimated_wait_sec": None,
                "small_decision": small_decision_clean,
                "small_confidence": confidence,
                "small_confidence_reason": conf_reason,
                "small_model_time_ms": local_ms,
                "final_decision": None,
                "error": None,
                "created_at": now,
                "updated_at": now,
                "patients": ranked,
                "self_marked": need_big,
                "self_marked_reason": big_reason,
            }
            # 背景發送至大模型；callback 會更新 _pending_escalations[request_id]
            asyncio.create_task(_async_escalate_flow(
                request_id, req, small_decision_clean, confidence, conf_reason, ranked, local_ms
            ))
            decision = small_decision_clean
            provisional = True
            escalation_status = "pending"
            escalation_info = {
                "original_model": DUAL_CFG.get("local_model", "gemma4:e4b"),
                "confidence": confidence,
                "confidence_reason": conf_reason,
                "small_model_time_ms": local_ms,
                "trigger": trigger,
                "self_marked": need_big,
            }
        else:
            decision = _strip_need_big_model_line(_strip_confidence_line(decision))
            if should_esc and not peer_ok:
                print("[DUAL] 需要升級但對端離線，使用小模型結果")
                escalation_status = "peer_offline"
            else:
                escalation_status = "not_required"
    # 大模型角色或非雙模型模式，decision 不做處理

    reasoning = {}
    if req.show_reasoning and not provisional:
        reason_system_prompt = (
            "你是災害救援決策說明器。"
            "根據已產生的最終決策，輸出精簡理由摘要。"
            "只輸出 JSON，不要任何額外文字。"
            "格式必須是："
            "{\"reason_summary\":[...],\"risk_notes\":[...],\"next_actions\":[...]}。"
            "每個陣列 1-5 點，每點一句話。"
        )
        reason_user_prompt = (
            f"最終決策：\n{decision}\n\n"
            f"傷患摘要：\n{patient_summary}\n\n"
            f"氣象：{weather_summary}\n"
            f"資源：{resource_text}\n"
            f"系統狀態：\n{status_text}\n"
        )

        reason_chat_kwargs = dict(
            model=runtime_model,
            messages=[
                {"role": "system", "content": reason_system_prompt},
                {"role": "user", "content": reason_user_prompt},
            ],
            options={**model_options, "temperature": 0.0, "num_predict": 512},
        )
        try:
            try:
                reason_response = client.chat(**reason_chat_kwargs, think=False)
            except TypeError:
                reason_response = client.chat(**reason_chat_kwargs)
            reason_raw = (reason_response.message.content or "").strip()
            reasoning = _clean_reasoning_output(reason_raw)
        except Exception as e:
            logger.warning(f"[GENERATE] 理由摘要生成失敗，略過 reasoning: {e}")

    # 7. 儲存決策到記憶（provisional 也存：標記為小模型初判）
    save_decision(req.voice_text, patient_summary, weather_summary, decision)

    # 8. 回傳生成的指揮決策文字
    if _is_small_role():
        result_model = DUAL_CFG.get("local_model", runtime_model)
    else:
        result_model = active_model
    result = {
        "decision": decision,
        "patients": ranked,
        "model": result_model,
        "escalated": False,            # 最終是否由大模型決策；provisional 階段為 False
        "provisional": provisional,    # True 表示等待大模型升級結果
        "escalation_status": escalation_status,  # pending|queued|processing|done|failed|not_required|peer_offline
        "queue_position": queue_position,
        "request_id": request_id,
    }
    if escalation_info:
        result["escalation_info"] = escalation_info
    if req.show_reasoning:
        result["reasoning"] = reasoning or {
            "reason_summary": [],
            "risk_notes": [],
            "next_actions": [],
        }
    return api_ok(result)


# === 雙模型升級：Endpoint 群（小模型側 + 大模型側）===

class EscalateRequest(BaseModel):
    request_id: str
    callback_url: str = ""
    original_request: dict
    small_model_result: dict
    escalation_trigger: str = "confidence_below_threshold"
    system_status: dict = {}


class EscalationResultRequest(BaseModel):
    request_id: str
    decision: str
    model: str = "gemma4:26b"
    elapsed_ms: int = 0
    error: Optional[str] = None
    escalation_failed: bool = False


async def _process_large_model_request(rid: str, payload: dict):
    """大模型側：在 _LARGE_MODEL_SEM 保護下實際執行大模型推理，完成後 callback 小模型。"""
    callback_url = payload.get("callback_url", "").rstrip("/")
    original = payload.get("original_request", {})
    small_result = payload.get("small_model_result", {})

    # 在 semaphore 內序列化執行
    async with _LARGE_MODEL_SEM:
        # 從佇列頭移除自己；若有人在前面（理論不該發生），等他們先
        async with _LARGE_QUEUE_LOCK:
            if rid in _LARGE_QUEUE:
                _LARGE_QUEUE.remove(rid)
            _LARGE_QUEUE_INFO.pop(rid, None)

        t0 = time.monotonic()
        try:
            runtime_model = _get_runtime_model()
            model_options = _get_model_options()
            ollama_client = ollama.Client(host=OLLAMA_HOST)

            voice_text = original.get("voice_text", "")
            patients = original.get("patients", [])
            weather = original.get("weather", {})
            resources = original.get("resources", "")
            ranked = rank_patients(patients) if patients else []
            patient_summary = format_for_llm(ranked) if ranked else "無傷患"
            weather_summary = format_weather_for_llm(weather) if weather else t("misc.no_weather")

            small_dec = (small_result.get("decision") or "").strip()
            small_conf = small_result.get("confidence")
            small_conf_reason = small_result.get("confidence_reason", "")

            system_prompt = (
                "你是 LinkGuard 災害救援指揮 AI（GEMMA4 26B 深度分析模型）。\n"
                "小模型（gemma4:e4b）已產出初判決策，但因信心度不足或情境複雜被升級。\n"
                "請審視小模型的初判結論，**修正、強化或重新組織**最終決策；如初判正確可保留並補充細節。\n"
                "請只輸出可執行決策，不要輸出推理過程，不要輸出信心度行。\n\n"
                f"{START_RULES}\n"
                "輸出格式：\n"
                "【優先處置】...\n"
                "【資源調配】...\n"
                "【注意事項】...\n"
                "【深度分析】（大模型專屬段：補充小模型遺漏的風險、二階效應、跨資源權衡）"
            )
            now = datetime.now(TZ_TW).isoformat()
            user_prompt = (
                f"目前時間：{now}\n"
                f"語音回報：{voice_text}\n\n"
                f"傷員狀況：\n{patient_summary}\n\n"
                f"氣象資訊：{weather_summary}\n\n"
                f"可用資源：{resources}\n\n"
                f"== 小模型初判（信心度={small_conf} 原因={small_conf_reason}）==\n"
                f"{small_dec}\n\n"
                "請輸出最終決策。"
            )

            chat_kwargs = dict(
                model=runtime_model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                options={**model_options, "temperature": 0.2, "num_predict": 1536},
            )
            try:
                response = ollama_client.chat(**chat_kwargs, think=False)
            except TypeError:
                response = ollama_client.chat(**chat_kwargs)
            final_decision = (response.message.content or "").strip()
            elapsed_ms = int((time.monotonic() - t0) * 1000)
            print(f"[DUAL/LARGE] 完成 rid={rid} 耗時={elapsed_ms}ms")

            # Callback to small model
            if callback_url:
                cb_payload = {
                    "request_id": rid,
                    "decision": final_decision,
                    "model": "gemma4:26b",
                    "elapsed_ms": elapsed_ms,
                    "escalation_failed": False,
                }
                await _post_callback(callback_url, cb_payload)
        except Exception as e:
            print(f"[DUAL/LARGE] 處理失敗 rid={rid}: {e}")
            if callback_url:
                await _post_callback(callback_url, {
                    "request_id": rid,
                    "decision": "",
                    "model": "gemma4:26b",
                    "escalation_failed": True,
                    "error": str(e),
                })

    # 處理完成後，廣播新佇列順位給仍在排隊的小模型（best-effort）
    asyncio.create_task(_notify_queue_advance())


async def _post_callback(callback_url: str, payload: dict, retries: int = 2):
    """callback 小模型 /escalation/result。失敗最多重試 retries 次。"""
    url = f"{callback_url.rstrip('/')}/escalation/result"
    last_err = None
    for attempt in range(retries + 1):
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
                return
        except Exception as e:
            last_err = e
            await asyncio.sleep(1.0 * (attempt + 1))
    print(f"[DUAL/LARGE] callback 失敗 {url}: {last_err}")


async def _notify_queue_advance():
    """大模型完成一個請求後，主動把新順位推給仍在排隊的小模型。
    需要每筆 _LARGE_QUEUE_INFO 帶 callback_url。"""
    async with _LARGE_QUEUE_LOCK:
        snapshot = list(_LARGE_QUEUE)
        info = dict(_LARGE_QUEUE_INFO)
    for idx, rid in enumerate(snapshot, start=1):
        meta = info.get(rid, {})
        cb = meta.get("callback_url", "")
        if not cb:
            continue
        try:
            url = f"{cb.rstrip('/')}/escalation/queue_update"
            async with httpx.AsyncClient(timeout=5) as client:
                await client.post(url, json={
                    "request_id": rid,
                    "queue_position": idx,
                    "estimated_wait_sec": idx * _LARGE_AVG_PROCESS_SEC,
                })
        except Exception:
            pass  # best-effort


@app.post("/escalate", status_code=202)
async def escalate(req: EscalateRequest):
    """大模型側接受小模型升級請求。立即回 202 + queue_position，背景序列化處理。"""
    if not _is_large_role():
        raise HTTPException(status_code=400, detail="此節點非大模型角色")

    rid = req.request_id or _new_request_id()

    async with _LARGE_QUEUE_LOCK:
        if len(_LARGE_QUEUE) >= MAX_LARGE_QUEUE:
            raise HTTPException(status_code=503, detail=f"大模型佇列已滿（{MAX_LARGE_QUEUE}）")
        if rid not in _LARGE_QUEUE:
            _LARGE_QUEUE.append(rid)
        _LARGE_QUEUE_INFO[rid] = {
            "callback_url": req.callback_url,
            "received_at": _now_ts(),
        }
        position = _LARGE_QUEUE.index(rid) + 1

    # 啟動處理 task；它會在 _LARGE_MODEL_SEM 保護下序列化
    asyncio.create_task(_process_large_model_request(rid, req.dict()))

    return api_ok({
        "request_id": rid,
        "queued": True,
        "queue_position": position,
        "estimated_wait_sec": position * _LARGE_AVG_PROCESS_SEC,
    })


@app.post("/escalation/result")
async def escalation_result(req: EscalationResultRequest):
    """小模型側接收大模型 callback。寫入 _pending_escalations 完成狀態。"""
    state = _pending_escalations.get(req.request_id)
    if not state:
        raise HTTPException(status_code=404, detail=f"unknown request_id: {req.request_id}")

    if req.escalation_failed:
        state["status"] = "failed"
        state["error"] = req.error or "large_model_failed"
        state["final_decision"] = state.get("small_decision") or ""
    else:
        state["status"] = "done"
        state["final_decision"] = req.decision
        state["large_model_time_ms"] = req.elapsed_ms
        state["large_model"] = req.model
    state["updated_at"] = _now_ts()
    print(f"[DUAL/SMALL] 收到大模型結果 rid={req.request_id} status={state['status']}")
    _gc_pending_escalations()
    return api_ok({"request_id": req.request_id, "status": state["status"]})


class QueueUpdateRequest(BaseModel):
    request_id: str
    queue_position: int
    estimated_wait_sec: float = 0


@app.post("/escalation/queue_update")
async def escalation_queue_update(req: QueueUpdateRequest):
    """小模型側接收大模型主動推送的佇列順位變化。"""
    state = _pending_escalations.get(req.request_id)
    if not state:
        return api_ok({"request_id": req.request_id, "ignored": True})
    if state.get("status") in ("done", "failed"):
        return api_ok({"request_id": req.request_id, "ignored": True})
    state["queue_position"] = req.queue_position
    state["estimated_wait_sec"] = req.estimated_wait_sec
    state["status"] = "queued" if req.queue_position > 1 else "processing"
    state["updated_at"] = _now_ts()
    return api_ok({"request_id": req.request_id, "status": state["status"]})


@app.get("/escalation/{request_id}")
async def get_escalation_status(request_id: str):
    """查詢升級請求目前狀態（給 tcp_server / HQ 輪詢）。"""
    state = _pending_escalations.get(request_id)
    if not state:
        raise HTTPException(status_code=404, detail=f"unknown request_id: {request_id}")
    return api_ok({
        "request_id": request_id,
        "status": state.get("status"),
        "queue_position": state.get("queue_position"),
        "estimated_wait_sec": state.get("estimated_wait_sec"),
        "small_decision": state.get("small_decision"),
        "small_confidence": state.get("small_confidence"),
        "small_confidence_reason": state.get("small_confidence_reason"),
        "small_model_time_ms": state.get("small_model_time_ms"),
        "final_decision": state.get("final_decision"),
        "large_model_time_ms": state.get("large_model_time_ms"),
        "large_model": state.get("large_model"),
        "error": state.get("error"),
        "patients": state.get("patients", []),
    })


@app.get("/escalation_queue")
async def get_escalation_queue():
    """大模型側除錯：查詢目前佇列。"""
    if not _is_large_role():
        raise HTTPException(status_code=400, detail="此節點非大模型角色")
    async with _LARGE_QUEUE_LOCK:
        snapshot = [
            {
                "request_id": rid,
                "queue_position": idx + 1,
                "callback_url": _LARGE_QUEUE_INFO.get(rid, {}).get("callback_url", ""),
                "received_at": _LARGE_QUEUE_INFO.get(rid, {}).get("received_at"),
            }
            for idx, rid in enumerate(_LARGE_QUEUE)
        ]
    return api_ok({"queue": snapshot, "max_queue": MAX_LARGE_QUEUE})


# === HQ AI 自由對話 ===

class ChatMessageItem(BaseModel):
    role: str  # "user" | "assistant"
    content: str


class ChatRequest(BaseModel):
    message: str
    history: list[ChatMessageItem] = []
    system_prompt: Optional[str] = None
    # 雙 AI 隔離：不同使用者群體用不同 session_id（預設 "default" 保持向後相容）
    #   "hq_commander"          — HQ macOS App 指揮官對話
    #   "field_{device_id}"     — iOS Field App 救援人員對話（每裝置一 session）
    session_id: str = "default"
    # 是否啟用後端 session 歷史（若 true 則伺服器端維護歷史，client 可忽略 history 參數）
    use_server_session: bool = False


# Unicode emoji 範圍 (主要區段),用於剝除模型輸出中的表情符號
_EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F680-\U0001F6FF"  # transport & map
    "\U0001F700-\U0001F77F"
    "\U0001F780-\U0001F7FF"
    "\U0001F800-\U0001F8FF"
    "\U0001F900-\U0001F9FF"  # supplemental symbols & pictographs
    "\U0001FA00-\U0001FA6F"
    "\U0001FA70-\U0001FAFF"
    "\U00002600-\U000026FF"  # misc symbols (☀ ☁ ⚠ ✅ etc.)
    "\U00002700-\U000027BF"  # dingbats (✂ ✈ ✔ ✖ etc.)
    "\U0001F1E6-\U0001F1FF"  # flags
    "\U0000FE0F"             # variation selector-16
    "\U0000200D"             # zero-width joiner
    "]+",
    flags=re.UNICODE,
)

# 行首 Markdown 標題: 1~6 個 # 後面接空白
_MD_HEADING_RE = re.compile(r"^#{1,6}\s+", flags=re.MULTILINE)


def _sanitize_chat_reply(text: str) -> str:
    """移除 emoji 與 Markdown # 標題語法,將標題改以 **粗體** 呈現。"""
    if not text:
        return text
    # 1) 將行首 # 標題改成 **粗體** (保留標題文字)
    def _heading_to_bold(match: re.Match) -> str:
        # 取整行,去掉行首 #
        return ""
    # 處理整行: 行首 # ... -> **...**
    cleaned_lines: list[str] = []
    for line in text.splitlines():
        m = _MD_HEADING_RE.match(line)
        if m:
            title = line[m.end():].strip().rstrip("#").strip()
            cleaned_lines.append(f"**{title}**" if title else "")
        else:
            cleaned_lines.append(line)
    text = "\n".join(cleaned_lines)
    # 2) 剝除所有 emoji
    text = _EMOJI_RE.sub("", text)
    # 3) 收斂多餘空白
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


@app.post("/chat")
async def hq_chat(req: ChatRequest):
    """HQ 指揮官與 AI 自由對話 (非結構化決策)。
    自動注入當前傷患/資源/節點狀態,讓 AI 能基於實況回答。"""
    user_msg = (req.message or "").strip()
    if not user_msg:
        return api_ok({"reply": "", "model": _get_active_model()})

    # === Plan v2 Phase A2: 三層 tier 路由 ===
    session_id = (req.session_id or "default").strip() or "default"
    tier = _resolve_tier_for_session(session_id)
    runtime_model = _runtime_model_for_tier(tier)
    runtime_host = _host_for_tier(tier)
    active_model = _get_active_model()
    model_options = {**_get_model_options(), "num_ctx": _tier_context(tier)}

    # 自動注入即時情境:系統狀態 + 詳細傷患清單
    try:
        status_text = _format_status_for_llm()
    except Exception as e:
        logger.warning(f"[CHAT] 取得系統狀態失敗: {e}")
        status_text = ""
    try:
        active_patients = linkguard_db.get_active_patients() or []
        # 重新計分以確保資料齊全(與 /generate 一致)
        ranked = rank_patients(active_patients) if active_patients else []
        patient_detail = format_for_llm(ranked) if ranked else "(目前無活動傷患)"
    except Exception as e:
        logger.warning(f"[CHAT] 取得傷患清單失敗: {e}")
        patient_detail = "(無法讀取傷患資料)"
    voice_history = _format_recent_voice_for_llm(limit=10)

    base_system = req.system_prompt or (
        "你是 LinkGuard 災害救援指揮 AI 助理,負責協助 HQ 指揮官思考、規劃與決策。\n"
        "回覆風格:精準、專業、條列、避免空泛口號;若資訊不足請主動詢問。\n"
        "回覆語言:正體中文。\n"
        "格式規則(嚴格遵守):\n"
        "1. 嚴禁使用任何 emoji 或表情符號 (例如 ✅ ⚠️ 🔥 📌 等),全部以純文字表達。\n"
        "2. 嚴禁使用 Markdown 標題語法,即不得出現 # ## ### #### 等井字號開頭的行。\n"
        "3. 需要強調的標題或重點,改用 **粗體** (兩個星號) 表示,例如 **行動方案**。\n"
        "4. 條列使用 - 或 1. 2. 3.,不要使用井字號。"
    )
    system_prompt = (
        f"{base_system}\n\n"
        f"=== 當前現場即時狀態 (供你決策參考,使用者未必會重複提及) ===\n"
        f"{status_text}\n\n"
        f"=== 活動傷患詳細資料 ===\n"
        f"{patient_detail}\n"
        + (f"\n{voice_history}\n" if voice_history else "")
        + f"=== 狀態結束 ===\n"
        f"當使用者詢問傷患、優先級、資源或人員時,請直接引用上述資料作答,不要回答「沒有資訊」。"
    )

    # 組合對話歷史 (最多保留最近 12 輪)
    messages: list[dict] = [{"role": "system", "content": system_prompt}]
    # 優先使用 server session 歷史（若啟用），否則使用 client 傳來的 history
    if req.use_server_session and session_id != "default":
        server_hist = _get_session_history(session_id, limit=12)
        for h in server_hist:
            role = h.get("role", "")
            content = (h.get("content") or "").strip()
            if role in ("user", "assistant") and content:
                messages.append({"role": role, "content": content})
    else:
        for m in (req.history or [])[-12:]:
            if m.role in ("user", "assistant") and (m.content or "").strip():
                messages.append({"role": m.role, "content": m.content})
    messages.append({"role": "user", "content": user_msg})

    client = ollama.Client(host=runtime_host)
    t0 = time.monotonic()
    chat_kwargs = dict(
        model=runtime_model,
        messages=messages,
        options={**model_options, "temperature": 0.4, "num_predict": 768},
    )

    def _call_ollama():
        try:
            return client.chat(**chat_kwargs, think=False)
        except TypeError:
            return client.chat(**chat_kwargs)

    record_ai_activity("HQ對話", target=f"local:{runtime_model}", detail=user_msg[:120])
    try:
        response = await asyncio.to_thread(_call_ollama)
    except ConnectionError as e:
        logger.warning(f"[CHAT] Ollama 連線失敗: {e}")
        record_ai_activity("HQ對話", target=f"local:{runtime_model}",
                           detail=f"Ollama 連線失敗: {e}", status="error")
        api_error(
            "ollama_unavailable",
            f"AI 模型服務 (Ollama @ {OLLAMA_HOST}) 無法連線，請確認 Ollama 已啟動。",
            status_code=503,
        )
    except Exception as e:
        logger.exception(f"[CHAT] AI 對話失敗: {e}")
        record_ai_activity("HQ對話", target=f"local:{runtime_model}",
                           detail=f"失敗: {e}", status="error")
        api_error("chat_failed", f"AI 對話失敗: {e}", status_code=500)

    raw_reply = (response.message.content or "").strip()

    # === 雙 AI 共識上報：偵測 ESCALATE 訊號並記錄 ===
    escalate_detected = _detect_escalation_signal(raw_reply)
    side = _classify_session_side(session_id)
    escalate_info = None
    if escalate_detected and side in ("hq", "field"):
        try:
            fired = await record_escalation_signal(session_id, raw_reply)
            escalate_info = {
                "detected": True,
                "side": side,
                "consensus_fired": bool(fired and fired.get("fired")),
            }
        except Exception as e:
            logger.warning(f"[CONSENSUS] 記錄訊號失敗: {e}")
            escalate_info = {"detected": True, "side": side, "consensus_fired": False}
    elif escalate_detected:
        escalate_info = {"detected": True, "side": side, "consensus_fired": False}

    reply = _strip_escalation_marker(raw_reply)
    reply = _sanitize_chat_reply(reply)

    # === Plan v2 Phase A2: 前線端內部升級 e2b → e4b ===
    # 若是 field session 且 e2b 偵測到 ESCALATE，且 routing 啟用 auto_internal_escalate
    # → 自動以 e4b (hq_local) 重跑一次，將升級結果一併回傳供 client 顯示。
    upgraded_reply: Optional[dict] = None
    routing_cfg = (DUAL_CFG.get("tier_routing") or {})
    if (escalate_detected and side == "field" and tier == "field"
            and routing_cfg.get("auto_internal_escalate_field_to_hq_local", True)):
        try:
            up_msgs = list(messages)  # 沿用同樣 system + history
            up = await _internal_escalate_to_e4b(up_msgs,
                                                 options={"temperature": 0.4, "num_predict": 768})
            if up.get("ok") and up.get("reply"):
                up_text = _sanitize_chat_reply(_strip_escalation_marker(up["reply"]))
                upgraded_reply = {
                    "tier": up["tier"],
                    "model": up["model"],
                    "reply": up_text,
                    "elapsed_ms": up.get("elapsed_ms"),
                }
                # 將升級後的回覆覆寫成主要 reply，原 e2b 結果保留於 lower_tier_reply
                lower_tier_payload = {"tier": tier, "model": runtime_model, "reply": reply}
                reply = up_text
                upgraded_reply["lower_tier_reply"] = lower_tier_payload
        except Exception as e:
            logger.warning(f"[CHAT] field 內部升級 e4b 失敗: {e}")

    # === Server session 歷史寫回 ===
    if req.use_server_session and session_id != "default":
        _append_session_message(session_id, "user", user_msg)
        if reply:
            _append_session_message(session_id, "assistant", reply)

    elapsed_ms = int((time.monotonic() - t0) * 1000)
    record_ai_activity("HQ對話完成", target=f"local:{runtime_model}",
                       detail=f"{elapsed_ms}ms · {reply[:160]}")

    result = {
        "reply": reply,
        "model": active_model,
        "runtime_model": runtime_model,
        "tier": tier,
        "elapsed_ms": elapsed_ms,
        "session_id": session_id,
    }
    if escalate_info:
        result["escalation"] = escalate_info
    if upgraded_reply:
        result["upgraded_reply"] = upgraded_reply
    return api_ok(result)


# === HQ AI 副駕駛：對話 + 結構化指令提案（HITL）===

# 16 大可審批指令類型（Plan v2 Phase A4 擴充）
# 每筆 metadata：mode = "auto" | "manual"
#                countdown_sec = 自動派發前的可取消秒數（0 = 不倒數立即執行）
#                require_human_double_confirm = 即使 auto 模式也須人類雙確認
_AI_PROPOSAL_META: dict[str, dict] = {
    # —— 自動派發類（低風險）——
    "dispatch":               {"mode": "auto",   "countdown_sec": 5, "require_human_double_confirm": False},
    "status_check":           {"mode": "auto",   "countdown_sec": 0, "require_human_double_confirm": False},
    "escalate_to_main":       {"mode": "auto",   "countdown_sec": 0, "require_human_double_confirm": False},
    "medical_priority_change":{"mode": "auto",   "countdown_sec": 5, "require_human_double_confirm": False},
    "resource_relocate":      {"mode": "auto",   "countdown_sec": 5, "require_human_double_confirm": False},
    "recall":                 {"mode": "auto",   "countdown_sec": 5, "require_human_double_confirm": False},
    "checkpoint":             {"mode": "auto",   "countdown_sec": 5, "require_human_double_confirm": False},
    # —— 人工審批類（高風險）——
    "alert":                  {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": False},
    "medical":                {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": False},
    "resource":               {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": False},
    "personnel":              {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": False},
    "evacuate":               {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": True},
    "emergency_evacuation":   {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": True},
    "force_broadcast":        {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": False},
    "task_order":             {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": False},
    "zone_lockdown":          {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": True},
}
_AI_PROPOSAL_TYPES = tuple(_AI_PROPOSAL_META.keys())

_AI_TOOLS_INSTRUCTION = (
    "\n\n=== AI 副駕駛指令模式（重要）===\n"
    "你除了用中文回答指揮官，還可以針對情勢「提出可執行指令建議」，"
    "由 HQ 指揮官審批後才會發布。如果你判斷需要建議任何行動，請在文字回覆之後，"
    "另起一行附上一個 fenced JSON block，格式如下：\n"
    "```json\n"
    "{\"proposals\": [\n"
    "  {\"type\": \"dispatch\", \"priority\": 2, \"title\": \"標題（不超過 20 字）\","
    " \"detail\": \"完整指令內容\", \"targets\": [], \"rationale\": \"為何建議此指令\"}\n"
    "]}\n"
    "```\n"
    "規則：\n"
    "1. type 僅可為下列之一："
    + ", ".join(_AI_PROPOSAL_TYPES)
    + "（dispatch=派遣搜救隊、status_check=狀態確認、escalate_to_main=升級主模型、"
    "medical_priority_change=傷患優先級調整、resource_relocate=資源轉移、recall=召回隊員、"
    "checkpoint=設立檢查點、alert=預警、medical=醫療後送、resource=資源調度、personnel=人員指派、"
    "evacuate=撤離、emergency_evacuation=緊急疏散(高風險,需雙確認)、"
    "force_broadcast=強制廣播、task_order=任務派令、zone_lockdown=區域封鎖)。\n"
    "2. priority 為整數 1~5：1=最緊急(紅)、2=高(橙)、3=中(黃)、4=低(藍)、5=備忘(灰)。\n"
    "3. targets 是裝置 ID 陣列；若不確定，留空 [] 表示廣播給全部前線。\n"
    "4. 若沒有需要建議的指令，**不要**輸出 JSON block，只回覆文字即可。\n"
    "5. 一次最多輸出 3 條最關鍵的提案；不要重複、不要灌水。\n"
    "6. JSON block 必須是合法 JSON，不得包含註解；fence 必須是 ```json。"
)


def _build_tools_system_prompt(base_system: str, status_text: str,
                               patient_detail: str, voice_history: str = "") -> str:
    """建構帶 tool schema 的 system prompt（重用 /chat 的狀態注入規則）。"""
    return (
        f"{base_system}\n\n"
        f"=== 當前現場即時狀態 (供你決策參考,使用者未必會重複提及) ===\n"
        f"{status_text}\n\n"
        f"=== 活動傷患詳細資料 ===\n"
        f"{patient_detail}\n"
        + (f"\n{voice_history}\n" if voice_history else "")
        + f"=== 狀態結束 ===\n"
        f"當使用者詢問傷患、優先級、資源或人員時,請直接引用上述資料作答,不要回答「沒有資訊」。"
        + _AI_TOOLS_INSTRUCTION
    )


# 抓取 fenced JSON block（```json ... ``` 或 ``` ... ```）
_FENCED_JSON_RE = re.compile(r"```(?:json)?\s*(\{.*?\})\s*```", re.DOTALL | re.IGNORECASE)


def _split_reply_and_proposals(raw: str, msg_id_prefix: str = "AIP") -> tuple[str, list[dict]]:
    """從 LLM 原始輸出抽出 proposals 與乾淨的 reply 文字。

    Returns:
        (clean_reply_text, proposals_list)
        proposals_list 中每筆已補上 id / timestamp 並過濾非法 type。
    """
    text = (raw or "").strip()
    if not text:
        return "", []

    proposals: list[dict] = []
    # 1) 先試 fenced JSON
    match = _FENCED_JSON_RE.search(text)
    json_block_str = ""
    if match:
        json_block_str = match.group(0)
        try:
            payload = json.loads(match.group(1))
            if isinstance(payload, dict) and isinstance(payload.get("proposals"), list):
                proposals = payload["proposals"]
            elif isinstance(payload, list):
                proposals = payload
        except (json.JSONDecodeError, TypeError):
            proposals = []

    # 2) Fallback: 若無 fence，但訊息看似純 JSON
    if not proposals and text.startswith("{"):
        try:
            payload = json.loads(text)
            if isinstance(payload, dict) and isinstance(payload.get("proposals"), list):
                proposals = payload["proposals"]
                json_block_str = text
        except (json.JSONDecodeError, TypeError):
            pass

    # 3) 從原文移除 JSON 區塊作為乾淨 reply
    clean_reply = text
    if json_block_str:
        clean_reply = clean_reply.replace(json_block_str, "").strip()
    # 收斂空白
    clean_reply = re.sub(r"\n{3,}", "\n\n", clean_reply).strip()

    # 4) 標準化 / 過濾每筆 proposal
    now_iso = datetime.now(TZ_TW).isoformat()
    hms = datetime.now(TZ_TW).strftime("%H%M%S")
    cleaned: list[dict] = []
    for idx, p in enumerate(proposals):
        if not isinstance(p, dict):
            continue
        ptype = str(p.get("type", "")).strip().lower()
        if ptype not in _AI_PROPOSAL_TYPES:
            continue
        title = str(p.get("title", "")).strip()
        if not title:
            continue
        try:
            priority = int(p.get("priority", 3))
        except (TypeError, ValueError):
            priority = 3
        priority = max(1, min(5, priority))
        targets_raw = p.get("targets") or []
        if not isinstance(targets_raw, list):
            targets_raw = []
        targets = [str(x).strip() for x in targets_raw if str(x).strip()]
        rationale = str(p.get("rationale", "")).strip()
        meta = _AI_PROPOSAL_META.get(ptype, {"mode": "manual", "countdown_sec": 0, "require_human_double_confirm": False})
        cleaned.append({
            "id": f"{msg_id_prefix}-{hms}-{idx}",
            "type": ptype,
            "priority": priority,
            "title": title[:60],
            "detail": str(p.get("detail", "")).strip(),
            "targets": targets,
            "rationale": rationale,
            "timestamp": now_iso,
            "mode": meta["mode"],
            "countdown_sec": meta["countdown_sec"],
            "require_human_double_confirm": meta["require_human_double_confirm"],
        })
        if len(cleaned) >= 3:
            break

    return clean_reply, cleaned


@app.post("/chat/with_tools")
async def hq_chat_with_tools(req: ChatRequest):
    """HQ AI 副駕駛：在 /chat 之上額外允許 AI 產出可審批的結構化指令提案。

    與 /chat 的差異：
    - System prompt 注入 6 大指令的 tool schema 與 fenced JSON 輸出規則
    - 從回覆中抽出 proposals[]，回傳給前端 HQAIChatView 顯示提案卡
    - 不直接執行任何指令；前端按下「執行」後才呼 HQCommandServer.sendCommand
    - 無 proposal 時行為等同 /chat（向後相容）
    """
    user_msg = (req.message or "").strip()
    if not user_msg:
        return api_ok({"reply": "", "model": _get_active_model(), "proposals": []})

    runtime_model = _get_runtime_model()
    active_model = _get_active_model()
    model_options = _get_model_options()

    # 沿用 /chat 的現場狀態注入
    try:
        status_text = _format_status_for_llm()
    except Exception as e:
        logger.warning(f"[CHAT/TOOLS] 取得系統狀態失敗: {e}")
        status_text = ""
    try:
        active_patients = linkguard_db.get_active_patients() or []
        ranked = rank_patients(active_patients) if active_patients else []
        patient_detail = format_for_llm(ranked) if ranked else "(目前無活動傷患)"
    except Exception as e:
        logger.warning(f"[CHAT/TOOLS] 取得傷患清單失敗: {e}")
        patient_detail = "(無法讀取傷患資料)"
    voice_history = _format_recent_voice_for_llm(limit=10)

    base_system = req.system_prompt or (
        "你是 LinkGuard 災害救援指揮 AI 副駕駛,負責協助 HQ 指揮官思考、規劃與決策,"
        "並在合適時機提出可審批的結構化指令建議。\n"
        "回覆風格:精準、專業、條列、避免空泛口號;若資訊不足請主動詢問。\n"
        "回覆語言:正體中文。\n"
        "格式規則(嚴格遵守):\n"
        "1. 嚴禁使用任何 emoji 或表情符號 (例如 ✅ ⚠️ 🔥 📌 等),全部以純文字表達。\n"
        "2. 嚴禁使用 Markdown 標題語法,即不得出現 # ## ### #### 等井字號開頭的行。\n"
        "3. 需要強調的標題或重點,改用 **粗體** (兩個星號) 表示,例如 **行動方案**。\n"
        "4. 條列使用 - 或 1. 2. 3.,不要使用井字號。"
    )
    system_prompt = _build_tools_system_prompt(base_system, status_text, patient_detail, voice_history)

    messages: list[dict] = [{"role": "system", "content": system_prompt}]
    for m in (req.history or [])[-12:]:
        if m.role in ("user", "assistant") and (m.content or "").strip():
            messages.append({"role": m.role, "content": m.content})
    messages.append({"role": "user", "content": user_msg})

    client = ollama.Client(host=OLLAMA_HOST)
    t0 = time.monotonic()
    chat_kwargs = dict(
        model=runtime_model,
        messages=messages,
        options={**model_options, "temperature": 0.4, "num_predict": 1024},
    )

    def _call_ollama():
        try:
            return client.chat(**chat_kwargs, think=False)
        except TypeError:
            return client.chat(**chat_kwargs)

    try:
        response = await asyncio.to_thread(_call_ollama)
    except ConnectionError as e:
        logger.warning(f"[CHAT/TOOLS] Ollama 連線失敗: {e}")
        api_error(
            "ollama_unavailable",
            f"AI 模型服務 (Ollama @ {OLLAMA_HOST}) 無法連線，請確認 Ollama 已啟動。",
            status_code=503,
        )
    except Exception as e:
        logger.exception(f"[CHAT/TOOLS] AI 對話失敗: {e}")
        api_error("chat_failed", f"AI 對話失敗: {e}", status_code=500)

    raw_reply = (response.message.content or "").strip()
    # 先抽 proposals（在 sanitize 之前，避免 JSON 內容被誤剝）
    clean_reply, proposals = _split_reply_and_proposals(raw_reply)

    # === 雙 AI 共識上報：偵測 ESCALATE 訊號並記錄 ===
    session_id = (req.session_id or "default").strip() or "default"
    escalate_detected = _detect_escalation_signal(clean_reply)
    side = _classify_session_side(session_id)
    escalate_info = None
    if escalate_detected and side in ("hq", "field"):
        try:
            fired = await record_escalation_signal(session_id, clean_reply)
            escalate_info = {
                "detected": True,
                "side": side,
                "consensus_fired": bool(fired and fired.get("fired")),
            }
        except Exception as e:
            logger.warning(f"[CONSENSUS] 記錄訊號失敗: {e}")
            escalate_info = {"detected": True, "side": side, "consensus_fired": False}
    elif escalate_detected:
        escalate_info = {"detected": True, "side": side, "consensus_fired": False}

    clean_reply = _strip_escalation_marker(clean_reply)
    # 再用 /chat 的 sanitize 清掉 markdown 標題與 emoji
    final_reply = _sanitize_chat_reply(clean_reply)

    # === Server session 歷史寫回 ===
    if req.use_server_session and session_id != "default":
        _append_session_message(session_id, "user", user_msg)
        if final_reply:
            _append_session_message(session_id, "assistant", final_reply)

    elapsed_ms = int((time.monotonic() - t0) * 1000)

    if proposals:
        try:
            linkguard_db.log_event(
                "ai_proposal", "qwen-server",
                f"AI 提出 {len(proposals)} 條指令提案 (待審批)",
            )
        except Exception:
            pass

    return api_ok({
        "reply": final_reply,
        "model": active_model,
        "runtime_model": runtime_model,
        "elapsed_ms": elapsed_ms,
        "proposals": proposals,
        "session_id": session_id,
        **({"escalation": escalate_info} if escalate_info else {}),
    })


# ====================================================================
# AI tier health / models / command lifecycle  (Plan v2 Phase A1.2 + A3)
# ====================================================================

@app.get("/ai/health")
async def ai_health():
    """檢查每個 tier 對應的 ollama host 是否可達。"""
    tiers = (DUAL_CFG.get("tiers") or {})
    out: dict = {"tiers": {}}
    for tier_name in ("field", "hq_local", "hq_main"):
        cfg = tiers.get(tier_name) or {}
        host = cfg.get("host") or OLLAMA_HOST
        model = cfg.get("name") or ""
        ok = False
        latency_ms = None
        err = None
        t0 = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=3) as client:
                r = await client.get(f"{host.rstrip('/')}/api/tags")
                ok = (r.status_code == 200)
            latency_ms = int((time.monotonic() - t0) * 1000)
        except Exception as e:
            err = str(e)
        out["tiers"][tier_name] = {
            "host": host, "model": model, "ok": ok,
            "latency_ms": latency_ms, "error": err,
            "thinking_mode": bool(cfg.get("thinking_mode")),
            "supports_audio": bool(cfg.get("supports_audio")),
        }
    out["routing"] = DUAL_CFG.get("tier_routing") or {}
    out["local_role"] = DUAL_CFG.get("local_role")
    return api_ok(out)


@app.get("/ai/models")
async def ai_models():
    """回傳每個 tier 的目前模型與 fallback 鏈。"""
    tiers = (DUAL_CFG.get("tiers") or {})
    out = {}
    for tier_name, cfg in tiers.items():
        out[tier_name] = {
            "name": cfg.get("name"),
            "host": cfg.get("host"),
            "context": cfg.get("context"),
            "fallback": cfg.get("fallback") or [],
            "use_for": cfg.get("use_for") or [],
            "thinking_mode": bool(cfg.get("thinking_mode")),
            "supports_audio": bool(cfg.get("supports_audio")),
        }
    return api_ok({"tiers": out})


# In-memory pending AI commands (auto-dispatch with countdown)
# Key: command id  Value: {proposal, scheduled_at, dispatch_at, status, task}
_AI_PENDING_CMDS: dict[str, dict] = {}
_AI_PENDING_LOCK = asyncio.Lock()


def _normalize_proposal_payload(raw: dict) -> dict:
    """補齊缺漏欄位 + 注入 mode/countdown 元資料。"""
    ptype = str(raw.get("type", "")).strip().lower()
    if ptype not in _AI_PROPOSAL_TYPES:
        raise ValueError(f"unsupported proposal type: {ptype}")
    meta = _AI_PROPOSAL_META[ptype]
    try:
        priority = int(raw.get("priority", 3))
    except (TypeError, ValueError):
        priority = 3
    priority = max(1, min(5, priority))
    targets = raw.get("targets") or []
    if not isinstance(targets, list):
        targets = []
    cmd_id = str(raw.get("id") or f"AIC-{datetime.now(TZ_TW).strftime('%H%M%S')}-{len(_AI_PENDING_CMDS)}")
    return {
        "id": cmd_id,
        "type": ptype,
        "priority": priority,
        "title": str(raw.get("title", "")).strip()[:60],
        "detail": str(raw.get("detail", "")).strip(),
        "targets": [str(x).strip() for x in targets if str(x).strip()],
        "rationale": str(raw.get("rationale", "")).strip(),
        "timestamp": datetime.now(TZ_TW).isoformat(),
        "mode": meta["mode"],
        "countdown_sec": int(raw.get("countdown_sec", meta["countdown_sec"])),
        "require_human_double_confirm": meta["require_human_double_confirm"],
    }


class AIProposalRequest(BaseModel):
    proposal: dict
    session_id: Optional[str] = None


@app.post("/ai/command/propose")
async def ai_command_propose(req: AIProposalRequest):
    """登錄一個 AI 提案到 pending 清單（不自動派發）。
    回傳含 mode/countdown 的標準化提案；前端依 mode 決定 UI。"""
    try:
        norm = _normalize_proposal_payload(req.proposal or {})
    except ValueError as e:
        api_error("invalid_proposal", str(e), status_code=400)
    async with _AI_PENDING_LOCK:
        _AI_PENDING_CMDS[norm["id"]] = {
            "proposal": norm,
            "session_id": req.session_id,
            "status": "pending",
            "scheduled_at": None,
            "dispatch_at": None,
            "task": None,
        }
    try:
        linkguard_db.log_event("ai_proposal", "qwen-server",
                               f"AI 提案登錄 {norm['type']} ({norm['mode']}) - {norm['title']}")
    except Exception:
        pass
    return api_ok({"command": norm})


class AIAutoDispatchRequest(BaseModel):
    command_id: str


async def _dispatch_command_now(cmd_id: str) -> dict:
    """實際派發：寫入事件 + 廣播給前線（簡化：留給 HQ App 透過 TCP 派發）。"""
    info = _AI_PENDING_CMDS.get(cmd_id)
    if not info:
        return {"ok": False, "error": "command_not_found"}
    if info["status"] in ("dispatched", "cancelled"):
        return {"ok": False, "error": f"already_{info['status']}"}
    proposal = info["proposal"]
    info["status"] = "dispatched"
    info["dispatch_at"] = datetime.now(TZ_TW).isoformat()
    try:
        linkguard_db.log_event("ai_command_dispatched", "qwen-server",
                               f"自動派發 {proposal['type']} - {proposal['title']}")
    except Exception:
        pass
    return {"ok": True, "command": proposal, "dispatched_at": info["dispatch_at"]}


@app.post("/ai/command/auto_dispatch")
async def ai_command_auto_dispatch(req: AIAutoDispatchRequest):
    """為一個已登錄的 AUTO 提案啟動倒數派發。
    countdown_sec 期間可被 /ai/command/cancel 取消。"""
    info = _AI_PENDING_CMDS.get(req.command_id)
    if not info:
        api_error("not_found", "command not found", status_code=404)
    proposal = info["proposal"]
    if proposal["mode"] != "auto":
        api_error("not_auto", "only auto-mode proposals can be auto-dispatched", status_code=400)
    if proposal.get("require_human_double_confirm"):
        api_error("requires_human", "this command requires human double-confirm", status_code=400)
    if info["status"] != "pending":
        api_error("invalid_state", f"command is {info['status']}", status_code=409)

    countdown = max(0, int(proposal.get("countdown_sec", 0)))
    info["scheduled_at"] = datetime.now(TZ_TW).isoformat()
    info["status"] = "scheduled"

    async def _runner():
        try:
            if countdown > 0:
                await asyncio.sleep(countdown)
            cur = _AI_PENDING_CMDS.get(req.command_id)
            if cur and cur["status"] == "scheduled":
                await _dispatch_command_now(req.command_id)
        except asyncio.CancelledError:
            pass

    info["task"] = asyncio.create_task(_runner())
    return api_ok({
        "command_id": req.command_id,
        "command_status": "scheduled",
        "countdown_sec": countdown,
        "scheduled_at": info["scheduled_at"],
    })


@app.post("/ai/command/cancel/{cmd_id}")
async def ai_command_cancel(cmd_id: str):
    info = _AI_PENDING_CMDS.get(cmd_id)
    if not info:
        api_error("not_found", "command not found", status_code=404)
    if info["status"] == "dispatched":
        api_error("already_dispatched", "cannot cancel a dispatched command", status_code=409)
    if info["status"] == "cancelled":
        return api_ok({"command_id": cmd_id, "command_status": "cancelled"})
    task = info.get("task")
    if task and not task.done():
        task.cancel()
    info["status"] = "cancelled"
    info["task"] = None
    try:
        linkguard_db.log_event("ai_command_cancelled", "qwen-server",
                               f"取消 AI 指令 {info['proposal']['type']} - {info['proposal']['title']}")
    except Exception:
        pass
    return api_ok({"command_id": cmd_id, "command_status": "cancelled"})


@app.get("/ai/command/list")
async def ai_command_list():
    out = []
    for cid, info in list(_AI_PENDING_CMDS.items()):
        out.append({
            "id": cid,
            "command_status": info["status"],
            "scheduled_at": info["scheduled_at"],
            "dispatch_at": info["dispatch_at"],
            "proposal": info["proposal"],
        })
    return api_ok({"commands": out})


# ====================================================================
# Field report formalization  (Plan v2 Phase A5)
# 將前線口語化的事件記錄交由 field tier (e2b) 改寫成正式戰情報告
# ====================================================================

class ReportFormalizeRequest(BaseModel):
    raw_text: str
    reporter: Optional[str] = None
    session_id: str = "default"
    incident_type: Optional[str] = None  # patient / resource / hazard / general


@app.post("/report/formalize")
async def report_formalize(req: ReportFormalizeRequest):
    """以 field tier (gemma4:e2b) 將口語報告改寫為正式格式。"""
    raw = (req.raw_text or "").strip()
    if not raw:
        api_error("empty_text", "raw_text 不可為空", status_code=400)

    tier = "field"
    model = _runtime_model_for_tier(tier)
    host = _host_for_tier(tier)

    sys_prompt = (
        "你是 LinkGuard 戰情報告整理員。將前線口語化記錄重寫為**正式戰情報告**。\n"
        "規則:\n"
        "1. 不得加入未提及的事實。若資訊不足以推論，明確標註「待補」。\n"
        "2. 條列式輸出，分為「事件」「時間」「地點」「人員/傷患」「狀態」「建議行動」。\n"
        "3. 嚴禁使用 emoji 與 Markdown 標題語法 (#)，重點以 **粗體** 表示。\n"
        "4. 若可辨識出緊急程度，請於最前列標註：[緊急程度: 紅/黃/綠]。\n"
        f"5. 報告類型: {req.incident_type or '一般'}\n"
        f"6. 報告人: {req.reporter or '未指定'}"
    )
    messages = [
        {"role": "system", "content": sys_prompt},
        {"role": "user", "content": raw},
    ]
    t0 = time.monotonic()
    try:
        client = ollama.Client(host=host)
        def _call():
            try:
                return client.chat(model=model, messages=messages,
                                   options={"temperature": 0.2, "num_predict": 800,
                                            "num_ctx": _tier_context(tier)},
                                   think=False)
            except TypeError:
                return client.chat(model=model, messages=messages,
                                   options={"temperature": 0.2, "num_predict": 800,
                                            "num_ctx": _tier_context(tier)})
        resp = await asyncio.to_thread(_call)
    except ConnectionError as e:
        api_error("ollama_unavailable", f"AI 模型服務無法連線: {e}", status_code=503)
    except Exception as e:
        logger.exception(f"[REPORT/FORMALIZE] 失敗: {e}")
        api_error("formalize_failed", f"格式化失敗: {e}", status_code=500)

    formal = _sanitize_chat_reply((resp.message.content or "").strip())
    elapsed = int((time.monotonic() - t0) * 1000)
    try:
        linkguard_db.log_event("report_formalized", req.reporter or "field",
                               f"{(req.incident_type or 'general')}: {raw[:80]}")
    except Exception:
        pass
    return api_ok({
        "raw": raw,
        "formal": formal,
        "model": model,
        "tier": tier,
        "elapsed_ms": elapsed,
        "reporter": req.reporter,
        "incident_type": req.incident_type,
    })


@app.get("/history")
def get_history():
    rows = linkguard_db.get_recent_decisions(10)
    return api_ok({"history": rows})


@app.get("/decisions")
def list_decisions(limit: int = 50):
    """Return AI decision history for LinkGuardHQ Decision History."""
    try:
        limit = max(1, min(int(limit), 500))
    except (TypeError, ValueError):
        limit = 50
    rows = linkguard_db.get_recent_decisions(limit)
    return api_ok({"decisions": rows, "total": len(rows)})


@app.delete("/history")
def clear_history():
    conn = linkguard_db._get_conn()
    conn.execute("DELETE FROM decisions")
    conn.commit()
    conn.close()
    return api_ok({"message": t("msg.history_cleared")})


# ============================================================
# 人員暱稱管理
# ============================================================
class NicknameRequest(BaseModel):
    device_id: str
    nickname: str
    role: Optional[str] = ""


@app.get("/personnel/nicknames")
def list_nicknames():
    """取得所有人員暱稱對照表。"""
    return api_ok({"nicknames": linkguard_db.get_all_nicknames()})


@app.get("/personnel/nickname/{device_id}")
def get_nickname(device_id: str):
    rec = linkguard_db.get_nickname(device_id)
    if not rec:
        return api_ok({"device_id": device_id, "nickname": None})
    return api_ok(rec)


@app.post("/personnel/nickname")
def upsert_nickname(req: NicknameRequest):
    ok = linkguard_db.set_nickname(req.device_id.strip(), req.nickname.strip(), (req.role or "").strip())
    if not ok:
        api_error("nickname_invalid", "device_id 與 nickname 皆必須提供", status_code=400)
    return api_ok(linkguard_db.get_nickname(req.device_id.strip()))


@app.delete("/personnel/nickname/{device_id}")
def remove_nickname(device_id: str):
    linkguard_db.delete_nickname(device_id)
    return api_ok({"deleted": device_id})


# === 翻譯功能 ===

SUPPORTED_LANGUAGES = {
    "zh-TW": "繁體中文", "en": "英文", "ja": "日文", "ko": "韓文",
    "vi": "越南文", "th": "泰文", "id": "印尼文", "ms": "馬來文",
}


class TranslateRequest(BaseModel):
    text: str
    source_lang: str = "auto"
    target_lang: str = "en"
    context: str = "medical"


TRANSLATION_MEMORY = {
    # iOS/Android 快速醫療用語：優先使用穩定翻譯，避免模型漂移
    ("你有哪裡不舒服？", "en"): "Where do you feel discomfort?",
    ("你能呼吸嗎？", "en"): "Can you breathe?",
    ("我要幫助你", "en"): "I am here to help you.",
    ("請不要移動", "en"): "Please do not move.",
    ("救護車來了", "en"): "The ambulance is here.",
    ("你叫什麼名字？", "en"): "What is your name?",
    ("你有沒有過敏？", "en"): "Do you have any allergies?",
    ("請張開嘴巴", "en"): "Please open your mouth.",
}


def _detect_lang_simple(text: str) -> str:
    t = text.strip()
    if not t:
        return "auto"

    if re.search(r"[\u3040-\u30ff\u31f0-\u31ff]", t):
        return "ja"
    if re.search(r"[\uac00-\ud7af]", t):
        return "ko"
    if re.search(r"[\u4e00-\u9fff]", t):
        return "zh-TW"
    if re.search(r"[A-Za-z]", t):
        return "en"
    return "auto"


def _clean_translation_output(raw: str) -> str:
    text = (raw or "").strip()
    if not text:
        return ""

    # 處理模型常見的 markdown code fence
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z0-9_-]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text).strip()

    # 優先嘗試 JSON 格式
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict) and isinstance(parsed.get("translated"), str):
            return parsed["translated"].strip()
    except Exception:
        pass

    # 去除常見前綴
    text = re.sub(r"^(翻譯|譯文|Translation)\s*[:：]\s*", "", text, flags=re.IGNORECASE)

    # 多行譯文需保留（以前 bug：只取首行導致長句被截斷）
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return ""
    # 若首行看起來是 label（例如 "Translation:"）且後續有譯文，跳過首行
    if len(lines) > 1 and re.match(r"^(翻譯|譯文|translation)\s*[:：]?\s*$", lines[0], re.IGNORECASE):
        lines = lines[1:]
    return "\n".join(lines)


@app.post("/translate")
def translate(req: TranslateRequest):
    text = req.text.strip()
    if not text:
        return api_error(t("err.text_empty"))

    target_name = SUPPORTED_LANGUAGES.get(req.target_lang, req.target_lang)
    source_name = SUPPORTED_LANGUAGES.get(req.source_lang, t("misc.auto_detect"))

    # 高頻急救短句優先採用記憶翻譯，確保一致且立即可用
    memory_hit = TRANSLATION_MEMORY.get((text, req.target_lang))
    if memory_hit:
        detected = req.source_lang if req.source_lang != "auto" else _detect_lang_simple(text)
        return api_ok({
            "original": text,
            "translated": memory_hit,
            "detected_lang": detected,
            "target_lang": req.target_lang,
            "model": "translation-memory",
            "context": req.context,
        })

    # 根據 context 動態調整 prompt
    context_guidance = ""
    if req.context == "medical":
        context_guidance = (
            "- 醫用術語必須準確（例：心率→heart rate、呼吸困難→respiratory distress）\n"
            "- 簡化複雜的醫學概念為非專業人士能理解的用語\n"
            "- 保留數字和生命徵象（血壓、脈搏、呼吸）\n"
        )
    elif req.context == "operational":
        context_guidance = (
            "- 保持指揮術語清晰準確（例：請求支援→request backup、方位→compass bearing）\n"
            "- 避免含糊其辭，必須有行動意圖\n"
        )
    elif req.context == "logistics":
        context_guidance = (
            "- 物資、設備名詞要準確對應（例：擔架→stretcher、繃帶→bandage）\n"
            "- 數量和單位必須正確轉換\n"
        )

    system_prompt = (
        "你是 LinkGuard 災害救援翻譯引擎（GEMMA4 26B）。\n"
        f"任務：把輸入文字從 {source_name} 翻成 {target_name}。\n"
        "只允許輸出 JSON，格式必須是：{\"translated\":\"...\"}。\n"
        "禁止輸出任何額外說明、前綴、Markdown、反引號。\n"
        "需保留人名、代號、座標、數字、單位與醫療數值。\n"
        "若原文已是目標語言或不需翻譯，translated 可回傳原文。\n"
        "翻譯優先：準確 > 簡潔 > 自然。\n"
        f"領域補充：\n{context_guidance}"
    )

    user_prompt = (
        f"source_lang={req.source_lang}\n"
        f"target_lang={req.target_lang}\n"
        f"context={req.context}\n"
        "text:\n"
        f"{text}"
    )

    active_model = _get_active_model()
    runtime_model = _get_runtime_model()
    model_options = _get_model_options()
    client = ollama.Client(host=OLLAMA_HOST)
    chat_kwargs = dict(
        model=runtime_model,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        options={**model_options, "temperature": 0.0, "num_predict": 256},
    )
    try:
        response = client.chat(**chat_kwargs, think=False)
    except TypeError:
        # 舊版 ollama SDK 不支援 think 參數
        response = client.chat(**chat_kwargs)
    raw_output = (response.message.content or "").strip()
    translated = _clean_translation_output(raw_output)
    if not translated:
        translated = text

    # 簡單語言偵測：若來源是 auto，依字元特徵估測
    detected = req.source_lang if req.source_lang != "auto" else _detect_lang_simple(text)

    print(f"[TRANSLATE] {req.context}/{req.source_lang}→{req.target_lang}: {text[:60]}... → {translated[:60]}...")

    return api_ok({
        "original": text,
        "translated": translated,
        "detected_lang": detected,
        "target_lang": req.target_lang,
        "model": active_model,
        "context": req.context,
    })


# === 檢傷評分端點 ===

class ScoreRequest(BaseModel):
    patient: dict


@app.post("/triage/score")
def triage_score_single(req: ScoreRequest):
    """對單一傷患計算完整評分。"""
    result = calculate_total_score(req.patient)
    return api_ok({**req.patient, **result})


class RankRequest(BaseModel):
    patients: list


@app.post("/triage/rank")
def triage_rank(req: RankRequest):
    """對多位傷患評分並排序。"""
    ranked = rank_patients(req.patients)
    return api_ok({"queue": ranked, "count": len(ranked)})


@app.get("/triage/queue")
def triage_queue():
    """從 DB 取得活動傷患的排序佇列。"""
    patients = linkguard_db.get_active_patients()
    return api_ok({"queue": patients, "count": len(patients)})


@app.post("/triage/recalc")
def triage_recalc():
    """手動觸發全佇列重新計算。"""
    _recalc_all_patients()
    patients = linkguard_db.get_active_patients()
    return api_ok({"message": t("msg.recalc_done"), "queue": patients, "count": len(patients)})


class DeactivateRequest(BaseModel):
    patient_id: str
    status: str = "rescued"


@app.post("/triage/deactivate")
def triage_deactivate(req: DeactivateRequest):
    """將傷患移出活動佇列（rescued / deceased_confirmed）。"""
    if req.status not in ("rescued", "deceased_confirmed"):
        api_error("INVALID_STATUS", t("err.invalid_status"))
    linkguard_db.deactivate_patient(req.patient_id, req.status)
    return api_ok({"message": t("msg.patient_deactivated", id=req.patient_id, status=req.status)})


@app.get("/health")
def health():
    ollama_ok = False
    try:
        client = ollama.Client(host=OLLAMA_HOST)
        client.list()
        ollama_ok = True
    except Exception:
        pass
    return health_check_response(
        "qwen-server",
        extras={
            "ollama_connected": ollama_ok,
            "active_model": MODEL_NAME,
        },
    )


# === 系統總覽端點 ===

def _format_recent_voice_for_llm(limit: int = 8) -> str:
    """取最近 N 筆語音轉錄,讓模型掌握現場語音回報脈絡。
    來源 source 區分:realtime_stt / audio_report / speech_report 等。"""
    try:
        rows = linkguard_db.get_transcriptions(limit=limit)
    except Exception:
        return ""
    if not rows:
        return ""
    # 反序成時間遞增,並用暱稱 (若有) 顯示
    try:
        nicks = {n["device_id"]: n.get("nickname") for n in linkguard_db.get_all_nicknames()}
    except Exception:
        nicks = {}
    lines = ["=== 最近語音回報 (時間遞增) ==="]
    for r in reversed(rows):
        ts = (r.get("timestamp") or "").replace("T", " ")[:19]
        sid = r.get("sender_id") or "?"
        nick = nicks.get(sid)
        who = f"{nick}({sid})" if nick else sid
        src = r.get("source") or "?"
        text = (r.get("text") or "").strip()
        if not text:
            continue
        lines.append(f"  [{ts}] {who} ({src}): {text}")
    if len(lines) == 1:
        return ""
    lines.append("=== 語音回報結束 ===")
    return "\n".join(lines)


def _build_system_status() -> dict:
    """聚合系統各模組狀態，供 /status 端點與 LLM prompt 使用。"""
    patient_stats = linkguard_db.get_patient_stats()
    resource_summary = linkguard_db.get_resource_summary()
    nodes = linkguard_db.get_latest_nodes()
    recent = linkguard_db.get_recent_decisions(3)
    active_patients = linkguard_db.get_active_patients()

    return {
        "model": {
            "active": MODEL_NAME,
            "description": _model_desc(MODEL_NAME),
        },
        "patients": patient_stats,
        "active_queue": [
            {
                "patient_id": p.get("patient_id"),
                "priority": p.get("priority"),
                "total_score": p.get("total_score"),
                "location_desc": p.get("location_desc", ""),
            }
            for p in active_patients[:10]
        ],
        "resources": resource_summary,
        "nodes": [
            {
                "node_id": n.get("node_id"),
                "battery": n.get("battery"),
                "rssi": n.get("rssi"),
                "online": bool(n.get("online")),
                "lat": n.get("lat"),
                "lon": n.get("lon"),
            }
            for n in nodes
        ],
        "recent_decisions": len(recent),
        "auto_wake": {
            "enabled": _autowake_enabled,
            "interval_sec": AUTOWAKE_INTERVAL,
            "last_trigger": _last_autowake_iso,
        },
        "dual_model": {
            "enabled": DUAL_CFG.get("enabled", False),
            "local_role": DUAL_CFG.get("local_role"),
            "peer_alive": _peer_alive,
        },
    }


def _format_status_for_llm() -> str:
    """將系統狀態格式化為 LLM 可閱讀的文字區塊。"""
    s = _build_system_status()
    lines = [t("status.header")]

    # 傷患統計
    ps = s["patients"]
    lines.append(
        t("status.patient_total",
          total=ps['total'], red=ps['red'], yellow=ps['yellow'],
          green=ps['green'], black=ps['black'])
    )

    # 排序佇列前 5
    if s["active_queue"]:
        lines.append(t("status.priority_queue"))
        for i, p in enumerate(s["active_queue"][:5], 1):
            lines.append(
                f"  {i}. {p['patient_id']} [{p['priority']}] "
                f"score={p['total_score']:.1f} {p['location_desc']}"
            )

    # 資源
    if s["resources"]:
        parts = []
        for rtype, info in s["resources"].items():
            rkey = f"res.{rtype}"
            name = t(rkey) if rkey in I18N_STRINGS else rtype
            parts.append(f"{name} {info['available']}/{info['total']}")
        lines.append(f"{t('status.resources')}{' | '.join(parts)}")

    # 節點
    if s["nodes"]:
        lines.append(t("status.lora_nodes"))
        for n in s["nodes"]:
            status = t("status.online") if n["online"] else t("status.offline")
            lines.append(
                t("status.node_fmt",
                  id=n['node_id'], battery=n['battery'],
                  rssi=n['rssi'], status=status)
            )
    else:
        lines.append(t("status.no_nodes"))

    return "\n".join(lines)


@app.get("/status")
def system_status():
    """系統狀態總覽：傷患、資源、節點、模型、auto-wake 等。"""
    status = _build_system_status()
    status["status_text"] = _format_status_for_llm()
    return api_ok(status)


# === 指令發布端點 ===

# 指令佇列：LLM 生成的待執行命令
_command_queue: list[dict] = []

COMMAND_TYPES = {
    "dispatch": "cmd.dispatch",
    "alert": "cmd.alert",
    "resource": "cmd.resource",
    "personnel": "cmd.personnel",
    "evacuate": "cmd.evacuate",
    "medical": "cmd.medical",
    "status_request": "cmd.status_request",
}


class CommandRequest(BaseModel):
    situation: str = ""
    command_type: str = ""
    priority: int = 2
    title: str = ""
    detail: str = ""
    targets: list[str] | None = None
    auto_generate: bool = False


@app.post("/command")
def issue_command(req: CommandRequest):
    """
    發布指令。兩種模式：
    1. auto_generate=True: 傳入 situation，由 LLM 自動生成指令
    2. auto_generate=False: 直接傳入 command_type/title/detail
    """
    if req.auto_generate:
        # 由 LLM 根據情境自動生成指令
        status_text = _format_status_for_llm()
        system_prompt = (
            "你是 LinkGuard 災害救援指揮 AI（GEMMA4 26B）。\n"
            "根據當前系統狀態與情境，生成最小且可執行的指令集合。\n"
            "輸出 JSON 格式：\n"
            '{"commands": [{"type":"dispatch|alert|resource|personnel|evacuate|medical",'
            '"priority":1-5, "title":"指令標題", "detail":"具體內容", "targets":["裝置ID"]}]}\n'
            "type 說明：dispatch=調派, alert=警報, resource=資源調配, "
            "personnel=人員指派, evacuate=撤離, medical=醫療指示\n"
            "priority: 1=最高 5=最低\n"
            "只輸出 JSON，不要任何說明。\n\n"
            f"{status_text}"
        )
        user_prompt = f"情境：{req.situation}\n請生成指揮指令。"

        active_model = _get_active_model()
        runtime_model = _get_runtime_model()
        model_options = _get_model_options()
        client = ollama.Client(host=OLLAMA_HOST)
        chat_kwargs = dict(
            model=runtime_model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            options={**model_options, "temperature": 0.15, "num_predict": 512},
        )
        try:
            response = client.chat(**chat_kwargs, think=False)
        except TypeError:
            response = client.chat(**chat_kwargs)
        raw = (response.message.content or "").strip()

        # 解析 JSON
        commands = _parse_command_json(raw)
        if not commands:
            return api_ok({
                "commands": [],
                "raw": raw,
                "message": t("msg.llm_no_command"),
                "model": active_model,
            })

        # 加入佇列
        now = datetime.now(TZ_TW).isoformat()
        for cmd in commands:
            cmd["id"] = f"CMD-{datetime.now(TZ_TW).strftime('%H%M%S')}-{len(_command_queue)}"
            cmd["timestamp"] = now
            cmd["source"] = "ai"
            cmd["status"] = "pending"
            _command_queue.append(cmd)

        linkguard_db.log_event(
            "ai_command", "qwen-server",
            f"AI 生成 {len(commands)} 條指令: {req.situation[:60]}",
        )

        return api_ok({
            "commands": commands,
            "model": active_model,
            "queue_size": len(_command_queue),
        })
    else:
        # 手動指令
        if not req.title:
            api_error("MISSING_TITLE", t("err.missing_title"))
        cmd_type = req.command_type or "dispatch"
        if cmd_type not in COMMAND_TYPES:
            api_error("INVALID_TYPE", t("err.invalid_type", types=list(COMMAND_TYPES.keys())))

        now = datetime.now(TZ_TW).isoformat()
        cmd = {
            "id": f"CMD-{datetime.now(TZ_TW).strftime('%H%M%S')}-{len(_command_queue)}",
            "type": cmd_type,
            "priority": req.priority,
            "title": req.title,
            "detail": req.detail or "",
            "targets": req.targets,
            "timestamp": now,
            "source": "manual",
            "status": "pending",
        }
        _command_queue.append(cmd)

        linkguard_db.log_event(
            "manual_command", "qwen-server",
            f"Manual command: [{t(COMMAND_TYPES[cmd_type])}] {req.title}",
        )

        return api_ok({"command": cmd, "queue_size": len(_command_queue)})


@app.get("/command/queue")
def get_command_queue():
    """取得指令佇列（含已執行與待執行）。"""
    return api_ok({
        "commands": _command_queue[-50:],
        "total": len(_command_queue),
    })


@app.post("/command/ack")
def ack_command(req: dict):
    """前線裝置回報指令已接收/執行。"""
    cmd_id = req.get("command_id", "")
    for cmd in _command_queue:
        if cmd.get("id") == cmd_id:
            cmd["status"] = "executed"
            return api_ok({"message": t("msg.command_executed", id=cmd_id)})
    api_error("NOT_FOUND", t("err.command_not_found", id=cmd_id), 404)


def _parse_command_json(raw: str) -> list:
    """從 LLM 輸出中提取指令 JSON。"""
    text = raw.strip()
    # 去除 markdown fence
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z0-9_-]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text).strip()
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict) and "commands" in parsed:
            return parsed["commands"]
        if isinstance(parsed, list):
            return parsed
    except (json.JSONDecodeError, TypeError):
        pass
    # 嘗試找 JSON 片段
    match = re.search(r'\{[^{}]*"commands"\s*:\s*\[.*?\]\s*\}', text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())["commands"]
        except Exception:
            pass
    return []


# === 自動喚醒機制 ===

_autowake_enabled: bool = True
AUTOWAKE_INTERVAL = 120  # 秒（2 分鐘檢查一次）
_autowake_task: Optional[asyncio.Task] = None
_last_autowake_iso: str = ""
_prev_patient_hash: str = ""


async def _autowake_loop():
    """定期檢查系統狀態變化，自動觸發 AI 決策。"""
    global _last_autowake_iso, _prev_patient_hash
    while True:
        await asyncio.sleep(AUTOWAKE_INTERVAL)
        if not _autowake_enabled:
            continue
        try:
            should_wake, reason = _check_wake_triggers()
            if should_wake:
                print(f"[AUTO-WAKE] 觸發: {reason}")
                # LLM 推論與 TCP 廣播都會阻塞，移到 thread 避免卡住事件迴圈
                await asyncio.to_thread(_run_autowake_decision, reason)
                _last_autowake_iso = datetime.now(TZ_TW).isoformat()
        except Exception as e:
            print(f"[AUTO-WAKE] 失敗: {e}")


def _check_wake_triggers() -> tuple[bool, str]:
    """檢查是否需要自動喚醒 AI 生成決策。"""
    global _prev_patient_hash
    reasons = []

    # 1. 傷患佇列變化（新增/分數大幅變動）
    patients = linkguard_db.get_active_patients()
    current_hash = "|".join(
        f"{p.get('patient_id')}:{p.get('priority')}:{p.get('total_score', 0):.0f}"
        for p in patients
    )
    if current_hash != _prev_patient_hash and _prev_patient_hash:
        reasons.append(t("wake.queue_changed"))
    _prev_patient_hash = current_hash

    # 2. 紅色傷患數量 > 0（高優先持續監控）
    red_count = sum(1 for p in patients if p.get("priority") == "紅色")
    if red_count > 0:
        reasons.append(t("wake.red_attention", count=red_count))

    # 3. 低電量節點警告
    nodes = linkguard_db.get_latest_nodes()
    low_battery = [n for n in nodes if (n.get("battery") or 100) < 20]
    if low_battery:
        ids = ", ".join(str(n.get("node_id")) for n in low_battery)
        reasons.append(t("wake.low_battery", ids=ids))

    if reasons:
        return True, "；".join(reasons)
    return False, ""


def _run_autowake_decision(trigger_reason: str):
    """執行自動喚醒決策生成。"""
    status_text = _format_status_for_llm()
    patients = linkguard_db.get_active_patients()
    patient_summary = format_for_llm(rank_patients(patients)) if patients else t("misc.no_patient")

    system_prompt = (
        "你是災害救援指揮AI助理（自動巡檢模式）。\n"
        "系統偵測到狀態變化，請根據當前資訊生成簡短決策建議。\n"
        "如無需行動，回覆「系統正常，無需額外處置」即可。\n\n"
        f"{START_RULES}\n"
        f"{status_text}\n\n"
        "格式：\n"
        "【巡檢結果】正常/需關注/緊急\n"
        "【建議行動】...\n"
        "【下次關注】..."
    )

    user_prompt = f"自動喚醒原因：{trigger_reason}\n傷員狀況：\n{patient_summary}"

    active_model = _get_active_model()
    model_options = _get_model_options()
    client = ollama.Client(host=OLLAMA_HOST)
    chat_kwargs = dict(
        model=active_model,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        options={**model_options, "num_predict": 512},
    )
    record_ai_activity("自動巡檢", target=f"local:{active_model}", detail=trigger_reason)
    try:
        response = client.chat(**chat_kwargs, think=False)
    except TypeError:
        response = client.chat(**chat_kwargs)
    decision = (response.message.content or "").strip()

    save_decision(
        voice_text=t("history.auto_wake_prefix", reason=trigger_reason),
        patients_summary=patient_summary[:200],
        weather_summary="",
        decision_text=decision,
    )
    print(f"[AUTO-WAKE] 決策已生成: {decision[:80]}...")
    record_ai_activity("自動巡檢決策", target="broadcast(tcp:9000)", detail=decision[:160])

    # 廣播決策到 tcp_server，讓所有 HQ / Field 裝置同步看到 AI 自動唤醒的決策
    try:
        send_to_tcp_with_retry({
            "type": "broadcast_decision",
            "device_id": "autowake",
            "data": {
                "decision": decision,
                "patients": patients,
                "weather": {},
                "trigger": f"auto_wake: {trigger_reason}",
            },
        }, tag="AUTO-WAKE")
    except Exception as e:
        print(f"[AUTO-WAKE] 廣播決策到 tcp_server 失敗: {e}")


class AutoWakeConfig(BaseModel):
    enabled: bool | None = None
    interval: int | None = None


@app.post("/wake")
def manual_wake():
    """手動觸發一次 AI 巡檢決策。"""
    _run_autowake_decision(t("wake.manual"))
    return api_ok({"message": t("msg.wake_triggered")})


@app.post("/wake/config")
def configure_autowake(req: AutoWakeConfig):
    """設定自動喚醒開關與間隔。"""
    global _autowake_enabled, AUTOWAKE_INTERVAL
    if req.enabled is not None:
        _autowake_enabled = req.enabled
    if req.interval is not None and req.interval >= 30:
        AUTOWAKE_INTERVAL = req.interval
    return api_ok({
        "enabled": _autowake_enabled,
        "interval_sec": AUTOWAKE_INTERVAL,
    })


@app.get("/wake/config")
def get_autowake_config():
    """查詢自動喚醒設定。"""
    return api_ok({
        "enabled": _autowake_enabled,
        "interval_sec": AUTOWAKE_INTERVAL,
        "last_trigger": _last_autowake_iso,
    })


@app.get("/locale")
def get_locale_endpoint():
    """Get current UI locale."""
    return api_ok({"locale": get_locale()})


class LocaleRequest(BaseModel):
    locale: str


@app.post("/locale")
def set_locale_endpoint(req: LocaleRequest):
    """Set UI locale ('zh' or 'en')."""
    if req.locale not in ("zh", "en"):
        api_error("INVALID_LOCALE", "locale must be 'zh' or 'en'")
    set_locale(req.locale)
    return api_ok({"locale": get_locale()})


# =====================================================================
# 雙模型端點  (/escalate, /peer/ping, /dual/config, /dual/status)
# =====================================================================

@app.post("/escalate")
def handle_escalation(body: dict):
    """
    大模型端點：接收小模型的升級請求，深度分析後回傳最終決策。
    小模型 PC 會呼叫此端點。
    """
    original = body.get("original_request", {})
    small_result = body.get("small_model_result", {})
    request_id = body.get("request_id", "")

    patients_raw = original.get("patients", [])
    ranked = rank_patients(patients_raw)
    patient_summary = format_for_llm(ranked)

    weather = original.get("weather", {})
    weather_summary = format_weather_for_llm(weather) if weather else t("misc.no_weather")

    recent_decisions = get_recent_decisions(5)
    status_text = _format_status_for_llm()

    small_decision = small_result.get("decision", "")
    small_conf = small_result.get("confidence", 0)
    small_reason = small_result.get("confidence_reason", "")

    system_prompt = (
        "你是 LinkGuard 災害救援深度分析 AI（GEMMA4 26B 深度模式）。\n"
        "小型快速模型已做初步判斷，但信心不足，需要你深度分析。\n\n"
        f"小模型初判結果：\n{small_decision}\n"
        f"小模型信心度：{small_conf}（{small_reason}）\n\n"
        "請基於更完整的分析，產生最終指揮決策。\n"
        "可以修正、補充或完全取代小模型的決策。\n\n"
        f"{START_RULES}\n"
        f"{status_text}\n\n"
        "以下是歷史決策記錄：\n"
        f"{recent_decisions}\n\n"
        "直接輸出決策，格式如下：\n"
        "【優先處置】...\n"
        "【資源調配】...\n"
        "【注意事項】...\n"
        "【與初判的差異】...\n"
        "如需下達指令：\n"
        "【建議指令】類型=xxx | 優先=1-5 | 內容=xxx"
    )

    now = datetime.now(TZ_TW).isoformat()
    user_prompt = (
        f"目前時間：{now}\n"
        f"語音回報：{original.get('voice_text', '')}\n\n"
        f"傷員狀況：\n{patient_summary}\n\n"
        f"氣象資訊：{weather_summary}\n\n"
        f"可用資源：{original.get('resources', '')}\n\n"
        "請根據以上資訊與小模型初判結果，生成最終深度分析決策。"
    )

    runtime_model = _get_runtime_model()
    model_options = _get_model_options()
    client = ollama.Client(host=OLLAMA_HOST)
    t0 = time.monotonic()
    chat_kwargs = dict(
        model=runtime_model,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        options={**model_options, "temperature": 0.2, "num_predict": 1024},
    )
    try:
        resp = client.chat(**chat_kwargs, think=False)
    except TypeError:
        resp = client.chat(**chat_kwargs)
    decision = (resp.message.content or "").strip()
    processing_ms = int((time.monotonic() - t0) * 1000)

    save_decision(
        original.get("voice_text", ""),
        patient_summary,
        weather_summary,
        f"[深度分析] {decision}",
    )

    print(f"[DUAL] 升級決策完成 ({processing_ms}ms): {decision[:80]}...")

    return api_ok({
        "request_id": request_id,
        "decision": decision,
        "model": runtime_model,
        "escalated": True,
        "processing_time_ms": processing_ms,
        "patients": ranked,
    })


@app.get("/peer/ping")
def peer_ping():
    """供對端定期探測本機是否存活。"""
    return api_ok({
        "role": DUAL_CFG.get("local_role", "unknown"),
        "model": _get_runtime_model(),
        "dual_enabled": DUAL_CFG.get("enabled", False),
    })


class DualConfigUpdate(BaseModel):
    enabled: Optional[bool] = None
    local_role: Optional[str] = None
    local_model: Optional[str] = None
    peer_host: Optional[str] = None
    peer_port: Optional[int] = None
    confidence_threshold: Optional[float] = None
    peer_timeout_sec: Optional[int] = None


@app.get("/dual/config")
def get_dual_config():
    """查詢雙模型配置。"""
    return api_ok({"dual": DUAL_CFG})


@app.post("/dual/config")
def update_dual_config(req: DualConfigUpdate):
    """更新雙模型配置（同時寫回 dual_config.json）。"""
    global DUAL_CFG
    updates = req.model_dump(exclude_none=True)
    if "local_role" in updates and updates["local_role"] not in ("small", "large"):
        api_error("INVALID_ROLE", "local_role must be 'small' or 'large'")
    if "confidence_threshold" in updates:
        v = updates["confidence_threshold"]
        if v < 0.0 or v > 1.0:
            api_error("INVALID_THRESHOLD", "confidence_threshold must be 0.0-1.0")

    DUAL_CFG.update(updates)
    _save_dual_config(DUAL_CFG)
    print(f"[DUAL] 配置已更新: {updates}")
    return api_ok({"dual": DUAL_CFG})


@app.get("/dual/status")
def dual_status():
    """查詢雙模型運作狀態。"""
    return api_ok({
        "enabled": DUAL_CFG.get("enabled", False),
        "local_role": DUAL_CFG.get("local_role", "unknown"),
        "local_model": _get_runtime_model(),
        "local_ip": get_local_ip(),
        "peer_host": DUAL_CFG.get("peer_host", ""),
        "peer_port": DUAL_CFG.get("peer_port", 8001),
        "peer_alive": _peer_alive,
        "peer_last_ping_ago_sec": round(time.monotonic() - _peer_last_ping, 1) if _peer_last_ping else None,
        "peer_info": _peer_info,
        "discovery_port": DUAL_DISCOVERY_PORT,
        "discovered_peer_ip": _discovered_peer_ip,
        "discovery_last_seen_sec": round(time.monotonic() - _discovery_last_seen, 1) if _discovery_last_seen else None,
        "confidence_threshold": DUAL_CFG.get("confidence_threshold", 0.6),
    })


# === 對端心跳檢查背景任務 ===

async def _peer_ping_loop():
    """定期 ping 對端，更新 _peer_alive 狀態。"""
    global _peer_alive, _peer_last_ping, _peer_info
    while True:
        interval = DUAL_CFG.get("peer_ping_interval_sec", 10)
        await asyncio.sleep(interval)
        if not DUAL_CFG.get("enabled"):
            _peer_alive = False
            continue
        peer_host = (DUAL_CFG.get("peer_host") or "").strip()
        peer_port = DUAL_CFG.get("peer_port", 8001)
        # 尚未學到 peer IP（auto / 空）時跳過 ping
        if not peer_host or peer_host.lower() == "auto":
            _peer_alive = False
            continue
        url = f"http://{peer_host}:{peer_port}/peer/ping"
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(url)
                if resp.status_code == 200:
                    _peer_alive = True
                    _peer_last_ping = time.monotonic()
                    _peer_info = resp.json()
                else:
                    _peer_alive = False
        except Exception:
            _peer_alive = False


# === 雙模型自動探索（LAN UDP 廣播）===

class _DualDiscoveryProtocol(asyncio.DatagramProtocol):
    """接收對端角色/IP 的 UDP 廣播。"""

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data: bytes, addr):
        global _discovered_peer_ip, _discovery_last_seen
        try:
            msg = json.loads(data.decode("utf-8", errors="ignore"))
        except Exception:
            return
        if msg.get("app") != DUAL_DISCOVERY_MAGIC:
            return
        peer_role = msg.get("role", "")
        local_role = DUAL_CFG.get("local_role", "")
        if not peer_role or peer_role == local_role:
            return
        peer_ip = msg.get("ip") or addr[0]
        if peer_ip == get_local_ip():
            return  # 忽略自己的回音
        is_new = peer_ip != _discovered_peer_ip
        _discovered_peer_ip = peer_ip
        _discovery_last_seen = time.monotonic()
        if _peer_host_is_auto() or DUAL_CFG.get("peer_host") == _discovered_peer_ip:
            if DUAL_CFG.get("peer_host") != peer_ip:
                DUAL_CFG["peer_host"] = peer_ip
                if is_new:
                    logger.info(
                        f"[DUAL-DISC] 發現對端 {peer_role}@{peer_ip}:{msg.get('port', 8001)}"
                        f" 模型={msg.get('model', '?')}"
                    )
        elif is_new:
            logger.info(
                f"[DUAL-DISC] 偵測到 {peer_role}@{peer_ip}（已手動指定 peer_host={DUAL_CFG.get('peer_host')}，忽略）"
            )


async def _dual_announce_loop():
    """每 3 秒在 LAN 廣播本機角色 / IP / 埠。使用阻塞 send 包裝在 to_thread。"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        while True:
            try:
                payload = {
                    "app": DUAL_DISCOVERY_MAGIC,
                    "role": DUAL_CFG.get("local_role", ""),
                    "ip": get_local_ip(),
                    "port": 8001,
                    "model": DUAL_CFG.get("local_model", ""),
                    "ts": time.time(),
                }
                data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                await asyncio.to_thread(sock.sendto, data, ("255.255.255.255", DUAL_DISCOVERY_PORT))
            except Exception as e:
                logger.debug(f"[DUAL-DISC] announce 失敗: {e}")
            await asyncio.sleep(3)
    finally:
        sock.close()


async def _dual_discover_loop():
    """綁 UDP 8011，收到相反角色封包 → 學起 peer IP。"""
    loop = asyncio.get_running_loop()
    try:
        transport, _protocol = await loop.create_datagram_endpoint(
            _DualDiscoveryProtocol,
            local_addr=("0.0.0.0", DUAL_DISCOVERY_PORT),
            allow_broadcast=True,
        )
    except OSError as e:
        logger.warning(f"[DUAL-DISC] 無法綁 UDP:{DUAL_DISCOVERY_PORT} — {e}；自動探索停用")
        return
    logger.info(f"[DUAL-DISC] 自動探索服務啟動 UDP:{DUAL_DISCOVERY_PORT}")
    try:
        # 長駐，直到 task 被 cancel
        while True:
            await asyncio.sleep(3600)
    finally:
        transport.close()


# === 簡易後台儀表板 (Windows / Web) ===

_ADMIN_DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="utf-8">
<title>LinkGuard 後台儀表板</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; }
  body { font-family: 'Segoe UI', 'Microsoft JhengHei', sans-serif;
         background:#0b0f14; color:#e6edf3; margin:0; padding:16px; }
  h1 { margin:0 0 12px; font-size:20px; color:#7ee787; }
  h2 { margin:18px 0 8px; font-size:15px; color:#79c0ff; border-bottom:1px solid #30363d; padding-bottom:4px; }
  .grid { display:grid; grid-template-columns: 1fr 1fr; gap:14px; }
  .card { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:12px; }
  .kv { display:grid; grid-template-columns: 110px 1fr; gap:4px 12px; font-size:13px; }
  .kv .k { color:#8b949e; }
  .kv .v { color:#e6edf3; word-break:break-all; }
  .badge { display:inline-block; padding:2px 8px; border-radius:10px; font-size:11px; font-weight:600; }
  .ok   { background:#1f6f43; color:#bef5cb; }
  .warn { background:#7d4e00; color:#ffe9b3; }
  .err  { background:#7d1f1f; color:#ffc7c7; }
  table { width:100%; border-collapse:collapse; font-size:12px; }
  th, td { text-align:left; padding:4px 6px; border-bottom:1px solid #21262d; vertical-align:top; }
  th { color:#8b949e; font-weight:600; }
  tr:hover td { background:#1c2128; }
  .mono { font-family: 'Consolas','Cascadia Code', monospace; }
  .target { color:#d2a8ff; }
  .action { color:#7ee787; font-weight:600; }
  .detail { color:#c9d1d9; }
  .muted { color:#6e7681; }
  .err-row td { color:#ffa198; }
  pre { background:#0d1117; border:1px solid #21262d; border-radius:6px;
        padding:8px; max-height:280px; overflow:auto; font-size:12px;
        white-space:pre-wrap; word-break:break-all; margin:0; }
  .row { display:flex; gap:12px; align-items:center; flex-wrap:wrap; }
  .pill { padding:2px 10px; background:#21262d; border-radius:14px; font-size:12px; }
</style>
</head>
<body>
  <h1>🛡️ LinkGuard 後台儀表板 <span id="updated" class="muted" style="font-size:12px;font-weight:normal;"></span></h1>

  <div class="grid">
    <div class="card">
      <h2>系統狀態</h2>
      <div class="kv" id="sys"></div>
    </div>
    <div class="card">
      <h2>雙模型 / 對端</h2>
      <div class="kv" id="dual"></div>
    </div>
  </div>

  <div class="card" style="margin-top:14px;">
    <h2>🤖 AI 即時活動 (最近 30 筆)</h2>
    <table id="ai_table">
      <thead><tr><th style="width:80px;">時間</th><th style="width:130px;">動作</th>
                 <th style="width:200px;">目的地</th><th>輸出 / 詳情</th></tr></thead>
      <tbody></tbody>
    </table>
  </div>

  <div class="card" style="margin-top:14px;">
    <h2>🌐 HTTP 請求 (最近 30 筆)</h2>
    <table id="http_table">
      <thead><tr><th style="width:80px;">時間</th><th style="width:60px;">方法</th>
                 <th>路徑</th><th style="width:140px;">來源</th>
                 <th style="width:60px;">狀態</th><th style="width:60px;">耗時</th></tr></thead>
      <tbody></tbody>
    </table>
  </div>

  <div class="card" style="margin-top:14px;">
    <h2>📜 Server Log (尾 80 行)</h2>
    <pre id="log_tail"></pre>
  </div>

<script>
function badgeClass(s) {
  if (s === 'ok' || (typeof s === 'number' && s < 400)) return 'ok';
  if (s === 'warn' || (typeof s === 'number' && s < 500)) return 'warn';
  return 'err';
}
function fmtSecAgo(s) { if (s === null || s === undefined) return '—'; return s.toFixed(1) + 's 前'; }

async function refresh() {
  try {
    const [statRes, actRes, logRes] = await Promise.all([
      fetch('/dual/status'),
      fetch('/admin/activities'),
      fetch('/admin/log_tail?lines=80'),
    ]);
    const stat = await statRes.json();
    const act = await actRes.json();
    const log = await logRes.text();

    const sys = document.getElementById('sys');
    sys.innerHTML = `
      <div class="k">本機 IP</div><div class="v mono">${stat.local_ip || '?'}</div>
      <div class="k">本機角色</div><div class="v">${stat.local_role || '?'}</div>
      <div class="k">本機模型</div><div class="v mono">${stat.local_model || '?'}</div>
      <div class="k">雙模式</div><div class="v"><span class="badge ${stat.enabled?'ok':'warn'}">${stat.enabled?'啟用':'停用'}</span></div>
      <div class="k">最後更新</div><div class="v" id="now"></div>
    `;

    const dual = document.getElementById('dual');
    dual.innerHTML = `
      <div class="k">對端</div><div class="v mono">${stat.peer_host || '—'}:${stat.peer_port || '—'}</div>
      <div class="k">對端狀態</div><div class="v"><span class="badge ${stat.peer_alive?'ok':'err'}">${stat.peer_alive?'在線':'離線'}</span></div>
      <div class="k">最後 ping</div><div class="v">${fmtSecAgo(stat.peer_last_ping_ago_sec)}</div>
      <div class="k">探索埠</div><div class="v mono">UDP:${stat.discovery_port || 8011}</div>
      <div class="k">已發現對端</div><div class="v mono">${stat.discovered_peer_ip || '尚未發現'}</div>
      <div class="k">最後探索</div><div class="v">${fmtSecAgo(stat.discovery_last_seen_sec)}</div>
    `;

    const aiBody = document.querySelector('#ai_table tbody');
    const ai = (act.ai_activities || []).slice(-30).reverse();
    aiBody.innerHTML = ai.length ? ai.map(a => `
      <tr class="${a.status==='error'?'err-row':''}">
        <td class="mono">${a.iso}</td>
        <td class="action">${a.action}</td>
        <td class="target mono">${a.target || '—'}</td>
        <td class="detail">${(a.detail || '').replace(/[<>&]/g, c=>({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]))}</td>
      </tr>`).join('') : '<tr><td colspan="4" class="muted">尚無活動</td></tr>';

    const hBody = document.querySelector('#http_table tbody');
    const h = (act.http_activities || []).slice(-30).reverse();
    hBody.innerHTML = h.length ? h.map(r => `
      <tr>
        <td class="mono">${r.iso}</td>
        <td class="mono">${r.method}</td>
        <td class="mono">${r.path}</td>
        <td class="mono muted">${r.client}</td>
        <td><span class="badge ${badgeClass(r.status)}">${r.status}</span></td>
        <td class="mono">${r.ms}ms</td>
      </tr>`).join('') : '<tr><td colspan="6" class="muted">尚無請求</td></tr>';

    document.getElementById('log_tail').textContent = log;
    document.getElementById('updated').textContent = '· 已更新 ' + new Date().toLocaleTimeString();
  } catch (e) {
    document.getElementById('updated').textContent = '· 更新失敗: ' + e.message;
  }
}
refresh();
setInterval(refresh, 1500);
</script>
</body>
</html>
"""


@app.get("/admin/dashboard", response_class=HTMLResponse)
def admin_dashboard():
    """簡易後台儀表板（HTML，自動每 1.5 秒更新）。"""
    return HTMLResponse(content=_ADMIN_DASHBOARD_HTML)


@app.get("/admin/activities")
def admin_activities():
    """提供儀表板輪詢用：AI 活動 + HTTP 活動。"""
    return api_ok({
        "ai_activities": list(_AI_ACTIVITIES),
        "http_activities": list(_HTTP_ACTIVITIES),
    })


@app.get("/admin/log_tail", response_class=PlainTextResponse)
def admin_log_tail(lines: int = 80):
    """讀取 gemma4_server.log 尾巴。"""
    lines = max(1, min(int(lines), 500))
    try:
        if not _LOG_FILE.exists():
            return PlainTextResponse("(log file not found)", media_type="text/plain; charset=utf-8")
        with open(_LOG_FILE, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            chunk = min(size, 64 * 1024)
            f.seek(size - chunk, 0)
            data = f.read().decode("utf-8", errors="ignore")
        tail = "\n".join(data.splitlines()[-lines:])
        return PlainTextResponse(tail, media_type="text/plain; charset=utf-8")
    except Exception as e:
        return PlainTextResponse(f"(error reading log: {e})", media_type="text/plain; charset=utf-8")


if __name__ == "__main__":
    import uvicorn

    HOST = "0.0.0.0"
    PORT = 8001

    # 啟動前檢查 port 是否被占用，避免「無聲閃退」
    _probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        _probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        _probe.bind((HOST, PORT))
    except OSError as e:
        logger.error(
            "[FATAL] 無法綁定 %s:%d — %s。請執行 `netstat -ano | findstr :%d` 找出佔用程序，"
            "或使用 stop_all.bat 後再啟動。",
            HOST, PORT, e, PORT,
        )
        sys.exit(1)
    finally:
        _probe.close()

    logger.info("[BOOT] 啟動 GEMMA4 AI Server 於 %s:%d", HOST, PORT)
    logger.info("[BOOT] 日誌檔位置：%s", _LOG_FILE)
    uvicorn.run(app, host=HOST, port=PORT, log_config=None)

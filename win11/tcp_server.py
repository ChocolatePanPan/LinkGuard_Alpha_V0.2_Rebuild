from __future__ import annotations

import asyncio
import json
import os
import socket
from datetime import datetime, timezone, timedelta

from zeroconf import ServiceInfo, Zeroconf
import httpx

from weather_fetcher import fetch_weather
from mqtt_broker import get_node_status
import linkguard_db
from utils import get_local_ip, now_iso, generate_msg_id
from i18n import t

# === 設定 ===
TCP_PORT = 9000
QWEN_SERVER_URL = "http://localhost:8001/generate"
QWEN_TRANSLATE_URL = "http://localhost:8001/translate"
TRIAGE_RANK_URL = "http://localhost:8001/triage/rank"
WEATHER_STATION_ID = "C0A980"
WEATHER_API_KEY = os.environ.get("CWA_API_KEY", "CWA-ABB1DE38-E0CD-4EBA-9723-894AAA62AE5E")
TZ_TW = timezone(timedelta(hours=8))
MAX_PATIENT_QUEUE_SIZE = int(os.environ.get("MAX_PATIENT_QUEUE_SIZE", "50"))
MESSAGE_TTL_SECONDS = 3600  # 已讀追蹤器 TTL: 1 小時

import time as _time_mod
_server_start_mono = _time_mod.monotonic()

# === 全域狀態 ===
connected_clients: dict[str, asyncio.StreamWriter] = {}  # {device_id: writer}
_clients_lock: asyncio.Lock | None = None  # 於 main() 中初始化
patient_queue: list[dict] = []
device_locations: dict[str, dict] = {}  # {device_id: {lat, lon, ...}}
current_voice: str = ""
last_weather: dict = {}  # 最後一次氣象快取
message_read_tracker: dict = {}  # {message_id: {"total": int, "read": set(), "created_at": float}}
import itertools as _itertools

_broadcast_counter = _itertools.count(1)  # 原子遞增計數器
device_clock_offsets: dict[str, int] = {}  # {device_id: offset_ms}  (server - client)

# === 送達追蹤 ===
TRACKED_MSG_TYPES = {"decision", "sos_alert", "hazard_report", "patient_warning"}
DELIVERY_MAX_RETRIES = 3
DELIVERY_TTL_SECONDS = 300  # 5 分鐘
delivery_tracking: dict = {}  # {msg_id: {"msg": dict, "targets": set, "delivered": set, "retries": int, "created_at": float}}


def _get_clients_lock() -> asyncio.Lock:
    global _clients_lock
    if _clients_lock is None:
        _clients_lock = asyncio.Lock()
    return _clients_lock


def _handle_task_exception(task: asyncio.Task):
    """create_task done_callback：攔截未處理的例外"""
    if task.cancelled():
        return
    exc = task.exception()
    if exc:
        print(f"[TCP] 背景任務異常: {exc}")


# === 工具函式 ===



def _next_broadcast_id() -> str:
    """產生遞增的廣播 ID（itertools.count 為原子操作）"""
    return f"MSG-{next(_broadcast_counter):04d}"


def _evict_old_trackers():
    """清除超過 TTL 的已讀追蹤器，防止記憶體洩漏"""
    import time
    now = time.monotonic()
    expired = [mid for mid, t in message_read_tracker.items()
               if now - t.get("created_at", 0) > MESSAGE_TTL_SECONDS]
    for mid in expired:
        del message_read_tracker[mid]


async def _register_read_tracker(message_id: str):
    """初始化已讀追蹤器"""
    import time
    _evict_old_trackers()
    async with _get_clients_lock():
        total = len(connected_clients)
    message_read_tracker[message_id] = {
        "total": total,
        "read": set(),
        "created_at": time.monotonic(),
    }


async def _get_read_status(message_id: str) -> dict:
    """取得已讀狀態"""
    tracker = message_read_tracker.get(message_id)
    if not tracker:
        return {"total": 0, "read_count": 0, "unread_devices": []}
    read_set = tracker["read"]
    async with _get_clients_lock():
        unread = [did for did in connected_clients if did not in read_set]
    return {
        "total": tracker["total"],
        "read_count": len(read_set),
        "unread_devices": unread,
    }


def make_msg(msg_type: str, data, msg_id: str | None = None) -> dict:
    """生成標準伺服器訊息"""
    m = {
        "type": msg_type,
        "device_id": "server",
        "timestamp": now_iso(),
        "data": data,
    }
    if msg_id:
        m["msg_id"] = msg_id
    return m



# === Bonjour 服務註冊 ===

async def register_bonjour(port: int) -> tuple[Zeroconf, ServiceInfo]:
    local_ip = get_local_ip()
    info = ServiceInfo(
        "_linkguardpy._tcp.local.",
        "LinkGuard-Command._linkguardpy._tcp.local.",
        addresses=[socket.inet_aton(local_ip)],
        port=port,
        properties={"description": "LinkGuard Command Server"},
    )
    zc = Zeroconf()
    await asyncio.to_thread(zc.register_service, info, allow_name_change=True)
    print(f"[Bonjour] 已註冊服務 {info.name} on {local_ip}:{port}")
    return zc, info


# === 推播 ===

async def broadcast(message: dict):
    data = json.dumps(message, ensure_ascii=False).encode() + b"\n"
    disconnected = []
    async with _get_clients_lock():
        for device_id, writer in connected_clients.items():
            try:
                writer.write(data)
                await writer.drain()
            except Exception:
                disconnected.append(device_id)
        for did in disconnected:
            print(f"[TCP] 推播失敗，移除客戶端 {did}")
            connected_clients.pop(did, None)
    # 對需追蹤的訊息類型建立送達記錄
    msg_type = message.get("type", "")
    msg_id = message.get("msg_id")
    if msg_type in TRACKED_MSG_TYPES and msg_id:
        import time
        async with _get_clients_lock():
            targets = set(connected_clients.keys())
        delivery_tracking[msg_id] = {
            "msg": message,
            "targets": targets,
            "delivered": set(),
            "retries": 0,
            "created_at": time.monotonic(),
        }


async def send_to(writer: asyncio.StreamWriter, message: dict):
    data = json.dumps(message, ensure_ascii=False).encode() + b"\n"
    writer.write(data)
    await writer.drain()


# === 氣象 ===

def get_weather() -> dict:
    global last_weather
    result = fetch_weather(WEATHER_STATION_ID, WEATHER_API_KEY)
    if result:
        last_weather = result
        return result
    if last_weather:
        print("[TCP] 氣象API無回應，使用快取")
    return last_weather


async def broadcast_weather():
    """取得並推播氣象資料"""
    weather = await asyncio.to_thread(get_weather)
    if weather:
        await broadcast(make_msg("weather_update", {
            "station_id": WEATHER_STATION_ID,
            "temperature": weather.get("temperature"),
            "humidity": weather.get("humidity"),
            "wind_speed": weather.get("wind_speed"),
            "rainfall": weather.get("rainfall"),
            "obs_time": weather.get("timestamp", ""),
        }))


# === LoRa 節點狀態推播 ===

async def broadcast_node_status():
    nodes_raw = get_node_status()
    nodes = []
    for nid, info in nodes_raw.items():
        nodes.append({
            "node_id": nid,
            "rssi": info.get("rssi", 0),
            "battery": info.get("battery", 0),
            "location": info.get("location", {}),
            "online": True,
            "last_seen": info.get("timestamp", ""),
        })
    if nodes:
        await broadcast(make_msg("node_status", {"nodes": nodes}))


# === 呼叫 qwen_server ===

async def call_qwen_server(voice_text: str, patients: list, weather: dict) -> dict:
    payload = {
        "voice_text": voice_text,
        "patients": patients,
        "weather": weather or {},
        "resources": "",
    }
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(QWEN_SERVER_URL, json=payload)
        resp.raise_for_status()
        return resp.json()


async def _rank_patients_remote(patients: list) -> list:
    """呼叫 qwen_server /triage/rank 取得評分排序結果。"""
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(TRIAGE_RANK_URL, json={"patients": patients})
        resp.raise_for_status()
        body = resp.json()
        return body.get("data", {}).get("queue", patients)


# === 雙模型升級狀態追蹤（HQ 廣播）===
ESCALATION_POLL_INTERVAL_SEC = 1.0
ESCALATION_POLL_MAX_SEC = 240


async def _poll_escalation_and_broadcast(request_id: str, base_msg: dict, trigger: str):
    """輪詢小模型 /escalation/{rid} 並把狀態變化廣播給 HQ。
    base_msg 為初始 decision message（含 request_id），廣播時用 in-place 更新概念
    （HQ 端依 request_id 取代 record）。"""
    poll_url = f"http://localhost:8001/escalation/{request_id}"
    last_status = None
    last_position = None
    deadline = asyncio.get_event_loop().time() + ESCALATION_POLL_MAX_SEC
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            while asyncio.get_event_loop().time() < deadline:
                await asyncio.sleep(ESCALATION_POLL_INTERVAL_SEC)
                try:
                    resp = await client.get(poll_url)
                    if resp.status_code == 404:
                        return
                    resp.raise_for_status()
                    body = resp.json()
                    data = body.get("data", body) if isinstance(body, dict) else {}
                except Exception as e:
                    print(f"[TCP] 輪詢升級狀態失敗 rid={request_id}: {e}")
                    continue

                status = data.get("status")
                position = data.get("queue_position")
                if status == last_status and position == last_position:
                    continue
                last_status = status
                last_position = position

                update_msg = make_msg("decision_update", {
                    "request_id": request_id,
                    "trigger": trigger,
                    "status": status,
                    "queue_position": position,
                    "estimated_wait_sec": data.get("estimated_wait_sec"),
                    "decision": data.get("final_decision") or data.get("small_decision"),
                    "patients": data.get("patients", []),
                    "provisional": status not in ("done", "failed", "not_required"),
                    "escalated": status == "done",
                    "small_model_time_ms": data.get("small_model_time_ms"),
                    "large_model_time_ms": data.get("large_model_time_ms"),
                    "model": data.get("large_model") if status == "done" else "gemma4:e4b",
                    "error": data.get("error"),
                }, msg_id=generate_msg_id("DEC"))
                await broadcast(update_msg)
                print(f"[TCP] 升級狀態廣播 rid={request_id} status={status} pos={position}")

                if status in ("done", "failed"):
                    return
    except asyncio.CancelledError:
        return
    print(f"[TCP] 升級輪詢逾時 rid={request_id}")


async def generate_and_broadcast(trigger: str,
                                  writer: asyncio.StreamWriter | None = None):
    global current_voice
    try:
        # Phase 1: 立即計算評分排序並廣播給 HQ
        ranked = await _rank_patients_remote(patient_queue)
        ranking_msg = make_msg("patient_ranking", {
            "patients": ranked,
            "trigger": trigger,
        }, msg_id=generate_msg_id("RNK"))
        await broadcast(ranking_msg)
        print(f"[TCP] 傷員排序已廣播 ({len(ranked)} 人)")

        # Phase 2: 呼叫 LLM 生成指揮決策
        weather = await asyncio.to_thread(get_weather)
        result_envelope = await call_qwen_server(current_voice, patient_queue, weather)
        # api_ok 包裝會是 {"ok":true,"data":{...}}；兼容兩種格式
        result = result_envelope.get("data", result_envelope) if isinstance(result_envelope, dict) else {}

        request_id = result.get("request_id")
        provisional = bool(result.get("provisional", False))
        escalation_status = result.get("escalation_status", "not_required")

        decision_msg = make_msg("decision", {
            "decision": result.get("decision", ""),
            "patients": result.get("patients", []),
            "weather": weather,
            "trigger": trigger,
            "request_id": request_id,
            "provisional": provisional,
            "escalation_status": escalation_status,
            "queue_position": result.get("queue_position"),
            "model": result.get("model"),
            "escalated": False,
        }, msg_id=generate_msg_id("DEC"))
        await broadcast(decision_msg)

        # Phase 3: 若是 provisional，啟動輪詢任務追蹤大模型結果並推送更新
        if provisional and request_id:
            task = asyncio.create_task(
                _poll_escalation_and_broadcast(request_id, decision_msg, trigger)
            )
            task.add_done_callback(_handle_task_exception)
    except Exception as e:
        print(f"[TCP] 生成決策失敗: {e}")
        if writer:
            try:
                await send_to(writer, make_msg("error", {
                    "code": "QWEN_TIMEOUT",
                    "message": t("err.decision_gen_failed", err=str(e)),
                }))
            except Exception:
                pass


async def _do_translate(device_id: str, text: str, source_lang: str, target_lang: str,
                        context: str = "medical", requesting_device_id: str = ""):
    """非同步翻譯，完成後回傳結果給請求裝置

    requesting_device_id: 若不為空，內含原始請求者 ID（讓 Mac HQ 能路由回中繼之前的前線裝置）。"""
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(QWEN_TRANSLATE_URL, json={
                "text": text,
                "source_lang": source_lang,
                "target_lang": target_lang,
                "context": context,
            })
            resp.raise_for_status()
            result = resp.json()
        async with _get_clients_lock():
            writer = connected_clients.get(device_id)
        if writer:
            payload = {
                "original": text,
                "translated": result.get("translated", ""),
                "detected_lang": result.get("detected_lang", source_lang),
                "target_lang": target_lang,
            }
            if requesting_device_id:
                payload["requesting_device_id"] = requesting_device_id
            await send_to(writer, make_msg("translate_result", payload))
            print(f"[TCP] 翻譯完成 → {device_id} (req={requesting_device_id or '-'})")
    except Exception as e:
        print(f"[TCP] 翻譯失敗: {e}")
        async with _get_clients_lock():
            writer = connected_clients.get(device_id)
        if writer:
            try:
                await send_to(writer, make_msg("error", {
                    "code": "TRANSLATE_FAILED",
                    "message": t("err.translate_failed", err=str(e)),
                }))
            except Exception:
                pass


# === 訊息處理 ===

async def handle_message(msg: dict, writer: asyncio.StreamWriter):
    global current_voice

    msg_type = msg.get("type")
    data = msg.get("data", {})
    device_id = msg.get("device_id", "unknown")

    if msg_type == "ping":
        import time as _time
        _uptime = round(_time.monotonic() - _server_start_mono, 1)
        pong_data: dict = {
            "connected_devices": len(connected_clients),
            "patient_count": len(patient_queue),
            "server_time": now_iso(),
            "uptime_seconds": _uptime,
        }
        # Mac HQ 自動連線：在 pong 中附上伺服器 IP，供 Bonjour 自動發現後取得 HTTP 主機位址
        if data.get("role") == "hq":
            pong_data["server_ip"] = get_local_ip()
        await send_to(writer, make_msg("pong", pong_data))

    elif msg_type == "time_sync":
        # 時鐘校正
        client_time_str = data.get("client_time", "")
        server_now = datetime.now(TZ_TW)
        try:
            client_time = datetime.fromisoformat(client_time_str)
            # 若 client_time 為 naive datetime，假設為同一時區 (TZ_TW)
            if client_time.tzinfo is None:
                client_time = client_time.replace(tzinfo=TZ_TW)
            offset_ms = int((server_now - client_time).total_seconds() * 1000)
        except (ValueError, TypeError):
            offset_ms = 0
        device_clock_offsets[device_id] = offset_ms
        print(f"[TCP] 時鐘校正 {device_id}: offset={offset_ms}ms")
        await send_to(writer, make_msg("time_sync_response", {
            "server_time": server_now.isoformat(),
            "client_time": client_time_str,
            "offset_ms": offset_ms,
        }))

    elif msg_type == "delivery_ack":
        # 送達確認
        ack_msg_id = data.get("msg_id", "")
        connected_clients[device_id] = writer
        tracker = delivery_tracking.get(ack_msg_id)
        if tracker:
            tracker["delivered"].add(device_id)
            delivered_count = len(tracker["delivered"])
            total_count = len(tracker["targets"])
            print(f"[TCP] 送達確認 {ack_msg_id} from {device_id} ({delivered_count}/{total_count})")
            await broadcast(make_msg("delivery_status", {
                "msg_id": ack_msg_id,
                "delivered_count": delivered_count,
                "total": total_count,
                "pending_devices": list(tracker["targets"] - tracker["delivered"]),
            }))
            # 全部送達後清理
            if tracker["delivered"] >= tracker["targets"]:
                del delivery_tracking[ack_msg_id]
        else:
            await send_to(writer, make_msg("ack", {"status": "unknown_msg_id"}))

    elif msg_type == "patient":
        patient_queue.append(data)
        # 限制佇列大小，移除最舊的資料
        while len(patient_queue) > MAX_PATIENT_QUEUE_SIZE:
            patient_queue.pop(0)
        connected_clients[device_id] = writer
        print(f"[TCP] 收到傷員資料 from {device_id}, 佇列長度: {len(patient_queue)}")
        await send_to(writer, make_msg("ack", {
            "received": "patient", "queue_size": len(patient_queue),
        }))
        await generate_and_broadcast("patient", writer)

    elif msg_type == "location":
        device_locations[device_id] = {
            "lat": data.get("lat"),
            "lon": data.get("lon"),
            "accuracy": data.get("accuracy"),
            "role": data.get("role", ""),
            "name": data.get("name", ""),
            "timestamp": now_iso(),
        }
        connected_clients[device_id] = writer
        # 持久化到資料庫（供 stats_server 統計）
        try:
            linkguard_db.save_location(
                device_id=device_id,
                name=data.get("name", ""),
                role=data.get("role", ""),
                lat=data.get("lat", 0.0),
                lon=data.get("lon", 0.0),
                accuracy=data.get("accuracy", 0.0),
            )
        except Exception as e:
            print(f"[TCP] 儲存位置失敗: {e}")
        print(f"[TCP] 更新位置 {device_id}: lat={data.get('lat')}, lon={data.get('lon')}")
        await send_to(writer, make_msg("ack", {"received": "location"}))

    elif msg_type == "voice_result":
        current_voice = data.get("text", "")
        connected_clients[device_id] = writer
        print(f"[TCP] 收到語音文字 from {device_id}: {current_voice[:60]}")
        await send_to(writer, make_msg("ack", {"received": "voice_result"}))
        await generate_and_broadcast("voice", writer)

    elif msg_type == "request_decision":
        # HQ 主動請求 AI 決策
        context_text = data.get("voice_text", "")
        if context_text:
            current_voice = context_text
        connected_clients[device_id] = writer
        print(f"[TCP] HQ 請求 AI 決策 from {device_id}, context: {current_voice[:60]}")
        await send_to(writer, make_msg("ack", {"received": "request_decision"}))
        await generate_and_broadcast("hq_request", writer)

    elif msg_type == "broadcast_decision":
        # 內部服務（如 gemma4_server 自動唤醒）將已生成的決策廣播出去
        # 只接受本機來源，避免外部註入假決策
        peer = writer.get_extra_info("peername")
        peer_host = peer[0] if peer else ""
        if peer_host not in ("127.0.0.1", "::1", "localhost"):
            print(f"[TCP] 拒絕非本機的 broadcast_decision from {peer_host}")
            await send_to(writer, make_msg("error", {"code": "FORBIDDEN", "message": "only loopback allowed"}))
            return
        decision_payload = {
            "decision": data.get("decision", ""),
            "patients": data.get("patients", []),
            "weather": data.get("weather", {}),
            "trigger": data.get("trigger", "auto_wake"),
        }
        print(f"[TCP] 內部廣播決策 ({decision_payload['trigger']}): {decision_payload['decision'][:60]}")
        await send_to(writer, make_msg("ack", {"received": "broadcast_decision"}))
        await broadcast(make_msg("decision", decision_payload, msg_id=generate_msg_id("DEC")))

    elif msg_type == "broadcast_escalation_trigger":
        # 雙 AI 共識上報觸發（由 gemma4_server loopback 呼叫）
        # 只接受本機來源，避免外部偽造
        peer = writer.get_extra_info("peername")
        peer_host = peer[0] if peer else ""
        if peer_host not in ("127.0.0.1", "::1", "localhost"):
            print(f"[TCP] 拒絕非本機的 broadcast_escalation_trigger from {peer_host}")
            await send_to(writer, make_msg("error", {
                "code": "FORBIDDEN",
                "message": "only loopback allowed"
            }))
            return
        trigger_payload = {
            "request_id": data.get("request_id", ""),
            "status": data.get("status", "dispatched"),
            "hq_summary": data.get("hq_summary", ""),
            "field_summary": data.get("field_summary", ""),
            "hq_session_id": data.get("hq_session_id", ""),
            "field_session_id": data.get("field_session_id", ""),
            "timestamp": data.get("timestamp", ""),
            "combined_prompt": data.get("combined_prompt", ""),
        }
        print(f"[TCP] 雙 AI 共識觸發: rid={trigger_payload['request_id']}")
        await send_to(writer, make_msg("ack", {"received": "broadcast_escalation_trigger"}))
        await broadcast(make_msg("escalation_trigger", trigger_payload,
                                 msg_id=generate_msg_id("ESC")))

    elif msg_type == "text_broadcast":
        # 文字廣播
        message = data.get("message", "")
        sender_name = data.get("sender_name", device_id)
        priority = data.get("priority", "normal")
        broadcast_id = _next_broadcast_id()
        connected_clients[device_id] = writer
        await _register_read_tracker(broadcast_id)
        print(f"[TCP] 文字廣播 [{priority}] from {sender_name}: {message[:40]}")
        await broadcast(make_msg("text_broadcast_rx", {
            "sender_id": device_id,
            "sender_name": sender_name,
            "message": message,
            "priority": priority,
            "broadcast_id": broadcast_id,
        }))
        await send_to(writer, make_msg("ack", {"received": "text_broadcast"}))

    elif msg_type == "message_ack":
        # 已讀回條
        message_id = data.get("message_id", "")
        connected_clients[device_id] = writer
        tracker = message_read_tracker.get(message_id)
        if tracker:
            tracker["read"].add(device_id)
            status = await _get_read_status(message_id)
            print(f"[TCP] 已讀回條 {message_id} from {device_id} ({status['read_count']}/{status['total']})")
            await broadcast(make_msg("read_status", {
                "message_id": message_id,
                "read_count": status["read_count"],
                "total": status["total"],
                "unread_devices": status["unread_devices"],
            }))
        else:
            await send_to(writer, make_msg("ack", {"status": "unknown_message"}))

    elif msg_type == "translate_request":
        # 翻譯請求
        # HQ Swift bridge 中繼時，data 是完整 iPhone payload（含巢狀 data 欄位）
        # 支援兩種結構：{ text, source_lang, ... } 或 { data: { text, ... }, requesting_device_id, ... }
        _inner = data.get("data", {}) if isinstance(data.get("data"), dict) else {}
        text = data.get("text", "") or _inner.get("text", "")
        source_lang = data.get("source_lang", "") or _inner.get("source_lang", "") or "auto"
        target_lang = data.get("target_lang", "") or _inner.get("target_lang", "") or "en"
        context = data.get("context", "") or _inner.get("context", "") or "medical"
        # Mac HQ 中繼時會在 data 內帶上原始前線裝置 ID，以便路由回應
        requesting_device_id = data.get("requesting_device_id", "") or _inner.get("requesting_device_id", "")
        connected_clients[device_id] = writer
        print(f"[TCP] 翻譯請求 from {device_id} (req={requesting_device_id or '-'}): {text[:40]}")
        await send_to(writer, make_msg("ack", {"received": "translate_request"}))
        # 非同步翻譯
        _task = asyncio.create_task(_do_translate(device_id, text, source_lang, target_lang, context, requesting_device_id))
        _task.add_done_callback(_handle_task_exception)

    elif msg_type == "patient_warning":
        # 傷患惡化預警 → 廣播給所有裝置
        connected_clients[device_id] = writer
        print(f"[TCP] 傷患預警 from {device_id}: {data.get('patient_id', '?')}")
        await broadcast(make_msg("patient_warning", data, msg_id=generate_msg_id("PW")))

    elif msg_type in ("voice_broadcast", "radio_control"):
        # 廣播控制：手機通知開始/停止語音廣播（相容 radio_control 別名）
        action = data.get("action", "")
        sender_name = data.get("sender_name", data.get("senderName", device_id))
        connected_clients[device_id] = writer
        print(f"[TCP] 語音廣播 {action} from {sender_name} ({device_id})")
        await broadcast(make_msg("voice_broadcast_rx", {
            "sender_id": device_id,
            "sender_name": sender_name,
            "action": action,
        }))

    elif msg_type == "report_summary":
        # http_server 轉送的會報摘要 → 推播給所有裝置
        print(f"[TCP] 收到會報摘要: {data.get('report_id', '?')}")
        await broadcast(make_msg("report_summary", data))

    elif msg_type == "status_report":
        # 前線裝置狀態報告（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        print(f"[TCP] 裝置狀態 from {device_id}: bat={data.get('battery', '?')}% ble={data.get('bleConnected', '?')}")
        try:
            linkguard_db.save_status_report(device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存狀態失敗: {e}")
        await send_to(writer, make_msg("ack", {"received": "status_report"}))

    elif msg_type == "chat_message":
        # 聊天訊息（經 Mac HQ 轉發）
        sender_name = data.get("senderName", data.get("sender_name", device_id))
        content = data.get("content", "")
        connected_clients[device_id] = writer
        print(f"[TCP] 聊天 from {sender_name}: {content[:40]}")
        try:
            linkguard_db.save_chat(device_id, sender_name, content)
        except Exception as e:
            print(f"[TCP] 儲存聊天失敗: {e}")
        await send_to(writer, make_msg("ack", {"received": "chat_message"}))

    elif msg_type == "quick_status":
        # 快速狀態（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        print(f"[TCP] 快速狀態 from {device_id}: {data.get('type', '?')}")
        try:
            linkguard_db.save_event("quick_status", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存快速狀態失敗: {e}")
        await send_to(writer, make_msg("ack", {"received": "quick_status"}))

    elif msg_type == "task_update":
        # 任務更新（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        print(f"[TCP] 任務更新 from {device_id}: {data.get('title', '?')} → {data.get('taskStatus', '?')}")
        try:
            linkguard_db.save_event("task_update", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存任務更新失敗: {e}")
        await send_to(writer, make_msg("ack", {"received": "task_update"}))

    elif msg_type == "hazard_report":
        # 危險回報（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        print(f"[TCP] 危險回報 from {device_id}: {data.get('hazardType', '?')}")
        try:
            linkguard_db.save_event("hazard_report", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存危險回報失敗: {e}")
        await broadcast(make_msg("hazard_report", data, msg_id=generate_msg_id("HAZ")))

    elif msg_type == "reinforcement_request":
        # 增援請求（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        print(f"[TCP] 增援請求 from {data.get('fromTeam', device_id)}: {data.get('message', '')[:40]}")
        try:
            linkguard_db.save_event("reinforcement_request", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存增援請求失敗: {e}")
        await send_to(writer, make_msg("ack", {"received": "reinforcement_request"}))

    elif msg_type == "reinforcement_reply":
        # 增援回覆（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        print(f"[TCP] 增援回覆 from {device_id}")
        try:
            linkguard_db.save_event("reinforcement_reply", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存增援回覆失敗: {e}")
        await send_to(writer, make_msg("ack", {"received": "reinforcement_reply"}))

    elif msg_type == "sos":
        # SOS 緊急呼叫（經 Mac HQ 轉發）
        sender_name = data.get("sender_name", device_id)
        connected_clients[device_id] = writer
        print(f"[TCP] 🆘 SOS from {sender_name} ({device_id})")
        try:
            linkguard_db.save_event("sos", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存 SOS 失敗: {e}")
        await broadcast(make_msg("sos_alert", data, msg_id=generate_msg_id("SOS")))

    elif msg_type == "sos_cancel":
        # SOS 取消（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        print(f"[TCP] SOS 取消 from {device_id}: {data.get('sos_id', '?')}")
        try:
            linkguard_db.save_event("sos_cancel", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存 SOS 取消失敗: {e}")
        await broadcast(make_msg("sos_cancel_alert", data))

    elif msg_type == "photo_alert":
        # 照片回報（經 Mac HQ 轉發）
        connected_clients[device_id] = writer
        photo_id = data.get("photo_id", "?")
        print(f"[TCP] 照片回報 from {device_id}: {photo_id}")
        try:
            linkguard_db.save_event("photo_alert", device_id, data)
        except Exception as e:
            print(f"[TCP] 儲存照片回報失敗: {e}")
        await broadcast(make_msg("photo_alert", data))

    else:
        await send_to(writer, make_msg("error", {
            "code": "JSON_PARSE_ERROR",
            "message": t("err.unknown_type", type=msg_type),
        }))


# === TCP 連線處理 ===

def normalize_message(raw: dict) -> dict:
    """將 WiFiMessage 格式 {msgType, deviceID, payload} 轉換為基礎封包格式 {type, data, device_id, timestamp}"""
    if "msgType" in raw and "payload" in raw:
        msg_type = raw["msgType"]
        # iOS 發送方的 device_id（WiFiMessage.deviceID 欄位，比 inner payload 更可靠）
        wifi_device_id = raw.get("deviceID") or raw.get("device_id") or "unknown"
        payload_str = raw["payload"]
        try:
            inner = json.loads(payload_str) if isinstance(payload_str, str) else payload_str
        except (json.JSONDecodeError, TypeError):
            inner = {}

        # 若內層已帶 type/data → 直接用內層
        if isinstance(inner, dict) and "type" in inner:
            if "timestamp" not in inner:
                inner["timestamp"] = now_iso()
            # 補上 device_id（優先 inner，其次 WiFiMessage 頂層 deviceID）
            if not inner.get("device_id") or inner["device_id"] == "unknown":
                if wifi_device_id != "unknown":
                    inner["device_id"] = wifi_device_id
            return inner

        # 從 inner 取 device_id，支援 snake_case 與 camelCase（FieldStatusReport 用 deviceID）
        inner_device_id = "unknown"
        if isinstance(inner, dict):
            inner_device_id = (inner.get("device_id")
                               or inner.get("deviceID")
                               or wifi_device_id)
        else:
            inner_device_id = wifi_device_id

        # 否則以 msgType 當 type，inner 當 data
        return {
            "type": msg_type,
            "data": inner if isinstance(inner, dict) else {},
            "device_id": inner_device_id,
            "timestamp": inner.get("timestamp", now_iso()) if isinstance(inner, dict) else now_iso(),
        }

    # 已經是基礎封包格式
    if "timestamp" not in raw:
        raw["timestamp"] = now_iso()
    return raw


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    addr = writer.get_extra_info("peername")
    print(f"[TCP] 新連線: {addr}")

    try:
        while True:
            data = await reader.readline()
            if not data:
                break
            try:
                raw = json.loads(data.decode())
                msg = normalize_message(raw)
                device_id = msg.get("device_id", "unknown")
                async with _get_clients_lock():
                    connected_clients[device_id] = writer
                await handle_message(msg, writer)
            except json.JSONDecodeError:
                print(f"[TCP] 無效 JSON from {addr}")
                await send_to(writer, make_msg("error", {
                    "code": "JSON_PARSE_ERROR",
                    "message": t("err.json_parse_failed"),
                }))
    except asyncio.CancelledError:
        pass
    except ConnectionResetError:
        pass
    except Exception as e:
        print(f"[TCP] 連線錯誤 {addr}: {e}")
    finally:
        async with _get_clients_lock():
            to_remove = [did for did, w in connected_clients.items() if w is writer]
            for did in to_remove:
                del connected_clients[did]
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        print(f"[TCP] 斷線: {addr}")


# === 定時任務 ===

async def periodic_weather(interval: int = 300):
    """每 5 分鐘自動推播氣象更新"""
    while True:
        await asyncio.sleep(interval)
        try:
            await broadcast_weather()
        except Exception as e:
            print(f"[TCP] 定時氣象推播失敗: {e}")


async def periodic_node_status(interval: int = 30):
    """每 30 秒推播 LoRa 節點狀態"""
    while True:
        await asyncio.sleep(interval)
        try:
            await broadcast_node_status()
        except Exception as e:
            print(f"[TCP] 定時節點推播失敗: {e}")


async def periodic_delivery_retry(interval: int = 30):
    """每 30 秒檢查未全部送達的追蹤訊息，對未送達裝置重送"""
    import time
    while True:
        await asyncio.sleep(interval)
        now = time.monotonic()
        expired = []
        for msg_id, tracker in list(delivery_tracking.items()):
            # TTL 過期清理
            if now - tracker["created_at"] > DELIVERY_TTL_SECONDS:
                expired.append(msg_id)
                continue
            # 已全部送達
            if tracker["delivered"] >= tracker["targets"]:
                expired.append(msg_id)
                continue
            # 超過最大重試次數
            if tracker["retries"] >= DELIVERY_MAX_RETRIES:
                pending = tracker["targets"] - tracker["delivered"]
                print(f"[TCP] 送達重試上限 {msg_id}: 未送達 {pending}")
                expired.append(msg_id)
                continue
            # 重送給未確認的裝置
            pending_devices = tracker["targets"] - tracker["delivered"]
            tracker["retries"] += 1
            msg_data = json.dumps(tracker["msg"], ensure_ascii=False).encode() + b"\n"
            async with _get_clients_lock():
                for did in pending_devices:
                    writer = connected_clients.get(did)
                    if writer:
                        try:
                            writer.write(msg_data)
                            await writer.drain()
                        except Exception:
                            pass
            print(f"[TCP] 重送 {msg_id} (第{tracker['retries']}次) → {pending_devices}")
        for msg_id in expired:
            delivery_tracking.pop(msg_id, None)


# === 啟動檢查 ===

async def check_qwen_server():
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = await client.get("http://localhost:8001/docs")
            if resp.status_code == 200:
                print("[TCP] qwen_server (port 8001) 連線正常")
                return True
    except Exception:
        pass
    print("[TCP] 警告: qwen_server (port 8001) 無回應，決策生成將會失敗")
    return False


# === 主程式 ===

async def main():
    local_ip = get_local_ip()
    print(f"[TCP] 本機 IP: {local_ip}")

    linkguard_db.init_db()
    await check_qwen_server()

    zc, info = await register_bonjour(TCP_PORT)

    server = await asyncio.start_server(handle_client, "0.0.0.0", TCP_PORT)
    print(f"[TCP] Server 啟動於 0.0.0.0:{TCP_PORT}")
    print(f"[TCP] 等待客戶端連線...")

    # 啟動定時推播任務
    t1 = asyncio.create_task(periodic_weather())
    t1.add_done_callback(_handle_task_exception)
    t2 = asyncio.create_task(periodic_node_status())
    t2.add_done_callback(_handle_task_exception)
    t3 = asyncio.create_task(periodic_delivery_retry())
    t3.add_done_callback(_handle_task_exception)

    try:
        async with server:
            await server.serve_forever()
    finally:
        await asyncio.to_thread(zc.unregister_service, info)
        zc.close()
        print("[TCP] Server 已關閉")


if __name__ == "__main__":
    asyncio.run(main())

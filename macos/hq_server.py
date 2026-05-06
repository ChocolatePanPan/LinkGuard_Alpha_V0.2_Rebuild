"""
hq_server.py — LinkGuard Windows HQ 指揮中心伺服器
完整替代 macOS HQ 的 Windows 版本

服務:
  - TCP 命令伺服器  :8930  (前線裝置連線)
  - LGAP 音訊伺服器 :8005  (PTT 即時音訊)
  - WebSocket + HTTP :8080  (HQ 儀表板)
  - Bonjour 自動發現 (前線裝置)
  - TCP 後端橋接    :9000  (連接現有 Windows 後端)
"""
from __future__ import annotations

import asyncio
import itertools
import json
import os
import socket
import struct
import time
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

import aiohttp
from aiohttp import web
import httpx
from zeroconf import ServiceInfo, Zeroconf
from utils import get_local_ip
from i18n import t
import re
import linkguard_db

# @ 提及解析器：抓取 @ 後的中英文/數字/-_ token (最多20字)
_MENTION_RE = re.compile(r'@([\u4e00-\u9fa5A-Za-z0-9_\-]{1,20})')

def _parse_mentions(text: str, nicknames: dict) -> list[str]:
    """從訊息文字解析 @提及，回傳被提及的 device_id 列表 (去重保序)。
    匹配規則：
      1) token 完全等於某個 nickname → 對應 device_id
      2) token 完全等於某個 device_id → device_id 自己
      3) token 是 device_id 的後綴 (例: @001 命中 DEV-001)
    """
    if not text:
        return []
    tokens = _MENTION_RE.findall(text)
    if not tokens:
        return []
    nick_to_id = {}
    id_set = set()
    for did, info in (nicknames or {}).items():
        id_set.add(did)
        nk = (info or {}).get("nickname")
        if nk:
            nick_to_id[nk] = did
    result = []
    seen = set()
    for tok in tokens:
        did = None
        if tok in nick_to_id:
            did = nick_to_id[tok]
        elif tok in id_set:
            did = tok
        else:
            for cand in id_set:
                if cand.endswith(tok) and len(tok) >= 3:
                    did = cand
                    break
        if did and did not in seen:
            seen.add(did)
            result.append(did)
    return result

# === 設定 ===
COMMAND_PORT = 8930       # 前線裝置 TCP 連線
LGAP_PORT = 8005          # PTT 音訊串流（對齊 Mac HQ AudioStreamServer + Android Field）
DASHBOARD_PORT = 8080     # Web 儀表板
BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = 9000       # 後端 TCP 伺服器
WHISPER_URL = f"http://localhost:8002/transcribe"
QWEN_URL = "http://localhost:8001"
STATIC_DIR = Path(__file__).parent / "hq"
TZ_TW = timezone(timedelta(hours=8))
LGAP_MAGIC = 0x4C474150   # "LGAP"

def now_iso():
    return datetime.now(TZ_TW).isoformat()

def _discover_lan_ips() -> list[str]:
    """回傳可用的本機 IPv4（優先實體 LAN，並去除 loopback）。"""
    primary = get_local_ip()
    found: list[str] = []

    # 優先放主 IP
    if primary and not primary.startswith("127."):
        found.append(primary)

    # 補上其他可用 IPv4，避免多網卡時 Bonjour 註冊到不理想介面
    try:
        hostname = socket.gethostname()
        for item in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = item[4][0]
            if ip and not ip.startswith("127.") and ip not in found:
                found.append(ip)
    except OSError:
        pass

    # 依常見 LAN 優先順序排序
    def _rank(ip: str) -> int:
        if ip.startswith("192.168."):
            return 0
        if ip.startswith("10."):
            return 1
        if ip.startswith("172."):
            return 2
        return 3

    found.sort(key=_rank)
    return found[:4]

# ============================================================
# HQ 狀態管理
# ============================================================
class HQState:
    def __init__(self):
        # 連線
        self.field_clients: dict[str, asyncio.StreamWriter] = {}  # device_id → writer
        self.ws_clients: set[web.WebSocketResponse] = set()
        self.backend_writer: asyncio.StreamWriter | None = None
        self.backend_reader: asyncio.StreamReader | None = None
        self._backend_lock = asyncio.Lock()

        # 資料
        self.victims: dict[str, dict] = {}
        self.teams: dict[str, dict] = {}
        self.commands: list[dict] = []
        self.chats: list[dict] = []
        self.patients: list[dict] = []
        self.decisions: list[dict] = []
        self.briefings: list[dict] = []
        self.radio_reports: list[dict] = []
        self.disaster_site: dict = {}
        self.personnel: list[dict] = []
        self.reinforcements: list[dict] = []
        self.quick_statuses: list[dict] = []
        self.tasks: list[dict] = []
        self.hazards: list[dict] = []
        self.pws_alerts: list[dict] = []
        self.sos_alerts: list[dict] = []
        self.photos: list[dict] = []
        self.notifications: list[dict] = []
        self.timeline: list[dict] = []
        self.stats: dict = {}
        self.weather: dict = {}
        self.lora_nodes: dict[str, dict] = {}
        self.locations: dict[str, dict] = {}
        self.countdowns: list[dict] = []
        self.text_broadcasts: list[dict] = []
        self.patient_warnings: list[dict] = []
        # 暱稱表：device_id → {device_id, nickname, role, updated_at}
        self.nicknames: dict[str, dict] = {}

        # 狀態
        self.start_time = time.time()
        self._cmd_counter = itertools.count(1)
        self._msg_counter = itertools.count(1)

    def next_cmd_id(self) -> str:
        return f"CMD-{next(self._cmd_counter):04d}"

    def next_msg_id(self) -> str:
        return f"MSG-{next(self._msg_counter):04d}"

    def add_timeline(self, event_type: str, title: str, detail: str = "",
                     device_id: str = "HQ"):
        self.timeline.insert(0, {
            "id": str(uuid.uuid4())[:8],
            "event_type": event_type,
            "title": title,
            "detail": detail,
            "device_id": device_id,
            "timestamp": now_iso(),
        })
        if len(self.timeline) > 500:
            self.timeline = self.timeline[:500]

    def get_snapshot(self) -> dict:
        """完整狀態快照"""
        return {
            "victims": self.victims,
            "teams": self.teams,
            "commands": self.commands[-100:],
            "chats": self.chats[-200:],
            "patients": self.patients[-50:],
            "decisions": self.decisions[-50:],
            "briefings": self.briefings[-20:],
            "radio_reports": self.radio_reports[-50:],
            "disaster_site": self.disaster_site,
            "personnel": self.personnel,
            "reinforcements": self.reinforcements[-50:],
            "quick_statuses": self.quick_statuses[-50:],
            "tasks": self.tasks,
            "hazards": self.hazards[-50:],
            "pws_alerts": self.pws_alerts[-20:],
            "sos_alerts": self.sos_alerts,
            "photos": self.photos[-100:],
            "notifications": self.notifications[-50:],
            "timeline": self.timeline[:200],
            "stats": self._compute_stats(),
            "weather": self.weather,
            "lora_nodes": self.lora_nodes,
            "locations": self.locations,
            "countdowns": self.countdowns,
            "text_broadcasts": self.text_broadcasts[-50:],
            "patient_warnings": self.patient_warnings[-20:],
            "connected_devices": list(self.field_clients.keys()),
            "device_count": len(self.field_clients),
            "backend_connected": self.backend_writer is not None,
            "nicknames": list(self.nicknames.values()),
        }

    def _compute_stats(self) -> dict:
        victims = list(self.victims.values())
        teams = list(self.teams.values())
        return {
            "victims_total": len(victims),
            "victims_online": sum(1 for v in victims if v.get("isOnline")),
            "victims_sos": sum(1 for v in victims if v.get("isSOS")),
            "teams_total": len(teams),
            "teams_online": sum(1 for t in teams if t.get("isOnline")),
            "patients_total": len(self.patients),
            "patients_immediate": sum(1 for p in self.patients if p.get("triage") == "immediate"),
            "patients_delayed": sum(1 for p in self.patients if p.get("triage") == "delayed"),
            "patients_minor": sum(1 for p in self.patients if p.get("triage") == "minor"),
            "patients_expectant": sum(1 for p in self.patients if p.get("triage") == "expectant"),
            "personnel_total": len(self.personnel),
            "commands_count": len(self.commands),
            "chats_count": len(self.chats),
            "radio_reports_count": len(self.radio_reports),
            "decisions_count": len(self.decisions),
            "photos_count": len(self.photos),
            "event_duration_min": int((time.time() - self.start_time) / 60),
            "sos_active": len(self.sos_alerts),
        }


state = HQState()

# ============================================================
# WebSocket 廣播 (→ 儀表板)
# ============================================================
async def ws_broadcast(msg_type: str, data: dict):
    """向所有 WebSocket 儀表板客戶端推播"""
    payload = json.dumps({"type": msg_type, "data": data, "timestamp": now_iso()},
                         ensure_ascii=False)
    dead = set()
    for ws in state.ws_clients:
        try:
            await ws.send_str(payload)
        except Exception:
            dead.add(ws)
    state.ws_clients -= dead


# ============================================================
# TCP 前線 → HQ (port 8930)
# ============================================================
async def field_broadcast(message: dict, exclude: str | None = None):
    """向所有前線裝置廣播 JSON"""
    data = json.dumps(message, ensure_ascii=False).encode() + b"\n"
    dead = []
    for did, writer in state.field_clients.items():
        if did == exclude:
            continue
        try:
            writer.write(data)
            await writer.drain()
        except Exception:
            dead.append(did)
    for did in dead:
        state.field_clients.pop(did, None)
        print(f"[CMD] 移除斷線裝置 {did}")


async def field_send(writer: asyncio.StreamWriter, message: dict):
    data = json.dumps(message, ensure_ascii=False).encode() + b"\n"
    writer.write(data)
    await writer.drain()


def make_hq_msg(msg_type: str, data: dict) -> dict:
    return {
        "type": msg_type,
        "device_id": "HQ",
        "timestamp": now_iso(),
        "data": data,
    }


async def forward_to_backend(message: dict):
    """轉發資料到後端 TCP:9000"""
    async with state._backend_lock:
        writer = state.backend_writer
    if writer is None:
        return
    try:
        data = json.dumps(message, ensure_ascii=False).encode() + b"\n"
        writer.write(data)
        await writer.drain()
    except Exception as e:
        print(f"[BACKEND] 轉發失敗: {e}")
        async with state._backend_lock:
            state.backend_writer = None
            state.backend_reader = None


async def handle_field_message(msg: dict, writer: asyncio.StreamWriter):
    """處理前線裝置發來的訊息"""
    msg_type = msg.get("type", "")
    data = msg.get("data", {})
    device_id = msg.get("device_id", "unknown")

    # 註冊裝置
    state.field_clients[device_id] = writer

    if msg_type == "status_report":
        # 裝置狀態（含受困者/團隊資料）
        victims = data.get("victims", [])
        for v in victims:
            vid = v.get("id", "")
            if vid:
                state.victims[vid] = {**v, "source_device": device_id, "updated": now_iso()}
        teams_data = data.get("teams") or data.get("teamMembers") or []
        for t in teams_data:
            tid = t.get("id", "")
            if tid:
                state.teams[tid] = {**t, "source_device": device_id, "updated": now_iso()}

        # 自動將前線裝置註冊為救援人員
        self_p = data.get("selfPersonnel")
        if self_p and isinstance(self_p, dict):
            auto_id = self_p.get("id", f"field-{device_id}")
            auto_entry = {
                "id": auto_id,
                "name": self_p.get("name", device_id),
                "assignedZone": self_p.get("assignedZone", ""),
                "assignedFloor": self_p.get("assignedFloor", ""),
                "role": self_p.get("role", "rescue"),
                "timestamp": now_iso(),
            }
        else:
            auto_id = f"field-{device_id}"
            auto_entry = {
                "id": auto_id,
                "name": device_id,
                "assignedZone": "",
                "assignedFloor": "",
                "role": "rescue",
                "timestamp": now_iso(),
            }
        found = False
        for i, p in enumerate(state.personnel):
            if p.get("id") == auto_id:
                state.personnel[i] = auto_entry
                found = True
                break
        if not found:
            state.personnel.append(auto_entry)

        state.add_timeline("status", f"狀態回報 from {device_id}",
                          f"受困者:{len(victims)} 隊員:{len(teams_data)}", device_id)
        await ws_broadcast("status_report", {
            "device_id": device_id, "victims": victims, "teams": teams_data,
            "battery": data.get("battery"), "rssi": data.get("rssi"),
        })
        await forward_to_backend(msg)

    elif msg_type == "chat_message":
        content_text = data.get("content", "")
        mentions = data.get("mentions") or _parse_mentions(content_text, state.nicknames)
        chat = {
            "id": data.get("id", str(uuid.uuid4())[:8]),
            "senderID": data.get("senderID", device_id),
            "senderName": data.get("senderName", device_id),
            "recipientID": data.get("recipientID"),
            "content": content_text,
            "timestamp": data.get("timestamp", now_iso()),
            "isRead": False,
            "mentions": mentions,
        }
        state.chats.append(chat)
        state.add_timeline("chat", f"聊天 from {chat['senderName']}",
                          chat['content'][:60], device_id)
        # 中繼到其他前線
        await field_broadcast(make_hq_msg("chat_message", chat), exclude=device_id)
        await ws_broadcast("chat_message", chat)
        # 對被 @ 的人額外推送個人通知
        for did in mentions:
            w = state.field_clients.get(did)
            if w:
                await field_send(w, make_hq_msg("personal_notification", {
                    "id": str(uuid.uuid4())[:8],
                    "target_device": did,
                    "title": f"@提及 來自 {chat['senderName']}",
                    "content": content_text,
                    "from_chat_id": chat["id"],
                    "timestamp": now_iso(),
                }))
        await forward_to_backend(msg)

    elif msg_type == "quick_status":
        qs = {
            "id": data.get("id", str(uuid.uuid4())[:8]),
            "type": data.get("type", ""),
            "senderID": data.get("senderID", device_id),
            "senderName": data.get("senderName", device_id),
            "zone": data.get("zone", ""),
            "note": data.get("note", ""),
            "timestamp": now_iso(),
        }
        state.quick_statuses.append(qs)
        type_labels = {"area_clear": "區域清除", "need_support": "需要支援",
                       "victim_found": "發現受困者", "retreating": "撤退中"}
        label = type_labels.get(qs["type"], qs["type"])
        state.add_timeline("quick_status", f"{label} - {qs['senderName']}",
                          qs.get("note", ""), device_id)
        await field_broadcast(make_hq_msg("quick_status", qs), exclude=device_id)
        await ws_broadcast("quick_status", qs)
        await forward_to_backend(msg)

    elif msg_type == "patient":
        patient = {**data, "device_id": device_id, "received_at": now_iso()}
        state.patients.append(patient)
        state.add_timeline("patient", f"傷患報告 from {device_id}",
                          f"位置:{data.get('location', '')}", device_id)
        await ws_broadcast("patient", patient)
        await forward_to_backend(msg)
        # 自動進行 START 檢傷分類
        asyncio.create_task(_auto_triage_patient(patient))

    elif msg_type == "sos":
        sos_id = data.get("sos_id", str(uuid.uuid4())[:8])
        sender_name = data.get("sender_name", device_id)
        lat = data.get("lat", 0)
        lon = data.get("lon", 0)
        # 同時保留 snake_case / camelCase，確保 iOS、Android、Web 儀表板皆可相容解析
        sos = {
            "id": sos_id,
            "sos_id": sos_id,
            "device_id": device_id,
            "deviceID": device_id,
            "sender_name": sender_name,
            "senderName": sender_name,
            "lat": lat,
            "lon": lon,
            "timestamp": now_iso(),
        }
        state.sos_alerts.append(sos)
        state.add_timeline("sos", f"🆘 SOS from {sos['senderName']}",
                          f"GPS: {sos['lat']}, {sos['lon']}", device_id)
        await field_broadcast(make_hq_msg("sos_alert", sos), exclude=device_id)
        await ws_broadcast("sos_alert", sos)
        await forward_to_backend(msg)

    elif msg_type == "sos_cancel":
        sos_id = data.get("sos_id", "")
        sender_name = data.get("sender_name", device_id)
        cancel_payload = {
            "sos_id": sos_id,
            "device_id": device_id,
            "sender_name": sender_name,
        }
        state.sos_alerts = [s for s in state.sos_alerts if s.get("id") != sos_id]
        state.add_timeline("sos_cancel", f"SOS 取消 {sos_id}", "", device_id)
        await field_broadcast(make_hq_msg("sos_cancel_alert", cancel_payload), exclude=device_id)
        await ws_broadcast("sos_cancel", {"sos_id": sos_id})
        await forward_to_backend(msg)

    elif msg_type == "hazard_report":
        hazard = {**data, "timestamp": now_iso()}
        state.hazards.append(hazard)
        state.add_timeline("hazard", f"危害回報 - {data.get('hazardType', '')}",
                          data.get("description", ""), device_id)
        await field_broadcast(make_hq_msg("hazard_report", hazard), exclude=device_id)
        await ws_broadcast("hazard_report", hazard)
        await forward_to_backend(msg)

    elif msg_type == "reinforcement_request":
        req = {
            "id": data.get("id", str(uuid.uuid4())[:8]),
            "fromTeam": data.get("fromTeam", device_id),
            "message": data.get("message", ""),
            "location": data.get("location", ""),
            "timestamp": now_iso(),
            "status": "pending",
            "respondedBy": [],
        }
        state.reinforcements.append(req)
        state.add_timeline("reinforcement", f"增援請求 from {req['fromTeam']}",
                          req["message"][:60], device_id)
        await ws_broadcast("reinforcement_request", req)
        await forward_to_backend(msg)

    elif msg_type == "task_update":
        task_id = data.get("id", data.get("taskId", ""))
        for t in state.tasks:
            if t.get("id") == task_id:
                t["status"] = data.get("taskStatus", data.get("status", t["status"]))
                break
        state.add_timeline("task", f"任務更新 {task_id}",
                          data.get("taskStatus", ""), device_id)
        await ws_broadcast("task_update", data)
        await forward_to_backend(msg)

    elif msg_type == "location":
        state.locations[device_id] = {
            "lat": data.get("lat"),
            "lon": data.get("lon"),
            "accuracy": data.get("accuracy"),
            "name": data.get("name", ""),
            "role": data.get("role", ""),
            "timestamp": now_iso(),
        }
        await ws_broadcast("location", {
            "device_id": device_id, **state.locations[device_id]
        })
        await forward_to_backend(msg)

    elif msg_type == "text_broadcast":
        tb = {
            "id": state.next_msg_id(),
            "sender_id": device_id,
            "sender_name": data.get("sender_name", device_id),
            "message": data.get("message", ""),
            "priority": data.get("priority", "normal"),
            "timestamp": now_iso(),
        }
        state.text_broadcasts.append(tb)
        state.add_timeline("broadcast", f"文字廣播 from {tb['sender_name']}",
                          tb["message"][:60], device_id)
        await field_broadcast(make_hq_msg("text_broadcast_rx", tb), exclude=device_id)
        await ws_broadcast("text_broadcast", tb)
        await forward_to_backend(msg)

    elif msg_type == "message_ack":
        await ws_broadcast("message_ack", data)
        await forward_to_backend(msg)

    elif msg_type == "patient_warning":
        pw = {**data, "timestamp": now_iso()}
        state.patient_warnings.append(pw)
        state.add_timeline("patient_warning", f"傷患惡化 {data.get('patient_id', '')}",
                          data.get("triage_level", ""), device_id)
        await field_broadcast(make_hq_msg("patient_warning", pw), exclude=device_id)
        await ws_broadcast("patient_warning", pw)
        await forward_to_backend(msg)

    elif msg_type in ("voice_broadcast", "radio_control"):
        action = data.get("action", "")
        sender = data.get("sender_name", data.get("senderName", device_id))
        state.add_timeline("radio", f"PTT {action} - {sender}", "", device_id)
        await field_broadcast(make_hq_msg("voice_broadcast_rx", {
            "sender_id": device_id, "sender_name": sender, "action": action,
        }), exclude=device_id)
        await ws_broadcast("radio_control", {
            "sender_id": device_id, "sender_name": sender, "action": action,
        })
        await forward_to_backend(msg)

    elif msg_type == "voice_result":
        state.add_timeline("voice", f"語音輸入 from {device_id}",
                          data.get("text", "")[:60], device_id)
        await ws_broadcast("voice_result", data)
        await forward_to_backend(msg)

    elif msg_type == "ping":
        await field_send(writer, make_hq_msg("pong", {
            "connected_devices": len(state.field_clients),
        }))

    elif msg_type == "translate_request":
        asyncio.create_task(_handle_translate(device_id, data, writer))

    else:
        print(f"[CMD] 未知訊息類型: {msg_type} from {device_id}")
        await forward_to_backend(msg)

    # ACK
    if msg_type not in ("ping",):
        try:
            await field_send(writer, make_hq_msg("ack", {"received": msg_type}))
        except Exception:
            pass


def normalize_message(raw: dict) -> dict:
    """相容 WiFiMessage 格式（支援 LGAP msgType/payload 和直接 type/data 兩種格式）"""
    if "msgType" in raw and "payload" in raw:
        msg_type = raw["msgType"]
        payload_str = raw["payload"]
        try:
            inner = json.loads(payload_str) if isinstance(payload_str, str) else payload_str
        except (json.JSONDecodeError, TypeError):
            inner = {}
        if isinstance(inner, dict) and "type" in inner:
            if "timestamp" not in inner:
                inner["timestamp"] = now_iso()
            return inner
        # 支援 camelCase "deviceID" 和 snake_case "device_id"（Android 相容）
        did = "unknown"
        if isinstance(inner, dict):
            did = inner.get("device_id") or inner.get("deviceID") or "unknown"
        # 也檢查頂層 device_id（ping 等訊息可能帶在頂層）
        if did == "unknown":
            did = raw.get("device_id") or raw.get("deviceID") or "unknown"
        return {
            "type": msg_type,
            "data": inner if isinstance(inner, dict) else {},
            "device_id": did,
            "timestamp": inner.get("timestamp", now_iso()) if isinstance(inner, dict) else now_iso(),
        }
    if "timestamp" not in raw:
        raw["timestamp"] = now_iso()
    return raw


async def handle_field_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    addr = writer.get_extra_info("peername")
    print(f"[CMD] 新前線連線: {addr}")
    await ws_broadcast("device_connect", {"address": str(addr)})

    try:
        while True:
            data = await reader.readline()
            if not data:
                break
            try:
                raw = json.loads(data.decode())
                msg = normalize_message(raw)
                await handle_field_message(msg, writer)
            except json.JSONDecodeError:
                print(f"[CMD] 無效 JSON from {addr}")
    except (asyncio.CancelledError, ConnectionResetError):
        pass
    except Exception as e:
        print(f"[CMD] 連線錯誤 {addr}: {e}")
    finally:
        to_remove = [d for d, w in state.field_clients.items() if w is writer]
        for d in to_remove:
            del state.field_clients[d]
            print(f"[CMD] 裝置斷線: {d}")
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        await ws_broadcast("device_disconnect", {
            "devices": to_remove, "device_count": len(state.field_clients),
        })


# ============================================================
# 後端 TCP 橋接 (→ port 9000)
# ============================================================
async def backend_connect_loop():
    """持續嘗試連接後端 TCP"""
    while True:
        try:
            reader, writer = await asyncio.open_connection(BACKEND_HOST, BACKEND_PORT)
            async with state._backend_lock:
                state.backend_writer = writer
                state.backend_reader = reader
            print(f"[BACKEND] 已連線 {BACKEND_HOST}:{BACKEND_PORT}")
            await ws_broadcast("backend_status", {"connected": True})

            # 讀取後端推播
            while True:
                data = await reader.readline()
                if not data:
                    break
                try:
                    msg = json.loads(data.decode())
                    await handle_backend_message(msg)
                except json.JSONDecodeError:
                    pass

        except (ConnectionRefusedError, OSError) as e:
            print(f"[BACKEND] 連線失敗: {e}, 5 秒後重試")
        except Exception as e:
            print(f"[BACKEND] 錯誤: {e}")
        finally:
            async with state._backend_lock:
                state.backend_writer = None
                state.backend_reader = None
            await ws_broadcast("backend_status", {"connected": False})
        await asyncio.sleep(5)


async def handle_backend_message(msg: dict):
    """處理從後端收到的訊息"""
    msg_type = msg.get("type", "")
    data = msg.get("data", {})

    if msg_type == "decision":
        decision = {
            "id": str(uuid.uuid4())[:8],
            "decision": data.get("decision", ""),
            "patients": data.get("patients", []),
            "weather": data.get("weather", {}),
            "trigger": data.get("trigger", ""),
            "timestamp": now_iso(),
        }
        state.decisions.append(decision)
        state.add_timeline("decision", "AI 決策生成", decision["decision"][:80])
        await field_broadcast(make_hq_msg("decision", data))
        await ws_broadcast("decision", decision)

    elif msg_type == "weather_update":
        state.weather = data
        await field_broadcast(make_hq_msg("weather_update", data))
        await ws_broadcast("weather_update", data)

    elif msg_type == "node_status":
        nodes = data.get("nodes", [])
        for n in nodes:
            nid = n.get("node_id", "")
            if nid:
                state.lora_nodes[nid] = n
        await field_broadcast(make_hq_msg("node_status", data))
        await ws_broadcast("node_status", data)

    elif msg_type == "report_summary":
        report = {
            "id": data.get("report_id", str(uuid.uuid4())[:8]),
            "senderName": data.get("sender_name", ""),
            "transcription": data.get("transcription", ""),
            "locationDesc": data.get("location_desc", ""),
            "patientsCount": data.get("patients_count", 0),
            "weather": data.get("weather_snapshot", {}),
            "audioURL": data.get("audio_url", ""),
            "timestamp": now_iso(),
        }
        state.radio_reports.append(report)
        state.add_timeline("report", f"會報 from {report['senderName']}",
                          report['transcription'][:80])
        await field_broadcast(make_hq_msg("report_summary", data))
        await ws_broadcast("report_summary", report)

    elif msg_type == "stats_update":
        state.stats = data
        await ws_broadcast("stats_update", data)

    elif msg_type == "translate_result":
        await ws_broadcast("translate_result", data)

    elif msg_type == "pong":
        pass  # 心跳回覆

    elif msg_type in ("sos_alert", "sos_cancel_alert", "photo_alert",
                       "hazard_report", "patient_warning",
                       "text_broadcast_rx", "read_status"):
        await field_broadcast(msg)
        await ws_broadcast(msg_type, data)

    else:
        print(f"[BACKEND] 收到: {msg_type}")
        await ws_broadcast(msg_type, data)


# ============================================================
# LGAP 音訊伺服器 (port 8005)
# ============================================================
class LGAPHandler:
    def __init__(self):
        self.audio_buffers: dict[str, bytearray] = {}
        self.current_sender: str | None = None

    async def handle_client(self, reader: asyncio.StreamReader,
                           writer: asyncio.StreamWriter):
        addr = writer.get_extra_info("peername")
        sender_id = f"lgap-{addr[0]}:{addr[1]}"
        print(f"[LGAP] 音訊連線: {addr}")
        self.current_sender = sender_id
        buf = bytearray()
        audio_data = bytearray()

        await ws_broadcast("radio_control", {
            "sender_id": sender_id, "action": "start",
        })

        try:
            while True:
                chunk = await reader.read(8192)
                if not chunk:
                    break
                buf.extend(chunk)

                while len(buf) >= 8:
                    magic = struct.unpack_from("<I", buf, 0)[0]
                    if magic != LGAP_MAGIC:
                        buf.pop(0)
                        continue
                    payload_len = struct.unpack_from("<I", buf, 4)[0]
                    if payload_len > 1024 * 1024:
                        buf.clear()
                        break
                    if len(buf) < 8 + payload_len:
                        break
                    pcm = buf[8:8 + payload_len]
                    buf = buf[8 + payload_len:]
                    audio_data.extend(pcm)

        except Exception as e:
            print(f"[LGAP] 錯誤: {e}")
        finally:
            writer.close()
            self.current_sender = None
            await ws_broadcast("radio_control", {
                "sender_id": sender_id, "action": "stop",
            })
            # 嘗試 Whisper 轉錄
            if len(audio_data) > 1600:
                asyncio.create_task(self._transcribe(sender_id, bytes(audio_data)))
            print(f"[LGAP] 音訊斷線: {addr}, {len(audio_data)} bytes")

    async def _transcribe(self, sender_id: str, pcm_data: bytes):
        """呼叫 Whisper 伺服器轉錄"""
        try:
            import io, wave
            wav_buf = io.BytesIO()
            with wave.open(wav_buf, "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(16000)
                wf.writeframes(pcm_data)
            wav_bytes = wav_buf.getvalue()

            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.post(
                    WHISPER_URL,
                    files={"file": ("audio.wav", wav_bytes, "audio/wav")},
                )
                if resp.status_code == 200:
                    result = resp.json()
                    text = result.get("text", result.get("transcription", ""))
                    report = {
                        "id": f"RR-{str(uuid.uuid4())[:8]}",
                        "senderName": sender_id,
                        "transcription": text,
                        "timestamp": now_iso(),
                    }
                    state.radio_reports.append(report)
                    state.add_timeline("radio_transcription",
                                      f"PTT 轉錄完成 - {sender_id}", text[:80])
                    await ws_broadcast("radio_transcription", report)
                    print(f"[LGAP] 轉錄完成: {text[:60]}")
        except Exception as e:
            print(f"[LGAP] 轉錄失敗: {e}")


lgap_handler = LGAPHandler()


# ============================================================
# AI 決策引擎整合 (qwen_server)
# ============================================================
async def _request_ai_decision(data: dict):
    """直接呼叫本地 qwen_server 生成 AI 決策"""
    try:
        # 收集當前傷患資料
        patients = []
        for p in state.patients:
            patients.append({
                "id": p.get("patientId", p.get("patient_id", p.get("id", ""))),
                "breathing_rate": p.get("breathingRate", p.get("breathing_rate", 0)),
                "capillary_refill": p.get("capillaryRefill", p.get("capillary_refill", 0)),
                "can_follow_commands": p.get("canFollowCommands", p.get("can_follow_commands", False)),
                "pulse": p.get("pulse", 0),
                "consciousness": p.get("consciousness", ""),
                "injury_type": p.get("injuryType", p.get("injury_type", "")),
            })

        # 收集氣象資料
        weather = state.weather or {}

        # 收集可用資源
        resources_parts = []
        stats = state._compute_stats()
        resources_parts.append(f"前線人員: {stats.get('fieldDevices', 0)} 人")
        resources_parts.append(f"傷患: {stats.get('totalPatients', 0)} 人")

        voice_text = data.get("context", "") or "請根據目前所有傷患與環境資訊生成決策"

        payload = {
            "voice_text": voice_text,
            "patients": patients,
            "weather": weather,
            "resources": " | ".join(resources_parts),
        }

        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(f"{QWEN_URL}/generate", json=payload)
            if resp.status_code == 200:
                result = resp.json()
                decision_text = result.get("decision", "")
                ranked_patients = result.get("patients", [])
                model_used = result.get("model", "")

                decision = {
                    "id": str(uuid.uuid4())[:8],
                    "decision": decision_text,
                    "patients": ranked_patients,
                    "weather": weather,
                    "model": model_used,
                    "trigger": voice_text[:80],
                    "timestamp": now_iso(),
                }
                state.decisions.append(decision)
                state.add_timeline("decision", "AI 決策生成",
                                  decision_text[:80])
                await field_broadcast(make_hq_msg("decision", {
                    "decision": decision_text,
                    "patients": ranked_patients,
                }))
                await ws_broadcast("decision", decision)
                print(f"[AI] 決策生成完成: {decision_text[:60]}")
            else:
                err = t("err.qwen_status", code=resp.status_code)
                print(f"[AI] 決策失敗: {err}")
                await ws_broadcast("decision_error", {"error": err})

    except httpx.ConnectError:
        err = t("err.ai_unreachable")
        print(f"[AI] {err}")
        await ws_broadcast("decision_error", {"error": err})
    except Exception as e:
        err = t("err.ai_decision_error", err=str(e))
        print(f"[AI] {err}")
        await ws_broadcast("decision_error", {"error": err})


async def _auto_triage_patient(patient: dict):
    """自動呼叫 qwen_server 對新傷患進行 START 檢傷分類"""
    TRIAGE_MAP = {"紅色": "immediate", "黃色": "delayed", "綠色": "minor", "黑色": "expectant"}
    try:
        patient_data = {
            "patient_id": patient.get("patientId", patient.get("patient_id", "")),
            "breathing_rate": patient.get("breathingRate", patient.get("breathing_rate", 0)),
            "capillary_refill": patient.get("capillaryRefill", patient.get("capillary_refill", 0)),
            "can_follow_commands": patient.get("canFollowCommands", patient.get("can_follow_commands", False)),
            "pulse": patient.get("pulse", 0),
        }
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(f"{QWEN_URL}/triage/score",
                                     json={"patient": patient_data})
            if resp.status_code == 200:
                result = resp.json()
                priority_zh = result.get("priority", "")
                triage_en = TRIAGE_MAP.get(priority_zh, priority_zh)
                patient["triage"] = triage_en
                patient["triageReason"] = result.get("reason", "")
                patient["totalScore"] = result.get("total_score", 0)
                await ws_broadcast("patient_triage", {
                    "patient_id": patient_data["patient_id"],
                    "triage": triage_en,
                    "reason": patient["triageReason"],
                    "totalScore": patient["totalScore"],
                })
                print(f"[TRIAGE] {patient_data['patient_id']} → {priority_zh} ({triage_en})")
    except Exception as e:
        print(f"[TRIAGE] 自動分類失敗: {e}")


async def _handle_translate(device_id: str, data: dict,
                            writer: asyncio.StreamWriter):
    """呼叫 qwen_server 翻譯並回傳結果給前線裝置"""
    try:
        payload = {
            "text": data.get("text", ""),
            "source_lang": data.get("source_lang", "auto"),
            "target_lang": data.get("target_lang", "en"),
            "context": data.get("context", "medical"),
        }
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(f"{QWEN_URL}/translate", json=payload)
            if resp.status_code == 200:
                result = resp.json()
                reply = make_hq_msg("translate_result", {
                    "original": result.get("original", ""),
                    "translated": result.get("translated", ""),
                    "source_lang": result.get("detected_lang", ""),
                    "target_lang": result.get("target_lang", ""),
                    "request_id": data.get("request_id", ""),
                })
                await field_send(writer, reply)
                await ws_broadcast("translate_result", result)
            else:
                print(f"[TRANSLATE] 失敗: {resp.status_code}")
    except Exception as e:
        print(f"[TRANSLATE] 翻譯錯誤: {e}")


# ============================================================
# Web 儀表板 (HTTP + WebSocket, port 8080)
# ============================================================
async def ws_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    state.ws_clients.add(ws)
    print(f"[WS] 儀表板連線, 共 {len(state.ws_clients)} 個")

    # 發送完整快照
    try:
        await ws.send_str(json.dumps({
            "type": "snapshot", "data": state.get_snapshot(), "timestamp": now_iso(),
        }, ensure_ascii=False))
    except Exception:
        pass

    try:
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    cmd = json.loads(msg.data)
                    await handle_dashboard_command(cmd, ws)
                except json.JSONDecodeError:
                    pass
            elif msg.type == aiohttp.WSMsgType.ERROR:
                break
    finally:
        state.ws_clients.discard(ws)
        print(f"[WS] 儀表板斷線, 剩 {len(state.ws_clients)} 個")

    return ws


async def handle_dashboard_command(cmd: dict, ws: web.WebSocketResponse):
    """處理儀表板操作指令"""
    action = cmd.get("action", "")
    data = cmd.get("data", {})

    if action == "send_command":
        # HQ 發送搜救命令
        command = {
            "id": state.next_cmd_id(),
            "type": data.get("type", "search"),
            "priority": data.get("priority", 0),
            "title": data.get("title", ""),
            "detail": data.get("detail", ""),
            "sender": "HQ",
            "timestamp": now_iso(),
        }
        state.commands.append(command)
        state.add_timeline("command", f"命令: {command['title']}",
                          command["detail"][:60])
        await field_broadcast(make_hq_msg("command", command))
        await ws_broadcast("command", command)
        await forward_to_backend(make_hq_msg("command", command))

    elif action == "send_chat":
        content_text = data.get("content", "")
        mentions = data.get("mentions") or _parse_mentions(content_text, state.nicknames)
        chat = {
            "id": str(uuid.uuid4())[:8],
            "senderID": "HQ",
            "senderName": "指揮中心",
            "recipientID": data.get("recipientID"),
            "content": content_text,
            "timestamp": now_iso(),
            "isRead": False,
            "mentions": mentions,
        }
        state.chats.append(chat)
        state.add_timeline("chat", "指揮中心發送訊息", chat["content"][:60])
        await field_broadcast(make_hq_msg("chat_message", chat))
        await ws_broadcast("chat_message", chat)
        for did in mentions:
            w = state.field_clients.get(did)
            if w:
                await field_send(w, make_hq_msg("personal_notification", {
                    "id": str(uuid.uuid4())[:8],
                    "target_device": did,
                    "title": "@提及 來自 指揮中心",
                    "content": content_text,
                    "from_chat_id": chat["id"],
                    "timestamp": now_iso(),
                }))

    elif action == "send_notification":
        notif = {
            "id": str(uuid.uuid4())[:8],
            "target_device": data.get("target_device", ""),
            "title": data.get("title", ""),
            "content": data.get("content", ""),
            "timestamp": now_iso(),
        }
        state.notifications.append(notif)
        target = data.get("target_device", "")
        writer = state.field_clients.get(target)
        if writer:
            await field_send(writer, make_hq_msg("personal_notification", notif))
        await ws_broadcast("notification", notif)

    elif action == "text_broadcast":
        tb = {
            "id": state.next_msg_id(),
            "sender_id": "HQ",
            "sender_name": "指揮中心",
            "message": data.get("message", ""),
            "priority": data.get("priority", "normal"),
            "timestamp": now_iso(),
        }
        state.text_broadcasts.append(tb)
        state.add_timeline("broadcast", "文字廣播", tb["message"][:60])
        await field_broadcast(make_hq_msg("text_broadcast_rx", tb))
        await ws_broadcast("text_broadcast", tb)
        await forward_to_backend(make_hq_msg("text_broadcast", {
            "message": tb["message"], "priority": tb["priority"],
            "sender_name": "指揮中心",
        }))

    elif action == "set_victim_priority":
        vid = data.get("victim_id", "")
        if vid in state.victims:
            state.victims[vid]["priority"] = data.get("priority", "unset")
            state.victims[vid]["note"] = data.get("note", "")
            await ws_broadcast("victim_update", state.victims[vid])

    elif action == "update_disaster_site":
        state.disaster_site = data
        state.add_timeline("disaster", "災害現場更新", data.get("buildingName", ""))
        await field_broadcast(make_hq_msg("disaster_update", state.disaster_site))
        await ws_broadcast("disaster_site", state.disaster_site)

    elif action == "assign_personnel":
        assignment = {
            "id": str(uuid.uuid4())[:8],
            "name": data.get("name", ""),
            "assignedZone": data.get("zone", ""),
            "assignedFloor": data.get("floor", ""),
            "role": data.get("role", ""),
            "timestamp": now_iso(),
        }
        # 更新或新增
        found = False
        for i, p in enumerate(state.personnel):
            if p.get("name") == assignment["name"]:
                state.personnel[i] = assignment
                found = True
                break
        if not found:
            state.personnel.append(assignment)
        state.add_timeline("personnel", f"人員配置: {assignment['name']}",
                          f"{assignment['role']} → {assignment['assignedZone']}")
        await field_broadcast(make_hq_msg("personnel_assignment", state.personnel))
        await ws_broadcast("personnel", {"list": state.personnel})

    elif action == "remove_personnel":
        pid = data.get("id", "")
        if pid.startswith("field-"):
            return  # 前線自動同步的人員不可刪除
        state.personnel = [p for p in state.personnel if p.get("id") != pid]
        await field_broadcast(make_hq_msg("personnel_assignment", state.personnel))
        await ws_broadcast("personnel", {"list": state.personnel})

    elif action == "create_task":
        task = {
            "id": str(uuid.uuid4())[:8],
            "title": data.get("title", ""),
            "detail": data.get("detail", ""),
            "assigneeID": data.get("assigneeID", ""),
            "assigneeName": data.get("assigneeName", ""),
            "zone": data.get("zone", ""),
            "priority": data.get("priority", 0),
            "status": "pending",
            "createdAt": time.time(),
            "dueTime": data.get("dueTime"),
        }
        state.tasks.append(task)
        state.add_timeline("task", f"任務指派: {task['title']}", task['detail'][:60])
        # 發送給指定裝置
        target = data.get("assigneeID", "")
        if target and target in state.field_clients:
            await field_send(state.field_clients[target],
                           make_hq_msg("task_assignment", task))
        await ws_broadcast("task_created", task)

    elif action == "create_briefing":
        briefing = {
            "id": str(uuid.uuid4())[:8],
            "title": data.get("title", ""),
            "type": data.get("type", "progress"),
            "author": data.get("author", "HQ"),
            "timestamp": now_iso(),
            "sections": data.get("sections", []),
        }
        state.briefings.append(briefing)
        state.add_timeline("briefing", f"會報: {briefing['title']}",
                          briefing["type"])
        await field_broadcast(make_hq_msg("briefing", briefing))
        await ws_broadcast("briefing", briefing)

    elif action == "dismiss_sos":
        sos_id = data.get("sos_id", "")
        state.sos_alerts = [s for s in state.sos_alerts if s.get("id") != sos_id]
        await field_broadcast(make_hq_msg("sos_cancel_alert", {"sos_id": sos_id, "ack_by": "HQ"}))
        await ws_broadcast("sos_dismissed", {"sos_id": sos_id})

    elif action == "request_decision":
        # 直接呼叫 qwen_server AI 決策引擎
        asyncio.create_task(_request_ai_decision(data))

    elif action == "create_countdown":
        cd = {
            "id": str(uuid.uuid4())[:8],
            "label": data.get("label", "倒數"),
            "seconds": data.get("seconds", 60),
            "target_device": data.get("target_device"),
            "created_at": time.time(),
        }
        state.countdowns.append(cd)
        timer_payload = {
            "id": cd["id"],
            "title": cd["label"],
            "durationSeconds": cd["seconds"],
            "startedAt": cd["created_at"],
            "isBroadcast": not bool(cd.get("target_device")),
            "targetDeviceID": cd.get("target_device") or "",
        }
        target = data.get("target_device")
        if target and target in state.field_clients:
            await field_send(state.field_clients[target],
                           make_hq_msg("timer_sync", timer_payload))
        else:
            await field_broadcast(make_hq_msg("timer_sync", timer_payload))
        await ws_broadcast("countdown", cd)

    elif action == "reinforce_reply":
        req_id = data.get("id", "")
        status = data.get("status", "joined")
        for r in state.reinforcements:
            if r.get("id") == req_id:
                r["status"] = status
                r["respondedBy"].append("HQ")
                break
        await ws_broadcast("reinforcement_update", {"id": req_id, "status": status})

    elif action == "pws_alert":
        alert = {
            "id": str(uuid.uuid4())[:8],
            "alertType": data.get("alertType", "other"),
            "title": data.get("title", ""),
            "content": data.get("content", ""),
            "severity": data.get("severity", "info"),
            "publisher": "HQ",
            "publishTime": time.time(),
            "expireTime": data.get("expireTime"),
            "isActive": True,
        }
        state.pws_alerts.append(alert)
        state.add_timeline("pws", f"PWS 警報: {alert['title']}",
                          alert["content"][:60])
        await field_broadcast(make_hq_msg("pws_alert", alert))
        await ws_broadcast("pws_alert", alert)

    elif action == "set_nickname":
        did = (data.get("device_id") or "").strip()
        nick = (data.get("nickname") or "").strip()
        role = (data.get("role") or "").strip()
        if did and nick:
            entry = {
                "device_id": did,
                "nickname": nick,
                "role": role,
                "updated_at": now_iso(),
            }
            state.nicknames[did] = entry
            try:
                linkguard_db.set_nickname(did, nick, role)
            except Exception as exc:
                print(f"[HQ] set_nickname DB 失敗: {exc}")
            await field_broadcast(make_hq_msg("nickname_update", entry))
            await ws_broadcast("nickname_update", entry)

    elif action == "delete_nickname":
        did = (data.get("device_id") or "").strip()
        if did and did in state.nicknames:
            state.nicknames.pop(did, None)
            try:
                linkguard_db.delete_nickname(did)
            except Exception as exc:
                print(f"[HQ] delete_nickname DB 失敗: {exc}")
            await field_broadcast(make_hq_msg("nickname_remove", {"device_id": did}))
            await ws_broadcast("nickname_remove", {"device_id": did})

    elif action == "get_snapshot":
        await ws.send_str(json.dumps({
            "type": "snapshot", "data": state.get_snapshot(), "timestamp": now_iso(),
        }, ensure_ascii=False))


# ============================================================
# Bonjour 服務註冊
# ============================================================
async def register_bonjour():
    ips = _discover_lan_ips()
    local_ip = ips[0] if ips else "127.0.0.1"
    try:
        info = ServiceInfo(
            "_linkguard-hq._tcp.local.",
            "LinkGuard-HQ._linkguard-hq._tcp.local.",
            addresses=[socket.inet_aton(ip) for ip in ips] or [socket.inet_aton(local_ip)],
            port=COMMAND_PORT,
            properties={
                "role": "HQ",
                "platform": "Windows",
                "dashboard_port": str(DASHBOARD_PORT),
                "command_port": str(COMMAND_PORT),
            },
        )
        zc = Zeroconf()
        await asyncio.to_thread(zc.register_service, info, allow_name_change=True)
        print(f"[Bonjour] 已註冊 HQ 服務 on {', '.join(ips) if ips else local_ip}:{COMMAND_PORT}")
        return zc, info
    except Exception as e:
        print(f"[Bonjour] 註冊失敗: {e}")
        return None, None


# ============================================================
# 定時任務
# ============================================================
async def _fetch_weather():
    """從 pws_fetcher 拉取最新氣象資料"""
    try:
        from pws_fetcher import fetch_weather
        api_key = os.environ.get("CWA_API_KEY",
                                 "CWA-ABB1DE38-E0CD-4EBA-9723-894AAA62AE5E")
        station_id = os.environ.get("CWA_STATION", "C0A980")
        weather = await asyncio.to_thread(fetch_weather, station_id, api_key)
        if weather:
            state.weather = weather
            await field_broadcast(make_hq_msg("weather_update", weather))
            await ws_broadcast("weather_update", weather)
            print(f"[WEATHER] 更新: {weather.get('temperature')}°C, "
                  f"{weather.get('humidity')}%")
    except Exception as e:
        print(f"[WEATHER] 拉取失敗: {e}")


async def periodic_tasks():
    """定時推播統計 + 倒數更新 + 氣象拉取"""
    weather_interval = 0  # 首次立即拉取
    while True:
        await asyncio.sleep(5)
        # 推播統計
        await ws_broadcast("stats_update", state._compute_stats())
        # 清理過期倒數
        now = time.time()
        expired = [c for c in state.countdowns
                   if now - c["created_at"] > c["seconds"]]
        for c in expired:
            state.countdowns.remove(c)
            await ws_broadcast("countdown_expired", c)
        # 每 5 分鐘拉取氣象
        weather_interval += 5
        if weather_interval >= 300:
            weather_interval = 0
            asyncio.create_task(_fetch_weather())


# ============================================================
# 主程式
# ============================================================
async def main():
    # 從 DB 載入暱稱表
    try:
        linkguard_db.init_db()
        for n in linkguard_db.get_all_nicknames():
            did = n.get("device_id")
            if did:
                state.nicknames[did] = n
        print(f"[HQ] 已載入 {len(state.nicknames)} 筆暱稱")
    except Exception as exc:
        print(f"[HQ] 載入暱稱失敗: {exc}")

    # 建立 aiohttp app
    app = web.Application()
    app.router.add_get("/ws", ws_handler)
    # 靜態檔案 (HQ 儀表板)
    if STATIC_DIR.exists():
        async def index_handler(request):
            return web.FileResponse(STATIC_DIR / "index.html")
        app.router.add_get("/", index_handler)
        app.router.add_static("/", STATIC_DIR)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", DASHBOARD_PORT)
    await site.start()
    print(f"[HQ] 儀表板啟動: http://0.0.0.0:{DASHBOARD_PORT}")

    # TCP 命令伺服器
    cmd_server = await asyncio.start_server(
        handle_field_client, "0.0.0.0", COMMAND_PORT)
    print(f"[HQ] 命令伺服器啟動: TCP {COMMAND_PORT}")

    # LGAP 音訊伺服器
    lgap_server = await asyncio.start_server(
        lgap_handler.handle_client, "0.0.0.0", LGAP_PORT)
    print(f"[HQ] LGAP 音訊伺服器: TCP {LGAP_PORT}")

    # Bonjour
    zc, zc_info = await register_bonjour()

    local_ip = get_local_ip()
    print("=" * 50)
    print(f"  LinkGuard Windows HQ 已啟動")
    print(f"  儀表板: http://{local_ip}:{DASHBOARD_PORT}")
    print(f"  命令伺服器: TCP {local_ip}:{COMMAND_PORT}")
    print(f"  LGAP 音訊: TCP {local_ip}:{LGAP_PORT}")
    print(f"  後端橋接: TCP {BACKEND_HOST}:{BACKEND_PORT}")
    print("=" * 50)

    # 啟動背景任務
    tasks = [
        asyncio.create_task(backend_connect_loop()),
        asyncio.create_task(periodic_tasks()),
    ]

    try:
        await asyncio.gather(*tasks)
    except asyncio.CancelledError:
        pass
    finally:
        cmd_server.close()
        lgap_server.close()
        if zc:
            await asyncio.to_thread(zc.unregister_service, zc_info)
            zc.close()
        await runner.cleanup()


if __name__ == "__main__":
    print("[HQ] 正在啟動 LinkGuard Windows HQ...")
    asyncio.run(main())

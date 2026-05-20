"""
utils.py — LinkGuard 共用工具模組
提供跨服務共用的工具函式，避免程式碼重複。
"""

from __future__ import annotations

import json
import os
import socket
import time
import uuid
from datetime import datetime, timezone, timedelta

from fastapi import HTTPException
from fastapi.responses import JSONResponse

TZ_TW = timezone(timedelta(hours=8))

# 服務啟動時間（用於 health check uptime 計算）
_service_start_time = time.monotonic()


def now_iso() -> str:
    """取得 ISO 格式的台灣時區時間戳"""
    return datetime.now(TZ_TW).isoformat()


# === 統一 API 回應格式 ===

def api_ok(data: dict | None = None) -> dict:
    """統一成功回應格式"""
    resp = {"status": "ok", "timestamp": now_iso()}
    if data:
        resp.update(data)
    return resp


def api_error(code: str, message: str, status_code: int = 400):
    """統一錯誤回應 — raise HTTPException"""
    raise HTTPException(
        status_code=status_code,
        detail={
            "status": "error",
            "code": code,
            "message": message,
            "timestamp": now_iso(),
        },
    )


# === 訊息 ID 生成 ===

def generate_msg_id(prefix: str = "MSG") -> str:
    """生成唯一訊息 ID，格式: {prefix}-{YYYYMMDD}-{uuid4短碼}"""
    date_str = datetime.now(TZ_TW).strftime("%Y%m%d")
    short_uuid = uuid.uuid4().hex[:8]
    return f"{prefix}-{date_str}-{short_uuid}"


# === 服務健康檢查 ===

def health_check_response(service_name: str, version: str = "0.1",
                          extras: dict | None = None) -> dict:
    """統一健康檢查回應格式"""
    uptime = round(time.monotonic() - _service_start_time, 1)
    resp = {
        "status": "ok",
        "service": service_name,
        "version": version,
        "uptime_seconds": uptime,
        "timestamp": now_iso(),
    }
    if extras:
        resp.update(extras)
    return resp


def get_local_ip() -> str:
    """取得本機 IP，支援離線環境

    優先順序：
    1. 環境變數 LINKGUARD_SERVER_IP
    2. 閘道探測（離線可用）
    3. 列舉非 loopback 介面
    4. 回傳 127.0.0.1
    """
    env_ip = os.environ.get("LINKGUARD_SERVER_IP")
    if env_ip:
        return env_ip
    for target in ("10.255.255.255", "192.168.50.1", "192.168.1.1", "10.0.0.1", "8.8.8.8"):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect((target, 1))
            ip = s.getsockname()[0]
            if ip and ip != "127.0.0.1":
                return ip
        except OSError:
            continue
        finally:
            s.close()
    try:
        hostname = socket.gethostname()
        addrs = socket.getaddrinfo(hostname, None, socket.AF_INET)
        for addr in addrs:
            ip = addr[4][0]
            if ip and not ip.startswith("127."):
                return ip
    except OSError:
        pass
    return "127.0.0.1"


# === TCP 重試轉發 ===

TCP_SERVER_HOST = "127.0.0.1"
TCP_SERVER_PORT = 9000


def send_to_tcp_with_retry(msg: dict, tag: str = "UTIL",
                           max_retries: int = 3):
    """發送 JSON 訊息到 tcp_server，失敗時指數退避重試。

    Args:
        msg: 要發送的 JSON dict
        tag: 日誌標籤（如 PHOTO, HTTP）
        max_retries: 最大重試次數（預設 3）
    """
    data = json.dumps(msg, ensure_ascii=False) + "\n"
    for attempt in range(1, max_retries + 1):
        s = None
        try:
            s = socket.create_connection(
                (TCP_SERVER_HOST, TCP_SERVER_PORT), timeout=5
            )
            s.sendall(data.encode())
            s.recv(4096)
            return  # 成功
        except Exception as e:
            if attempt < max_retries:
                wait = 2 ** (attempt - 1)  # 1s, 2s, 4s
                print(f"[{tag}] 送 tcp_server 失敗 (第{attempt}次): {e}，"
                      f"{wait}s 後重試")
                time.sleep(wait)
            else:
                print(f"[{tag}] 送 tcp_server 失敗 (已重試{max_retries}次): {e}")
        finally:
            if s is not None:
                try:
                    s.close()
                except Exception:
                    pass

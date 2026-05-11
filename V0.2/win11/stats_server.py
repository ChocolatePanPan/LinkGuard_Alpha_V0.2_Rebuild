"""
stats_server.py — LinkGuard 即時統計伺服器
Port 8005, FastAPI
提供即時統計 API + 定時推播統計更新
"""

import asyncio
import json
import os
import socket
from datetime import datetime, timezone, timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import linkguard_db
from utils import now_iso, send_to_tcp_with_retry, api_ok, health_check_response

TZ_TW = timezone(timedelta(hours=8))
TCP_SERVER_HOST = os.environ.get("TCP_SERVER_HOST", "127.0.0.1")
TCP_SERVER_PORT = 9000
STATS_PUSH_INTERVAL = 60  # 秒

# 事件開始時間（首次啟動記錄）
_event_start_time: datetime | None = None
_ALLOWED_ORIGINS = os.environ.get("CORS_ORIGINS", "http://localhost:8080").split(",")

app = FastAPI(title="LinkGuard Stats Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def _send_to_tcp(msg: dict):
    await asyncio.to_thread(send_to_tcp_with_retry, msg, "STATS")


def _compute_stats() -> dict:
    global _event_start_time

    # 傷患統計
    patient_stats = linkguard_db.get_patient_stats()

    # 資源統計
    resource_summary = linkguard_db.get_resource_summary()
    ambulance = resource_summary.get("ambulance", {"total": 0, "available": 0})
    medical_kit = resource_summary.get("medical_kit", {"total": 0, "available": 0})

    # 通訊統計
    try:
        conn = linkguard_db._get_conn()

        # 最近 1 小時 LoRa 節點狀態
        # DB 中 timestamp 統一由 now_iso() 產生 (TZ_TW ISO 格式)
        # 使用 now_iso 相同格式以確保字串比較一致
        since_1h = (datetime.now(TZ_TW) - timedelta(hours=1)).isoformat()
        nodes = conn.execute(
            "SELECT DISTINCT node_id FROM node_status_log WHERE timestamp >= ? AND online = 1",
            (since_1h,),
        ).fetchall()
        lora_online = len(nodes)

        total_nodes = conn.execute(
            "SELECT COUNT(DISTINCT node_id) as cnt FROM node_status_log"
        ).fetchone()
        lora_total = total_nodes["cnt"] if total_nodes else 0

        # 會報數量
        reports_count = conn.execute("SELECT COUNT(*) as cnt FROM reports").fetchone()["cnt"]

        # 決策數量
        decisions_count = conn.execute("SELECT COUNT(*) as cnt FROM decisions").fetchone()["cnt"]

        # 照片數量
        photos_count = conn.execute("SELECT COUNT(*) as cnt FROM photos").fetchone()["cnt"]

        # 連線裝置數（從 locations 最近 5 分鐘推估）
        since_5m = (datetime.now(TZ_TW) - timedelta(minutes=5)).isoformat()
        wifi_devices = conn.execute(
            "SELECT COUNT(DISTINCT device_id) as cnt FROM locations WHERE timestamp >= ?",
            (since_5m,),
        ).fetchone()["cnt"]

        # 人員統計（從 locations 推估）
        personnel = conn.execute(
            "SELECT role, COUNT(DISTINCT device_id) as cnt FROM locations "
            "WHERE timestamp >= ? GROUP BY role",
            (since_5m,),
        ).fetchall()
        personnel_dict = {r["role"]: r["cnt"] for r in personnel}

        conn.close()
    except Exception as e:
        print(f"[STATS] 查詢失敗: {e}")
        lora_online = lora_total = reports_count = decisions_count = 0
        photos_count = wifi_devices = 0
        personnel_dict = {}

    # 事件持續時間
    if _event_start_time is None:
        _event_start_time = datetime.now(TZ_TW)
    duration_minutes = int((datetime.now(TZ_TW) - _event_start_time).total_seconds() / 60)

    personnel_total = sum(personnel_dict.values())

    return {
        "timestamp": now_iso(),
        "patients": patient_stats,
        "personnel": {
            "total": personnel_total,
            "rescuer": personnel_dict.get("rescuer", 0) + personnel_dict.get("EMT", 0),
            "medical": personnel_dict.get("medical", 0),
            "commander": personnel_dict.get("commander", 0),
        },
        "resources": {
            "ambulance_total": ambulance["total"],
            "ambulance_available": ambulance["available"],
            "medical_kit_total": medical_kit["total"],
            "medical_kit_used": medical_kit["total"] - medical_kit["available"],
        },
        "communications": {
            "lora_nodes_online": lora_online,
            "lora_nodes_total": max(lora_total, lora_online),
            "wifi_devices": wifi_devices,
            "reports_count": reports_count,
        },
        "decisions_count": decisions_count,
        "photos_count": photos_count,
        "event_duration_minutes": duration_minutes,
    }


# === 路由 ===

@app.get("/stats")
async def get_stats():
    return api_ok(_compute_stats())


@app.get("/stats/history")
async def get_stats_history(hours: int = 1):
    """回傳過去 N 小時的事件歷史（用系統事件做時間軸）"""
    since = (datetime.now(TZ_TW) - timedelta(hours=hours)).isoformat()
    events = linkguard_db.get_events_since(since)
    return api_ok({"events": events, "since": since})


# === 定時推播 ===

_last_pushed_stats: dict | None = None


async def _periodic_stats_push():
    """每 60 秒推播統計到 tcp_server，無變化則跳過"""
    global _last_pushed_stats
    while True:
        await asyncio.sleep(STATS_PUSH_INTERVAL)
        try:
            stats = _compute_stats()
            # 跳過無變化的推播（比對數據內容，排除 timestamp）
            stats_for_cmp = {k: v for k, v in stats.items() if k != "timestamp"}
            if _last_pushed_stats == stats_for_cmp:
                continue
            _last_pushed_stats = stats_for_cmp
            await _send_to_tcp({
                "type": "stats_update",
                "device_id": "stats-server",
                "timestamp": now_iso(),
                "data": stats,
            })
        except Exception as e:
            print(f"[STATS] 定時推播失敗: {e}")


@app.on_event("startup")
async def startup():
    linkguard_db.init_db()
    asyncio.create_task(_periodic_stats_push())
    print("[STATS] Stats server 已啟動，每 60 秒推播更新（無變化則跳過）")


@app.get("/health")
def health():
    db_ok = False
    try:
        conn = linkguard_db._get_conn()
        conn.execute("SELECT 1")
        conn.close()
        db_ok = True
    except Exception:
        pass
    return health_check_response("stats-server", extras={"db_connected": db_ok})


@app.get("/health/all")
async def health_all():
    """聚合所有服務的健康狀態"""
    import httpx
    services = {
        "http-server": "http://127.0.0.1:8003/health",
        "photo-server": "http://127.0.0.1:8004/health",
        "stats-server": "http://127.0.0.1:8005/health",
        "resource-server": "http://127.0.0.1:8006/health",
        "whisper-server": "http://127.0.0.1:8002/health",
        "qwen-server": "http://127.0.0.1:8001/health",
    }
    results = {}
    async with httpx.AsyncClient(timeout=3) as client:
        for name, url in services.items():
            try:
                resp = await client.get(url)
                results[name] = resp.json()
            except Exception as e:
                results[name] = {"status": "error", "message": str(e)}
    all_ok = all(r.get("status") == "ok" for r in results.values())
    return {
        "status": "ok" if all_ok else "degraded",
        "timestamp": now_iso(),
        "services": results,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8005)

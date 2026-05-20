from __future__ import annotations

import asyncio
import json
import os
import shutil
import socket
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
import httpx

import linkguard_db
from utils import get_local_ip, now_iso, send_to_tcp_with_retry, health_check_response
from i18n import t

import threading
import uuid

_report_id_lock = threading.Lock()

TZ_TW = timezone(timedelta(hours=8))
AUDIO_DIR = Path("./reports/audio")
PENDING_DIR = Path("./reports/pending")
_WHISPER_HOST = os.environ.get("WHISPER_HOST", "localhost")
WHISPER_URL = f"http://{_WHISPER_HOST}:8002/transcribe"
TCP_SERVER_HOST = os.environ.get("TCP_SERVER_HOST", "127.0.0.1")
TCP_SERVER_PORT = 9000
RETRY_INTERVAL = 60   # 秒
MAX_RETRIES = 3
MAX_AUDIO_SIZE = 50 * 1024 * 1024  # 50 MB
_ALLOWED_ORIGINS = os.environ.get("CORS_ORIGINS", "http://localhost:8080").split(",")

# === FastAPI App ===
app = FastAPI(title="LinkGuard Report Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)



# === 資料庫（委託 linkguard_db） ===

def init_db():
    linkguard_db.init_db()


def next_report_id() -> str:
    """生成 RPT-YYYYMMDD-NNN-xxxx 格式的 report_id（含 UUID 短碼防碰撞）"""
    with _report_id_lock:
        today = datetime.now(TZ_TW).strftime("%Y%m%d")
        usuf = uuid.uuid4().hex[:4]
        prefix = f"RPT-{today}-"
        conn = linkguard_db._get_conn()
        try:
            row = conn.execute(
                "SELECT report_id FROM reports WHERE report_id LIKE ? ORDER BY report_id DESC LIMIT 1",
                (f"{prefix}%",),
            ).fetchone()
        finally:
            conn.close()
        if row:
            parts = row["report_id"].split("-")
            try:
                last_num = int(parts[2]) if len(parts) >= 3 else 0
            except (ValueError, IndexError):
                last_num = 0
            return f"{prefix}{last_num + 1:03d}-{usuf}"
        return f"{prefix}001-{usuf}"


def save_report(report_id: str, sender_id: str, sender_name: str,
                audio_path: str, transcription: str,
                lat: float, lon: float, location_desc: str,
                patients_snapshot: str, weather_snapshot: str):
    linkguard_db.save_report({
        "report_id": report_id,
        "sender_id": sender_id,
        "sender_name": sender_name,
        "audio_path": audio_path,
        "transcription": transcription,
        "location_lat": lat,
        "location_lon": lon,
        "location_desc": location_desc,
        "patients_snapshot": patients_snapshot,
        "weather_snapshot": weather_snapshot,
    })


# === TCP 轉送 ===

def _build_report_summary_msg(report_id: str, sender_name: str,
                              transcription: str, location_desc: str,
                              patients_count: int, weather: dict) -> dict:
    """建立會報摘要訊息 dict"""
    local_ip = get_local_ip()
    return {
        "type": "report_summary",
        "device_id": "http-server",
        "timestamp": time.time(),
        "data": {
            "report_id": report_id,
            "sender_name": sender_name,
            "transcription": transcription,
            "timestamp": time.time(),
            "location_desc": location_desc,
            "patients_count": patients_count,
            "weather": weather,
            "audio_url": f"http://{local_ip}:8003/audio/{report_id}",
        },
    }


async def send_report_summary_to_tcp(report_id: str, sender_name: str,
                               transcription: str, location_desc: str,
                               patients_count: int, weather: dict):
    """將會報摘要送到 tcp_server 推播（非同步，含重試）"""
    msg = _build_report_summary_msg(
        report_id, sender_name, transcription,
        location_desc, patients_count, weather,
    )
    await asyncio.to_thread(send_to_tcp_with_retry, msg, "HTTP")



# === 啟動 ===

@app.on_event("startup")
async def startup():
    init_db()
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    PENDING_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[HTTP] 報告資料庫: linkguard_db (統一)")
    print(f"[HTTP] 音訊目錄: {AUDIO_DIR.resolve()}")
    print(f"[HTTP] 暂存目錄: {PENDING_DIR.resolve()}")
    asyncio.create_task(retry_pending())


# === 路由 ===

@app.post("/report")
async def upload_report(
    audio: UploadFile = File(...),
    device_id: str = Form(...),
    sender_name: str = Form(""),
    location_lat: float = Form(0.0),
    location_lon: float = Form(0.0),
    location_desc: str = Form(""),
    patients_snapshot: str = Form("[]"),
    weather_snapshot: str = Form("{}"),
    timestamp: str = Form(""),
):
    report_id = next_report_id()

    # 1. 存音訊檔
    audio_filename = f"{report_id}.m4a"
    audio_path = AUDIO_DIR / audio_filename
    # 分塊讀取，防止超大檔案 OOM
    chunks = []
    total = 0
    while True:
        chunk = await audio.read(1024 * 1024)  # 1 MB
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_AUDIO_SIZE:
            raise HTTPException(status_code=413, detail=t("err.audio_too_large", limit=MAX_AUDIO_SIZE // (1024*1024)))
        chunks.append(chunk)
    audio_bytes = b"".join(chunks)
    audio_path.write_bytes(audio_bytes)

    # 2. 送 Whisper 轉錄
    transcription = ""
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(
                WHISPER_URL,
                files={"file": (audio_filename, audio_bytes, "audio/mp4")},
                data={"source": "report", "sender_id": device_id},
            )
            if resp.status_code == 200:
                transcription = resp.json().get("text", "")
    except httpx.TimeoutException:
        print(f"[HTTP] Whisper 轉錄逾時 (120s)，暫存到 pending: {report_id}")
        _save_pending(report_id, audio_bytes, device_id, sender_name,
                      location_lat, location_lon, location_desc,
                      patients_snapshot, weather_snapshot, timestamp)
    except Exception as e:
        print(f"[HTTP] Whisper 轉錄失敗: {e}")
        # 轉錄失敗時暂存到 pending
        _save_pending(report_id, audio_bytes, device_id, sender_name,
                      location_lat, location_lon, location_desc,
                      patients_snapshot, weather_snapshot, timestamp)

    # 3. 存 SQLite
    save_report(
        report_id, device_id, sender_name, str(audio_path),
        transcription, location_lat, location_lon, location_desc,
        patients_snapshot, weather_snapshot,
    )

    # 3b. 儲存轉錄到 transcriptions 表
    if transcription:
        linkguard_db.save_transcription(
            sender_id=device_id, text=transcription,
            source="report", report_id=report_id,
        )

    # 3c. 備份音訊到 USB
    try:
        from usb_backup import sync_audio
        sync_audio(report_id)
    except Exception as e:
        print(f"[HTTP] USB 音訊備份失敗: {e}")

    # 4. 解析 weather/patients 供推播
    try:
        weather_dict = json.loads(weather_snapshot)
    except (json.JSONDecodeError, TypeError):
        weather_dict = {}
    try:
        patients_list = json.loads(patients_snapshot)
        patients_count = len(patients_list)
    except (json.JSONDecodeError, TypeError):
        patients_count = 0

    # 5. 推播到 tcp_server
    await send_report_summary_to_tcp(
        report_id, sender_name, transcription,
        location_desc, patients_count, weather_dict,
    )

    print(f"[HTTP] 會報已儲存: {report_id}")

    return {
        "status": "ok",
        "report_id": report_id,
        "transcription": transcription,
        "timestamp": now_iso(),
    }


@app.get("/audio/{report_id}")
async def get_audio(report_id: str):
    # 防止路徑遍歷攻擊
    import re
    if not re.match(r"^RPT-\d{8}-\d{3}(-[0-9a-f]{4})?$", report_id):
        raise HTTPException(status_code=400, detail=t("err.invalid_report_id"))
    audio_path = (AUDIO_DIR / f"{report_id}.m4a").resolve()
    if not audio_path.is_relative_to(AUDIO_DIR.resolve()):
        raise HTTPException(status_code=400, detail=t("err.invalid_report_id"))
    if not audio_path.exists():
        raise HTTPException(status_code=404, detail=t("err.audio_not_found"))
    return FileResponse(str(audio_path), media_type="audio/mp4")


@app.get("/reports")
async def list_reports():
    reports = linkguard_db.get_reports(limit=20)
    return {"reports": reports}


# === Pending 暂存 / 重試 ===

def _save_pending(report_id: str, audio_bytes: bytes, device_id: str,
                  sender_name: str, lat: float, lon: float,
                  location_desc: str, patients_snapshot: str,
                  weather_snapshot: str, timestamp: str):
    """將轉錄失敗的會報暂存到 pending 目錄"""
    entry_dir = PENDING_DIR / report_id
    entry_dir.mkdir(parents=True, exist_ok=True)
    (entry_dir / "audio.m4a").write_bytes(audio_bytes)
    (entry_dir / "meta.json").write_text(json.dumps({
        "report_id": report_id,
        "device_id": device_id,
        "sender_name": sender_name,
        "location_lat": lat,
        "location_lon": lon,
        "location_desc": location_desc,
        "patients_snapshot": patients_snapshot,
        "weather_snapshot": weather_snapshot,
        "timestamp": timestamp,
        "retry_count": 0,
    }, ensure_ascii=False), encoding="utf-8")
    print(f"[HTTP] 已暂存 pending: {report_id}")


async def retry_pending():
    """背景任務：每 60 秒重試 pending 目錄中的會報，最多重試 3 次"""
    while True:
        await asyncio.sleep(RETRY_INTERVAL)
        if not PENDING_DIR.exists():
            continue
        for entry in PENDING_DIR.iterdir():
            if not entry.is_dir():
                continue
            meta_file = entry / "meta.json"
            audio_file = entry / "audio.m4a"
            if not meta_file.exists() or not audio_file.exists():
                continue

            meta = json.loads(meta_file.read_text(encoding="utf-8"))
            retry_count = meta.get("retry_count", 0)
            if retry_count >= MAX_RETRIES:
                print(f"[HTTP] 重試次數已達上限，移除: {entry.name}")
                shutil.rmtree(entry)
                continue

            report_id = meta["report_id"]
            audio_bytes = audio_file.read_bytes()

            try:
                async with httpx.AsyncClient(timeout=60) as client:
                    files = {"file": ("audio.m4a", audio_bytes, "audio/mp4")}
                    data = {"source": "report", "sender_id": meta["device_id"]}
                    resp = await client.post(WHISPER_URL, files=files, data=data)
                    resp.raise_for_status()
                    transcription = resp.json().get("text", "")

                # 更新 DB 轉錄結果
                conn = linkguard_db._get_conn()
                conn.execute(
                    "UPDATE reports SET transcription = ? WHERE report_id = ?",
                    (transcription, report_id),
                )
                conn.commit()
                conn.close()

                # 儲存轉錄
                linkguard_db.save_transcription(
                    sender_id=meta["device_id"], text=transcription,
                    source="report", report_id=report_id,
                )

                # 重新推播摘要
                try:
                    patients_count = len(json.loads(meta.get("patients_snapshot", "[]")))
                except (json.JSONDecodeError, TypeError):
                    patients_count = 0
                try:
                    weather_dict = json.loads(meta.get("weather_snapshot", "{}"))
                except (json.JSONDecodeError, TypeError):
                    weather_dict = {}

                await send_report_summary_to_tcp(
                    report_id, meta["sender_name"], transcription,
                    meta["location_desc"], patients_count, weather_dict,
                )

                shutil.rmtree(entry)
                print(f"[HTTP] 重試成功: {report_id}")
            except Exception as e:
                meta["retry_count"] = retry_count + 1
                meta_file.write_text(
                    json.dumps(meta, ensure_ascii=False), encoding="utf-8"
                )
                print(f"[HTTP] 重試失敗 ({retry_count + 1}/{MAX_RETRIES}): {report_id}: {e}")


# === 報告生成 ===

class ReportRequest:
    pass


@app.post("/generate_report")
async def api_generate_report(
    event_name: str = Form("LinkGuard Event Report"),
    start_time: str = Form(""),
    end_time: str = Form(""),
    include_photos: bool = Form(True),
    include_audio: bool = Form(True),
):
    """生成 PDF 事件報告"""
    try:
        from report_generator import generate_report
        filepath = generate_report(
            event_name=event_name,
            start_time=start_time,
            end_time=end_time,
            include_photos=include_photos,
            include_audio=include_audio,
        )
        filename = os.path.basename(filepath)
        local_ip = get_local_ip()
        return {
            "status": "ok",
            "filename": filename,
            "download_url": f"http://{local_ip}:8003/download_report/{filename}",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=t("err.report_gen_failed", err=str(e)))


@app.get("/download_report/{filename}")
async def download_report(filename: str, token: str | None = None):
    """下載 PDF 報告（需 token，若 REPORT_API_TOKEN 未設定則僅做檔名驗證）"""
    import re
    expected = os.environ.get("REPORT_API_TOKEN", "").strip()
    if expected and token != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")
    if not re.match(r"^event_\d{8}_\d{6}\.pdf$", filename):
        raise HTTPException(status_code=400, detail=t("err.invalid_report_name"))
    filepath = (Path("./reports") / filename).resolve()
    reports_root = Path("./reports").resolve()
    if not str(filepath).startswith(str(reports_root) + os.sep):
        raise HTTPException(status_code=400, detail=t("err.invalid_report_name"))
    if not filepath.exists():
        raise HTTPException(status_code=404, detail=t("err.report_not_found"))
    return FileResponse(str(filepath), media_type="application/pdf",
                        filename=filename)


DASHBOARD_DIR = Path(__file__).parent / "dashboard"


@app.get("/dashboard")
async def dashboard_page():
    """提供 Web Dashboard 頁面"""
    index = DASHBOARD_DIR / "index.html"
    if not index.exists():
        raise HTTPException(status_code=404, detail=t("err.dashboard_not_found"))
    return FileResponse(str(index), media_type="text/html")


@app.get("/health")
def health():
    reports_writable = AUDIO_DIR.exists() and os.access(str(AUDIO_DIR), os.W_OK)
    pending_count = len(list(PENDING_DIR.iterdir())) if PENDING_DIR.exists() else 0
    return health_check_response(
        "http-server",
        extras={
            "reports_writable": reports_writable,
            "pending_retries": pending_count,
        },
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8003)

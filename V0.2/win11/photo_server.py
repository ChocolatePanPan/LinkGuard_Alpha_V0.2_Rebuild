"""
photo_server.py — LinkGuard 照片回報伺服器
Port 8004, FastAPI
接收現場照片、壓縮儲存、生成縮圖、廣播通知
"""

import asyncio
import io
import json
import os
import re
import socket
import shutil
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from PIL import Image

import linkguard_db
from utils import get_local_ip, now_iso, send_to_tcp_with_retry, health_check_response
from usb_backup import sync_photo, sync_radio, sync_audio
from i18n import t

import threading

TZ_TW = timezone(timedelta(hours=8))
PHOTO_DIR = Path("./photos")
RADIO_DIR = Path("./radio")
AUDIO_DIR = Path("./reports/audio")
THUMB_DIR = Path("./photos/thumbs")
TCP_SERVER_HOST = os.environ.get("TCP_SERVER_HOST", "127.0.0.1")
TCP_SERVER_PORT = 9000
MAX_IMAGE_BYTES = 1 * 1024 * 1024  # 1 MB
MAX_PHOTO_UPLOAD = 10 * 1024 * 1024  # 10 MB 上傳上限
THUMB_SIZE = (300, 300)
_photo_id_lock = threading.Lock()
_ALLOWED_ORIGINS = os.environ.get("CORS_ORIGINS", "http://localhost:8080").split(",")

app = FastAPI(title="LinkGuard Photo Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)



def _next_photo_id() -> str:
    with _photo_id_lock:
        today = datetime.now(TZ_TW).strftime("%Y%m%d")
        usuf = uuid.uuid4().hex[:4]
        prefix = f"PHO-{today}-"
        conn = linkguard_db._get_conn()
        try:
            row = conn.execute(
                "SELECT photo_id FROM photos WHERE photo_id LIKE ? ORDER BY photo_id DESC LIMIT 1",
                (f"{prefix}%",),
            ).fetchone()
        finally:
            conn.close()
        if row:
            # 取序號部分（排除微秒後綴）
            parts = row["photo_id"].split("-")
            try:
                last_num = int(parts[3]) if len(parts) >= 4 else 0
            except (ValueError, IndexError):
                last_num = 0
            return f"{prefix}{last_num + 1:03d}-{usuf}"
        return f"{prefix}001-{usuf}"


def _compress_image(data: bytes) -> bytes:
    """壓縮圖片到 MAX_IMAGE_BYTES 以內"""
    try:
        img = Image.open(io.BytesIO(data))
        if img.mode != "RGB":
            img = img.convert("RGB")
            
        quality = 85
        while quality >= 20:
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=quality, optimize=True)
            if buf.tell() <= MAX_IMAGE_BYTES:
                return buf.getvalue()
            quality -= 10
            
        # 最後手段：縮小尺寸
        img.thumbnail((1920, 1920))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=50, optimize=True)
        return buf.getvalue()
    except Exception as e:
        raise HTTPException(status_code=400, detail=t("err.invalid_image", err=str(e)))


def _make_thumbnail(data: bytes) -> bytes:
    """生成 300x300 縮圖"""
    try:
        img = Image.open(io.BytesIO(data))
        if img.mode != "RGB":
            img = img.convert("RGB")
        img.thumbnail(THUMB_SIZE)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=75)
        return buf.getvalue()
    except Exception as e:
        raise HTTPException(status_code=400, detail=t("err.thumb_gen_failed", err=str(e)))


async def _send_to_tcp(msg: dict):
    """發送訊息到 tcp_server 用於廣播（非同步，含重試）"""
    await asyncio.to_thread(send_to_tcp_with_retry, msg, "PHOTO")


# === 啟動 ===

@app.on_event("startup")
async def startup():
    linkguard_db.init_db()
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)
    THUMB_DIR.mkdir(parents=True, exist_ok=True)
    RADIO_DIR.mkdir(parents=True, exist_ok=True)
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[PHOTO] 照片目錄: {PHOTO_DIR.resolve()}")
    print(f"[PHOTO] 縮圖目錄: {THUMB_DIR.resolve()}")
    print(f"[PHOTO] 電台錄音目錄: {RADIO_DIR.resolve()}")
    print(f"[PHOTO] 災情錄音目錄: {AUDIO_DIR.resolve()}")


# === 路由 ===

@app.post("/photo")
async def upload_photo(
    photo: UploadFile = File(...),
    device_id: str = Form(...),
    sender_name: str = Form(""),
    lat: float = Form(0.0),
    lon: float = Form(0.0),
    location_desc: str = Form(""),
    caption: str = Form(""),
    timestamp: str = Form(""),
):
    photo_id = _next_photo_id()
    # 分塊讀取，防止超大檔案 OOM
    chunks = []
    total = 0
    while True:
        chunk = await photo.read(1024 * 1024)  # 1 MB
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_PHOTO_UPLOAD:
            raise HTTPException(status_code=413, detail=t("err.photo_too_large", limit=MAX_PHOTO_UPLOAD // (1024*1024)))
        chunks.append(chunk)
    raw_bytes = b"".join(chunks)

    # 1. 壓縮原圖
    compressed = _compress_image(raw_bytes)
    photo_path = PHOTO_DIR / f"{photo_id}.jpg"
    photo_path.write_bytes(compressed)

    # 2. 生成縮圖
    thumb_bytes = _make_thumbnail(compressed)
    thumb_path = THUMB_DIR / f"{photo_id}.jpg"
    thumb_path.write_bytes(thumb_bytes)

    # 3. 寫入 DB
    linkguard_db.save_photo({
        "photo_id": photo_id,
        "timestamp": timestamp or now_iso(),
        "sender_id": device_id,
        "sender_name": sender_name,
        "photo_path": str(photo_path),
        "lat": lat,
        "lon": lon,
        "location_desc": location_desc,
        "caption": caption,
    })

    # 4. 記錄系統事件
    linkguard_db.log_event(
        "photo", device_id,
        f"照片回報: {photo_id} from {sender_name} at ({lat},{lon}) {caption}",
        "info",
    )

    # 5. 廣播 photo_alert 到 tcp_server
    local_ip = get_local_ip()
    alert_data = {
        "photo_id": photo_id,
        "sender_id": device_id,
        "sender_name": sender_name,
        "lat": lat,
        "lon": lon,
        "location_desc": location_desc,
        "caption": caption,
        "thumbnail_url": f"http://{local_ip}:8004/thumb/{photo_id}",
        "full_url": f"http://{local_ip}:8004/photo/{photo_id}",
    }
    await _send_to_tcp({
        "type": "photo_alert",
        "device_id": "photo-server",
        "timestamp": now_iso(),
        "data": alert_data,
    })

    # 6. USB 備份
    try:
        sync_photo(photo_id)
    except Exception as e:
        print(f"[PHOTO] USB 備份失敗: {e}")

    print(f"[PHOTO] 照片已儲存: {photo_id} ({len(compressed)} bytes)")

    return {
        "status": "ok",
        "photo_id": photo_id,
        "thumbnail_url": f"http://{local_ip}:8004/thumb/{photo_id}",
        "full_url": f"http://{local_ip}:8004/photo/{photo_id}",
    }


@app.get("/photo/{photo_id}")
async def get_photo(photo_id: str):
    if not re.match(r"^PHO-\d{8}-\d{3}-[0-9a-f]{4}$", photo_id):
        raise HTTPException(status_code=400, detail=t("err.invalid_photo_id"))
    path = (PHOTO_DIR / f"{photo_id}.jpg").resolve()
    if not path.is_relative_to(PHOTO_DIR.resolve()):
        raise HTTPException(status_code=400, detail=t("err.invalid_photo_id"))
    if not path.exists():
        raise HTTPException(status_code=404, detail=t("err.photo_not_found"))
    return FileResponse(str(path), media_type="image/jpeg")


@app.get("/thumb/{photo_id}")
async def get_thumbnail(photo_id: str):
    if not re.match(r"^PHO-\d{8}-\d{3}-[0-9a-f]{4}$", photo_id):
        raise HTTPException(status_code=400, detail=t("err.invalid_photo_id"))
    path = (THUMB_DIR / f"{photo_id}.jpg").resolve()
    if not path.is_relative_to(THUMB_DIR.resolve()):
        raise HTTPException(status_code=400, detail=t("err.invalid_photo_id"))
    if not path.exists():
        raise HTTPException(status_code=404, detail=t("err.thumb_not_found"))
    return FileResponse(str(path), media_type="image/jpeg")


@app.get("/photos")
async def list_photos(limit: int = 20):
    photos = linkguard_db.get_photos(limit=limit)
    local_ip = get_local_ip()
    for p in photos:
        pid = p.get("photo_id", "")
        p["thumbnail_url"] = f"http://{local_ip}:8004/thumb/{pid}"
        p["full_url"] = f"http://{local_ip}:8004/photo/{pid}"
    return {"photos": photos}


_SAFE_FILENAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def _safe_join(base: Path, filename: str) -> Path:
    """安全地組合 base / filename：拒絕任何路徑分隔符或穿越字元。"""
    if not filename or not _SAFE_FILENAME_RE.match(filename):
        raise HTTPException(status_code=400, detail="Invalid filename")
    candidate = (base / filename).resolve()
    base_resolved = base.resolve()
    if not str(candidate).startswith(str(base_resolved) + os.sep) and candidate != base_resolved:
        raise HTTPException(status_code=400, detail="Invalid filename")
    return candidate


@app.post("/radio_backup")
async def radio_backup(
    file: UploadFile = File(...),
    device_id: str = Form(...),
):
    filename = file.filename
    if not filename:
        raise HTTPException(status_code=400, detail="Missing filename")

    save_path = _safe_join(RADIO_DIR, filename)
    base_name = Path(save_path.name).stem

    with open(save_path, "wb") as f:
        shutil.copyfileobj(file.file, f)
        
    try:
        sync_radio(base_name)
    except Exception as e:
        print(f"[PHOTO] USB 電台備份失敗: {e}")
        
    return {"status": "ok", "filename": filename}

@app.post("/audio_backup")
async def audio_backup(
    file: UploadFile = File(...),
    report_id: str = Form(...),
):
    filename = file.filename
    if not filename:
        raise HTTPException(status_code=400, detail="Missing filename")

    # report_id 必須符合 RPT-YYYYMMDD-NNN-xxxx 格式才允許入檔名
    if not re.match(r"^RPT-\d{8}-\d{3}-[0-9a-f]{4}$", report_id):
        raise HTTPException(status_code=400, detail="Invalid report_id")

    file_ext = Path(filename).suffix
    if file_ext.lower() not in {".m4a", ".wav", ".mp3", ".aac", ".caf"}:
        raise HTTPException(status_code=400, detail="Invalid audio extension")

    save_path = _safe_join(AUDIO_DIR, f"{report_id}{file_ext}")
        
    with open(save_path, "wb") as f:
        shutil.copyfileobj(file.file, f)
        
    try:
        sync_audio(report_id)
    except Exception as e:
        print(f"[PHOTO] USB 災情備份失敗: {e}")
        
    return {"status": "ok", "filename": save_path.name}


@app.get("/health")
def health():
    photos_writable = PHOTO_DIR.exists() and os.access(str(PHOTO_DIR), os.W_OK)
    thumbs_writable = THUMB_DIR.exists() and os.access(str(THUMB_DIR), os.W_OK)
    return health_check_response(
        "photo-server",
        extras={
            "photos_writable": photos_writable,
            "thumbs_writable": thumbs_writable,
        },
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8004)
